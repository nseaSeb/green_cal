defmodule GreenCal.Astro.RiseSet do
  @moduledoc """
  Generic search for rises, sets and meridian transits.

  ## Why a numeric search rather than a closed-form formula

  The classic hour-angle formula (`cos H = (sin h₀ − sin φ sin δ) /
  (cos φ cos δ)`) assumes δ constant over the day. That is acceptable for
  the Sun, where it holds to the minute. For the Moon it is wrong: its
  right ascension advances up to 15°/day and its declination up to 5°/day.
  A closed-form moonrise can be off by more than a quarter of an hour.

  So we sample the body's altitude hour by hour, spot sign changes of
  `altitude − h₀`, then refine by bisection. The same code serves the Sun,
  the Moon and the twilights — you only provide a function
  `jd_ut -> {α, δ, h₀}`, and the result's accuracy is then limited only by
  the underlying ephemeris.

  ## Mind the time scale

  `body_fun` receives a Julian day in **UT**. Applying ΔT before calling
  the ephemeris series is its responsibility. Sidereal time, on the other
  hand, is computed here from the received UT — as it must be.
  """

  import GreenCal.Astro.Time, only: [gast: 1, norm360: 1, norm180: 1, sin_d: 1, cos_d: 1, rad: 0]

  alias GreenCal.Astro.Numeric

  @deg 180.0 / :math.pi()

  @typedoc """
  Function describing the observed body: receives a UT Julian day, returns
  right ascension, declination (degrees) and the reference altitude `h₀` of
  the searched phenomenon (degrees).
  """
  @type body_fun :: (float() -> {float(), float(), float()})

  @typedoc "A horizon or meridian event."
  @type event :: %{
          type: :rise | :set | :transit,
          jd: float(),
          azimuth: float(),
          altitude: float()
        }

  @typedoc """
  Result of a search.

  `:state` is `:normal`, or `:always_above` / `:always_below` when the body
  never crosses the horizon over the window: midnight sun, polar night, a
  twilight that does not occur, or simply a Moon that does not rise that
  day (which happens about one day in 27).
  """
  @type result :: %{state: :normal | :always_above | :always_below, events: [event()]}

  @doc """
  Searches for events of a body between two UT Julian days.

  Crossings shorter than the sampling step are still caught: the altitude
  can only peak at a culmination, so every sampled interval that contains
  one is probed at the culmination itself before being declared
  crossing-free. A 55-minute polar day between two hourly samples is found,
  not skipped.

  Options:

    * `:step` — sampling step in days (default `1/24`, i.e. 1 h).
    * `:tolerance` — bisection precision in days (default `1.0e-7`,
      i.e. ≈ 9 ms).
    * `:transits` — include meridian transits (default `true`).
  """
  @spec search(body_fun(), {number(), number()}, float(), float(), keyword()) :: result()
  def search(body_fun, {lat, lon}, jd_from, jd_to, opts \\ []) do
    tol = Keyword.get(opts, :tolerance, 1.0e-7)
    with_transits? = Keyword.get(opts, :transits, true)

    n = max(ceil((jd_to - jd_from) / Keyword.get(opts, :step, 1.0 / 24.0)), 1)
    step = (jd_to - jd_from) / n

    # One body_fun evaluation per sample: dh and ha are derived from the
    # same {ra, dec, h0}.
    eval = fn jd ->
      {ra, dec, h0} = body_fun.(jd)
      %{jd: jd, dh: altitude(jd, lat, lon, ra, dec) - h0, ha: hour_angle(jd, lon, ra)}
    end

    dh_at = fn jd -> eval.(jd).dh end
    ha_at = fn jd -> eval.(jd).ha end

    samples = for i <- 0..n, do: eval.(jd_from + i * step)

    horizon =
      pairs(samples)
      |> Enum.flat_map(fn {a, b} ->
        case {a.dh, b.dh} do
          {x, y} when x <= 0.0 and y > 0.0 -> [{:rise, a.jd, b.jd}]
          {x, y} when x >= 0.0 and y < 0.0 -> [{:set, a.jd, b.jd}]
          _ -> grazing_crossings(a, b, eval, dh_at, ha_at, tol)
        end
      end)
      |> Enum.map(&refine(&1, dh_at, body_fun, {lat, lon}, tol))

    transits =
      if with_transits? do
        pairs(samples)
        |> Enum.flat_map(fn {a, b} ->
          # The hour angle always increases (≈ 15°/h): a negative-to-positive
          # crossing is an upper culmination. The +180 → −180 wrap
          # (antitransit) shows up in the opposite direction and is ignored.
          if a.ha < 0.0 and b.ha >= 0.0, do: [{:transit, a.jd, b.jd}], else: []
        end)
        |> Enum.map(&refine(&1, ha_at, body_fun, {lat, lon}, tol))
      else
        []
      end

    state =
      cond do
        horizon != [] -> :normal
        Enum.all?(samples, &(&1.dh > 0.0)) -> :always_above
        true -> :always_below
      end

    %{state: state, events: Enum.sort_by(horizon ++ transits, & &1.jd)}
  end

  # An interval whose endpoints sit on the same side of the horizon can
  # still hide a pair of crossings — but only around an altitude extremum,
  # and the altitude only peaks at the upper culmination (ha = 0) and
  # bottoms at the lower one (|ha| = 180). Probe the culmination when the
  # interval contains one; if the body pokes through the horizon there,
  # split the interval at that point into a rise/set (or set/rise) pair.
  defp grazing_crossings(a, b, eval, dh_at, ha_at, tol) do
    cond do
      # Below the horizon at both ends, upper culmination inside
      a.dh <= 0.0 and b.dh <= 0.0 and a.ha < 0.0 and b.ha >= 0.0 ->
        t = Numeric.bisect_zero(ha_at, a.jd, b.jd, tol)

        if dh_at.(t) > 0.0,
          do: [{:rise, a.jd, t}, {:set, t, b.jd}],
          else: []

      # Above the horizon at both ends, lower culmination inside
      # (detected by the ±180° wrap of the hour angle)
      a.dh >= 0.0 and b.dh >= 0.0 and b.ha < a.ha - 180.0 ->
        t = Numeric.bisect_zero(fn jd -> norm360(eval.(jd).ha) - 180.0 end, a.jd, b.jd, tol)

        if dh_at.(t) < 0.0,
          do: [{:set, a.jd, t}, {:rise, t, b.jd}],
          else: []

      true ->
        []
    end
  end

  defp pairs(samples), do: Enum.zip(samples, tl(samples))

  defp refine({type, ja, jb}, f, body_fun, {lat, lon}, tol) do
    jd = Numeric.bisect_zero(f, ja, jb, tol)
    {ra, dec, _h0} = body_fun.(jd)

    %{
      type: type,
      jd: jd,
      azimuth: azimuth(jd, lat, lon, ra, dec),
      altitude: altitude(jd, lat, lon, ra, dec)
    }
  end

  @doc """
  Local hour angle in degrees, reduced into [−180, 180).

  Negative before meridian transit, positive after.
  """
  @spec hour_angle(float(), number(), float()) :: float()
  def hour_angle(jd, lon, ra), do: norm180(gast(jd) + lon - ra)

  @doc "Geometric altitude of a body above the horizon, in degrees."
  @spec altitude(float(), number(), number(), float(), float()) :: float()
  def altitude(jd, lat, lon, ra, dec) do
    h = hour_angle(jd, lon, ra)
    :math.asin(sin_d(lat) * sin_d(dec) + cos_d(lat) * cos_d(dec) * cos_d(h)) * @deg
  end

  @doc "Azimuth of a body, in degrees from North through East."
  @spec azimuth(float(), number(), number(), float(), float()) :: float()
  def azimuth(jd, lat, lon, ra, dec) do
    h = hour_angle(jd, lon, ra)

    a =
      :math.atan2(sin_d(h), cos_d(h) * sin_d(lat) - :math.tan(dec * rad()) * cos_d(lat)) *
        @deg

    norm360(a + 180.0)
  end
end
