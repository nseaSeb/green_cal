defmodule GreenCal.Astro do
  @moduledoc """
  Low-level facade: apparent positions, phase, rises and sets.

  This is where UT and TT are reconciled. Every public function in this
  module takes a Julian day in **UT** and applies ΔT itself before calling
  `GreenCal.Astro.Sun` / `GreenCal.Astro.Moon`.

  For the garden-oriented API, see `GreenCal`.
  """

  alias GreenCal.Astro.{Moon, Numeric, RiseSet, Sun, Time}

  import GreenCal.Astro.Time, only: [norm360: 1, norm180: 1, sin_d: 1, cos_d: 1]

  @au_km 149_597_870.7
  @deg 180.0 / :math.pi()

  @doc "Apparent position of the Sun for a UT Julian day."
  @spec sun(float(), keyword()) :: Sun.position()
  def sun(jd, opts \\ []), do: Sun.position(Time.jd_to_jde(jd, opts[:delta_t]))

  @doc "Apparent position of the Moon for a UT Julian day."
  @spec moon(float(), keyword()) :: Moon.position()
  def moon(jd, opts \\ []), do: Moon.position(Time.jd_to_jde(jd, opts[:delta_t]))

  @doc """
  Elongation, phase angle and illuminated fraction of the Moon.

  The phase angle follows Meeus 48.3, using the true Earth–Sun and
  Earth–Moon distances rather than the approximate series of chapter 47:
  more accurate, and free since the Sun is computed anyway.

  `:elongation` is the ecliptic longitude difference λ☾ − λ☉ reduced into
  [0, 360) — this, not the true angular elongation, is what defines the
  phases (0 = new moon, 180 = full moon).
  """
  @spec phase(float(), keyword()) :: %{
          elongation: float(),
          phase_angle: float(),
          illuminated_fraction: float(),
          angular_separation: float()
        }
  def phase(jd, opts \\ []) do
    s = sun(jd, opts)
    m = moon(jd, opts)

    # Geocentric Sun–Moon angular separation
    cos_psi = cos_d(m.latitude) * cos_d(m.longitude - s.longitude)
    psi = :math.acos(max(-1.0, min(1.0, cos_psi))) * @deg

    r = s.radius_vector * @au_km

    i = :math.atan2(r * sin_d(psi), m.distance_km - r * cos_d(psi)) * @deg

    %{
      elongation: norm360(m.longitude - s.longitude),
      phase_angle: i,
      illuminated_fraction: (1.0 + cos_d(i)) / 2.0,
      angular_separation: psi
    }
  end

  @doc """
  Phase name from the elongation λ☾ − λ☉, in eight sectors.

  Each of the four principal phases owns a 22.5° sector centered on its
  exact value: `:full_moon` therefore names the day around the exact
  instant, not just the instant.
  """
  @spec phase_name(float()) :: atom()
  def phase_name(elongation) do
    cond do
      elongation < 11.25 or elongation >= 348.75 -> :new_moon
      elongation < 78.75 -> :waxing_crescent
      elongation < 101.25 -> :first_quarter
      elongation < 168.75 -> :waxing_gibbous
      elongation < 191.25 -> :full_moon
      elongation < 258.75 -> :waning_gibbous
      elongation < 281.25 -> :last_quarter
      true -> :waning_crescent
    end
  end

  # ── Lunar event instants ───────────────────────────────────────────────

  @doc """
  Exact instants of the principal lunar phases between two UT Julian days.

  Returns a chronological list of

      %{type: :new_moon | :first_quarter | :full_moon | :last_quarter,
        jd: float,
        eclipse: :none | :possible | :likely}

  The instant is where the elongation λ☾ − λ☉ crosses 0°, 90°, 180° or
  270° (the standard definition of the phases), found by bisection on the
  apparent longitudes — so ΔT and nutation are accounted for.

  `:eclipse` is a **screening flag**, not an eclipse computation: at a new
  moon (solar eclipse) or full moon (lunar eclipse), an eclipse can only
  happen if the Moon is close enough to the ecliptic. `|β| < 1.2°` →
  `:likely`, `|β| < 1.9°` → `:possible` (thresholds from Meeus ch. 54's
  argument-of-latitude criterion). It says an eclipse happens somewhere on
  Earth — visibility, magnitude and local circumstances are out of scope.
  Quarters always carry `:none`.
  """
  @spec phase_events(float(), float(), keyword()) :: [
          %{type: atom(), jd: float(), eclipse: :none | :possible | :likely}
        ]
  def phase_events(jd_from, jd_to, opts \\ []) do
    # Elongation grows monotonically at ~12.2°/day: daily sampling brackets
    # every 90° crossing, bisection on the local difference nails it.
    elong = fn jd -> phase(jd, opts).elongation end

    for {j0, j1} <- sample_pairs(jd_from, jd_to, 1.0),
        e0 = elong.(j0),
        # Unwrap so the interval [e0, e1] is increasing
        e1 = elong.(j1) |> then(&if &1 < e0, do: &1 + 360.0, else: &1),
        {target, type} <- [
          {90.0, :first_quarter},
          {180.0, :full_moon},
          {270.0, :last_quarter},
          {360.0, :new_moon}
        ],
        e0 < target and target <= e1 do
      f = fn jd -> norm180(elong.(jd) - target) end
      jd = Numeric.bisect_zero(f, j0, j1)
      %{type: type, jd: jd, eclipse: eclipse_screening(type, jd, opts)}
    end
    |> Enum.sort_by(& &1.jd)
  end

  defp eclipse_screening(type, jd, opts) when type in [:new_moon, :full_moon] do
    beta = abs(moon(jd, opts).latitude)

    cond do
      beta < 1.2 -> :likely
      beta < 1.9 -> :possible
      true -> :none
    end
  end

  defp eclipse_screening(_type, _jd, _opts), do: :none

  @doc """
  Perigee and apogee instants between two UT Julian days.

  Extrema of the Earth–Moon distance (anomalistic month, 27.55 days),
  located as zero crossings of the centered derivative. Returns
  `%{type: :perigee | :apogee, jd: float, distance_km: float}` in
  chronological order.
  """
  @spec apsis_events(float(), float(), keyword()) :: [
          %{type: :perigee | :apogee, jd: float(), distance_km: float()}
        ]
  def apsis_events(jd_from, jd_to, opts \\ []) do
    extrema(fn jd -> moon(jd, opts).distance_km end, jd_from, jd_to)
    |> Enum.map(fn {kind, jd, value} ->
      %{type: if(kind == :min, do: :perigee, else: :apogee), jd: jd, distance_km: value}
    end)
  end

  @doc """
  Lunar standstill instants between two UT Julian days: the extrema of the
  Moon's declination, i.e. the exact moments the Moon switches from
  ascending to descending (`:northernmost`) and back (`:southernmost`).

  This is the boundary printed in biodynamic sowing calendars. Half a
  tropical month (~13.7 days) apart. Returns
  `%{type: :northernmost | :southernmost, jd: float, declination: float}`.
  """
  @spec declination_extrema(float(), float(), keyword()) :: [
          %{type: :northernmost | :southernmost, jd: float(), declination: float()}
        ]
  def declination_extrema(jd_from, jd_to, opts \\ []) do
    extrema(fn jd -> moon(jd, opts).declination end, jd_from, jd_to)
    |> Enum.map(fn {kind, jd, value} ->
      %{
        type: if(kind == :max, do: :northernmost, else: :southernmost),
        jd: jd,
        declination: value
      }
    end)
  end

  # Locates extrema of `fun` as sign changes of its centered derivative
  # (h = 0.05 day), sampled daily — safe for anything with a period over a
  # week, which covers every lunar cycle handled here.
  defp extrema(fun, jd_from, jd_to) do
    h = 0.05
    deriv = fn jd -> fun.(jd + h) - fun.(jd - h) end

    for {j0, j1} <- sample_pairs(jd_from, jd_to, 1.0),
        d0 = deriv.(j0),
        d1 = deriv.(j1),
        (d0 <= 0.0 and d1 > 0.0) or (d0 >= 0.0 and d1 < 0.0) do
      jd = Numeric.bisect_zero(deriv, j0, j1)
      # d1 is strictly nonzero in both guard branches; d0 may be exactly
      # 0.0 in either, so the label must come from d1
      {if(d1 < 0.0, do: :max, else: :min), jd, fun.(jd)}
    end
    |> Enum.sort_by(fn {_, jd, _} -> jd end)
  end

  defp sample_pairs(jd_from, jd_to, step) do
    n = max(ceil((jd_to - jd_from) / step), 1)
    step = (jd_to - jd_from) / n
    points = for i <- 0..n, do: jd_from + i * step
    Enum.zip(points, tl(points))
  end

  # ── Rises / sets ───────────────────────────────────────────────────────

  @doc """
  Rises, sets and meridian transit of the Sun between two UT Julian days.

  Options: `:elevation` (meters, default 0), `:delta_t`, plus those of
  `GreenCal.Astro.RiseSet.search/5`.
  """
  @spec sun_events({number(), number()}, float(), float(), keyword()) :: RiseSet.result()
  def sun_events(loc, jd_from, jd_to, opts \\ []) do
    h0 = Sun.horizon_altitude(Keyword.get(opts, :elevation, 0.0))
    RiseSet.search(sun_fun(h0, opts), loc, jd_from, jd_to, opts)
  end

  @doc """
  Dawn and dusk for a given solar altitude.

  Accepts `:civil` (−6°), `:nautical` (−12°), `:astronomical` (−18°), or a
  number of degrees — e.g. `6.0` for the golden hour.

  Unlike a computation derived from sunrise, this one stays valid when the
  Sun does not rise: civil twilight does happen above the polar circle in
  winter.

  `:elevation` deliberately does not apply here: twilights are defined by
  the Sun's **geometric** altitude, not by its visibility over the local
  horizon, so observer height changes sunrise but not dawn.
  """
  @spec twilight_events({number(), number()}, float(), float(), atom() | number(), keyword()) ::
          RiseSet.result()
  def twilight_events(loc, jd_from, jd_to, kind, opts \\ []) do
    h0 =
      case kind do
        k when is_atom(k) -> Sun.twilight_altitude(k)
        deg when is_number(deg) -> deg * 1.0
      end

    RiseSet.search(sun_fun(h0, opts), loc, jd_from, jd_to, Keyword.put(opts, :transits, false))
  end

  @doc """
  Lunar node crossings between two UT Julian days.

  A node crossing is the instant the Moon crosses the ecliptic plane
  (ecliptic latitude β = 0): `:ascending` when β turns positive,
  `:descending` when it turns negative. They occur every ~13.6 days
  (half a draconic month) and are geocentric — no location involved.

  Biodynamic calendars mark the hours around a node crossing as
  unfavorable for sowing; eclipses can only happen near one.

  Returns a list of `%{type: :ascending | :descending, jd: float}` in
  chronological order.
  """
  @spec node_crossings(float(), float(), keyword()) :: [
          %{type: :ascending | :descending, jd: float()}
        ]
  def node_crossings(jd_from, jd_to, opts \\ []) do
    # β moves at ~1.2°/day near the nodes: 1-day sampling cannot miss a
    # crossing (β period 27.2 days), bisection then nails the instant.
    n = max(ceil(jd_to - jd_from), 1)
    step = (jd_to - jd_from) / n

    lat_at = fn jd -> moon(jd, opts).latitude end

    samples = for i <- 0..n, do: {jd_from + i * step, lat_at.(jd_from + i * step)}

    samples
    |> Enum.zip(tl(samples))
    |> Enum.flat_map(fn {{j0, b0}, {j1, b1}} ->
      cond do
        b0 <= 0.0 and b1 > 0.0 -> [%{type: :ascending, jd: Numeric.bisect_zero(lat_at, j0, j1)}]
        b0 >= 0.0 and b1 < 0.0 -> [%{type: :descending, jd: Numeric.bisect_zero(lat_at, j0, j1)}]
        true -> []
      end
    end)
  end

  @doc """
  Rises, sets and meridian transit of the Moon between two UT Julian days.

  Here `h₀` depends on the instantaneous distance (parallax), so it is
  recomputed at every evaluation — see
  `GreenCal.Astro.Moon.horizon_altitude/1`.
  """
  @spec moon_events({number(), number()}, float(), float(), keyword()) :: RiseSet.result()
  def moon_events(loc, jd_from, jd_to, opts \\ []) do
    RiseSet.search(moon_fun(opts), loc, jd_from, jd_to, opts)
  end

  @doc false
  def sun_fun(h0, opts) do
    fn jd ->
      s = sun(jd, opts)
      {s.right_ascension, s.declination, h0}
    end
  end

  @doc false
  def moon_fun(opts) do
    dip = Sun.horizon_dip(Keyword.get(opts, :elevation, 0.0))

    fn jd ->
      m = moon(jd, opts)
      {m.right_ascension, m.declination, Moon.horizon_altitude(m) - dip}
    end
  end
end
