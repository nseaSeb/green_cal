defmodule GreenCal do
  @moduledoc """
  Agricultural sun & moon calendar — pure Elixir, zero dependencies.

  From a geolocation, a date (or a date range) and optionally an elevation,
  GreenCal computes everything a gardening / market-farming calendar needs:

    * sunrise, solar noon, sunset, day length, civil dawn/dusk
    * moonrise, moonset, phase, illuminated fraction, distance
    * the three independent lunar cycles used by agricultural calendars:
      **waxing/waning** (illumination), **ascending/descending**
      (declination — the one biodynamic sowing calendars care about), and
      **perigee/apogee** (distance)
    * **lunar node crossings** (β = 0), the days biodynamic calendars mark
      as unfavorable
    * the sidereal constellation the Moon stands in, its element and the
      plant organ traditionally associated with it

  ## Quick start

      day = GreenCal.day({48.8566, 2.3522}, ~D[2026-06-21])
      day.sun.rise            #=> ~U[2026-06-21 03:46:57Z]
      day.moon.phase          #=> :first_quarter
      day.moon.trend          #=> :descending

      GreenCal.calendar({48.8566, 2.3522}, Date.range(~D[2026-07-01], ~D[2026-07-31]))

  ## Options

  Accepted by `day/3` and `calendar/3`:

    * `:elevation` — meters above sea level (default `0.0`). Deepens the
      apparent horizon dip: about one minute of earlier sunrise per 100 m.
      Applies to sun and moon rise/set only — twilights are defined by the
      Sun's geometric altitude and are deliberately unaffected (a higher
      vantage point sees the Sun sooner, but the sky's illumination
      geometry does not change).
    * `:time_zone` — IANA zone name (e.g. `"Europe/Paris"`). The civil day
      then runs from local midnight to local midnight and every `DateTime`
      is returned in that zone. Requires a configured time zone database
      (e.g. `tzdata`); the default `"Etc/UTC"` needs none.
    * `:twilight` — altitude used for dawn/dusk: `:civil` (default),
      `:nautical`, `:astronomical`, or degrees.
    * `:boundaries` — constellation convention: `:equal_sidereal`
      (default) or `:iau` (see `constellation_of/3`).
    * `:delta_t` — override ΔT in seconds (see `GreenCal.Astro.Time`).

  ## A warning about the interpretive layer

  Rise/set times, phases and declination trends are astronomy: they are
  computed here to the minute and validated against published references.
  Elements, organs and "sowing days" are **tradition**, not science —
  GreenCal computes the underlying astronomy faithfully and labels the
  traditional mapping for what it is.

  Note on constellations: the default is the sidereal zodiac with a Lahiri
  ayanamsa and equal 30° sectors. Printed biodynamic calendars (Maria Thun
  et al.) use the unequal IAU constellation boundaries instead — pass
  `boundaries: :iau` to match them (13 sectors, Ophiuchus included).
  """

  alias GreenCal.Astro
  alias GreenCal.Astro.Time

  @typedoc "Latitude and longitude in degrees, East positive."
  @type location :: {number(), number()}

  # Sidereal zodiac: {constellation, element}. The traditional element →
  # organ mapping follows: fire→fruit, earth→root, air→flower, water→leaf.
  @constellations [
    {"Aries", :fire},
    {"Taurus", :earth},
    {"Gemini", :air},
    {"Cancer", :water},
    {"Leo", :fire},
    {"Virgo", :earth},
    {"Libra", :air},
    {"Scorpio", :water},
    {"Sagittarius", :fire},
    {"Capricorn", :earth},
    {"Aquarius", :air},
    {"Pisces", :water}
  ]

  @element_to_organ %{fire: :fruit, earth: :root, air: :flower, water: :leaf}

  # IAU (1930) constellation boundaries where they cross the ecliptic,
  # expressed as tropical ecliptic longitude at epoch J2000.0 — the entry
  # longitude of each constellation, unequal sectors, Ophiuchus included.
  # Cross-checked in the test suite against this library's own solar
  # ephemeris at the published solar entry dates (Wikipedia "Zodiac").
  # Ophiuchus carries :water — printed biodynamic calendars fold that
  # stretch into Scorpius.
  @iau_boundaries [
    {29.09, "Aries", :fire},
    {53.47, "Taurus", :earth},
    {90.43, "Gemini", :air},
    {118.26, "Cancer", :water},
    {138.18, "Leo", :fire},
    {174.15, "Virgo", :earth},
    {217.80, "Libra", :air},
    {241.14, "Scorpius", :water},
    {248.08, "Ophiuchus", :water},
    {266.30, "Sagittarius", :fire},
    {299.71, "Capricornus", :earth},
    {327.89, "Aquarius", :air},
    {351.57, "Pisces", :water}
  ]

  # General precession in ecliptic longitude, degrees per Julian year.
  # Star-fixed boundaries drift by this much against tropical longitudes.
  @precession_per_year 50.28796 / 3600.0

  @doc """
  Everything about one civil day at one location.

  See `GreenCal.Day` for the returned struct and the module doc for the
  option list.

  The `:sun` and `:moon` structs carry a `:state` field: `:normal`, or
  `:always_above` / `:always_below` when the body never crosses the horizon
  that day (polar day/night for the Sun; for the Moon this legitimately
  happens about one day per month — a `nil` moonrise is not a bug).
  """
  @spec day(location(), Date.t(), keyword()) :: GreenCal.Day.t()
  def day({_lat, _lon} = loc, %Date{} = date, opts \\ []) do
    validate_location!(loc)
    {jd0, jd1, tz} = civil_day_window(date, opts)
    noon_jd = (jd0 + jd1) / 2.0

    sun_result = Astro.sun_events(loc, jd0, jd1, opts)
    twilight_kind = Keyword.get(opts, :twilight, :civil)
    twilight_result = Astro.twilight_events(loc, jd0, jd1, twilight_kind, opts)
    moon_result = Astro.moon_events(loc, jd0, jd1, opts)

    moon_now = Astro.moon(noon_jd, opts)
    phase = Astro.phase(noon_jd, opts)

    # Centered derivatives at ±12 h: day-to-day sampling misses the
    # inversions near the extrema of the declination cycle.
    moon_before = Astro.moon(noon_jd - 0.5, opts)
    moon_after = Astro.moon(noon_jd + 0.5, opts)

    {constellation, element} = constellation_of(moon_now.longitude, date, opts)

    sun_sel = select_events(sun_result)
    twilight_sel = select_events(twilight_result)
    moon_sel = select_events(moon_result)

    %GreenCal.Day{
      date: date,
      location: loc,
      sun: %GreenCal.Day.Sun{
        state: sun_result.state,
        rise: stamp(sun_sel.rise, tz),
        set: stamp(sun_sel.set, tz),
        transit: stamp(sun_sel.transit, tz),
        day_length_minutes: sunlight_minutes(sun_result, jd0, jd1),
        rise_azimuth: sun_sel.rise && sun_sel.rise.azimuth,
        set_azimuth: sun_sel.set && sun_sel.set.azimuth
      },
      twilight: %GreenCal.Day.Twilight{
        kind: twilight_kind,
        state: twilight_result.state,
        dawn: stamp(twilight_sel.rise, tz),
        dusk: stamp(twilight_sel.set, tz)
      },
      moon: %GreenCal.Day.Moon{
        state: moon_result.state,
        rise: stamp(moon_sel.rise, tz),
        set: stamp(moon_sel.set, tz),
        transit: stamp(moon_sel.transit, tz),
        phase: Astro.phase_name(phase.elongation),
        elongation: phase.elongation,
        illuminated_fraction: phase.illuminated_fraction,
        distance_km: moon_now.distance_km,
        declination: moon_now.declination,
        ecliptic_latitude: moon_now.latitude,
        # Node crossing within the civil day, if any (~2 days per month).
        # Biodynamic calendars treat the surrounding hours as unfavorable.
        node: node_crossing(jd0, jd1, tz, opts),
        # The three independent cycles — conflating the first two is the
        # single most common mistake in lunar-calendar implementations.
        trend: trend(moon_before.declination, moon_after.declination, :ascending, :descending),
        illumination_trend: if(phase.elongation < 180.0, do: :waxing, else: :waning),
        distance_trend:
          trend(moon_before.distance_km, moon_after.distance_km, :receding, :approaching)
      },
      constellation: constellation,
      element: element,
      organ: Map.fetch!(@element_to_organ, element)
    }
  end

  @doc """
  One `GreenCal.Day` per date of the range (or any enumerable of dates).

  Days are independent computations (~1.8 ms each): pass `parallel: true`
  to spread them over the schedulers with `Task.async_stream/3` — a full
  year drops from ~630 ms to ~160 ms on a typical machine. Order is
  preserved either way, and exceptions stay rescuable in both modes.

      GreenCal.calendar(loc, Date.range(~D[2026-07-01], ~D[2026-07-31]))
      GreenCal.calendar(loc, Date.range(~D[2026-01-01], ~D[2026-12-31]), parallel: true)
  """
  @spec calendar(location(), Enumerable.t(), keyword()) :: [GreenCal.Day.t()]
  def calendar(loc, dates, opts \\ []) do
    validate_location!(loc)
    {parallel, opts} = Keyword.pop(opts, :parallel, false)

    if parallel do
      # Exceptions inside linked tasks would kill the caller as an exit
      # signal; capture and re-raise them here so both branches fail the
      # same way (a rescuable exception).
      dates
      |> Task.async_stream(
        fn date ->
          try do
            {:ok, day(loc, date, opts)}
          rescue
            e -> {:raise, e, __STACKTRACE__}
          end
        end,
        ordered: true,
        timeout: :infinity
      )
      |> Enum.map(fn
        {:ok, {:ok, day}} -> day
        {:ok, {:raise, e, stacktrace}} -> reraise e, stacktrace
      end)
    else
      Enum.map(dates, &day(loc, &1, opts))
    end
  end

  @doc """
  Geocentric lunar events over a date range — no location involved.

  Everything a printed lunar calendar marks with a symbol, as exact
  instants:

    * `:phases` — new moon, quarters, full moon, with the `:eclipse`
      screening flag (see `GreenCal.Astro.phase_events/3`)
    * `:apsides` — perigees and apogees, with distances
    * `:nodes` — ascending / descending node crossings
    * `:standstills` — northernmost / southernmost declination, i.e. the
      exact flips between ascending and descending Moon

  Times are UTC `DateTime`s, or local ones with the `:time_zone` option.

      GreenCal.lunar_events(Date.range(~D[2026-08-01], ~D[2026-08-31]))
      #=> %{phases: [%{type: :new_moon, at: ~U[2026-08-12 17:36:40Z], eclipse: :likely}, ...],
      #     apsides: [...], nodes: [...], standstills: [...]}
  """
  @spec lunar_events(Date.Range.t(), keyword()) :: %{
          phases: [map()],
          apsides: [map()],
          nodes: [map()],
          standstills: [map()]
        }
  def lunar_events(%Date.Range{first: first, last: last}, opts \\ []) do
    # Same civil-day windows as calendar/3: with a :time_zone the range
    # runs from the first date's local midnight to the day after the last
    # date's local midnight, so both functions agree on what "August" is.
    {jd0, _, tz} = civil_day_window(first, opts)
    {_, jd1, _} = civil_day_window(last, opts)

    stamp = fn events ->
      Enum.map(events, fn %{jd: jd} = e ->
        e |> Map.delete(:jd) |> Map.put(:at, jd |> Time.to_datetime() |> shift(tz))
      end)
    end

    %{
      phases: stamp.(Astro.phase_events(jd0, jd1, opts)),
      apsides: stamp.(Astro.apsis_events(jd0, jd1, opts)),
      nodes: stamp.(Astro.node_crossings(jd0, jd1, opts)),
      standstills: stamp.(Astro.declination_extrema(jd0, jd1, opts))
    }
  end

  @doc """
  Constellation occupied by a tropical ecliptic longitude.

  Two boundary conventions, chosen with the `:boundaries` option:

    * `:equal_sidereal` (default) — sidereal zodiac, twelve equal 30°
      sectors, Lahiri ayanamsa. The convention of Indian ephemerides.
    * `:iau` — the real (unequal) IAU constellation boundaries along the
      ecliptic, thirteen sectors including Ophiuchus. This is what printed
      biodynamic calendars (Maria Thun et al.) use; Ophiuchus carries
      `:water`, as those calendars fold it into Scorpius.

  Both drift together against the tropical zodiac by ~50.3″/yr
  (precession), computed continuously — no jump at January 1st.

  Returns `{name, element}`.

      iex> GreenCal.constellation_of(45.0, ~D[2026-01-01])
      {"Aries", :fire}

      iex> GreenCal.constellation_of(250.0, ~D[2026-01-01], boundaries: :iau)
      {"Ophiuchus", :water}
  """
  @spec constellation_of(float(), Date.t(), keyword()) :: {String.t(), atom()}
  def constellation_of(tropical_longitude, %Date{} = date, opts \\ []) do
    years = decimal_year(date) - 2000.0

    case Keyword.get(opts, :boundaries, :equal_sidereal) do
      :equal_sidereal ->
        # Lahiri ayanamsa: 23.853° at J2000, growing with precession
        sidereal = Time.norm360(tropical_longitude - 23.853 - @precession_per_year * years)
        Enum.at(@constellations, trunc(sidereal / 30.0))

      :iau ->
        # Bring the longitude back to J2000, where the table is expressed.
        # The sector is the last boundary at or below it; below the first
        # boundary (29.09°) we are in Pisces, which wraps around 0°.
        lon = Time.norm360(tropical_longitude - @precession_per_year * years)

        {_, name, element} =
          @iau_boundaries
          |> Enum.take_while(fn {start, _, _} -> start <= lon end)
          |> List.last(List.last(@iau_boundaries))

        {name, element}
    end
  end

  defp decimal_year(%Date{year: year} = date) do
    year + (Date.day_of_year(date) - 1) / 365.25
  end

  # ── Internals ──────────────────────────────────────────────────────────

  # The civil day runs from local midnight to local midnight when a
  # `:time_zone` is given, from UTC midnight otherwise.
  defp civil_day_window(date, opts) do
    case Keyword.get(opts, :time_zone, "Etc/UTC") do
      "Etc/UTC" ->
        jd0 = Time.julian_day(date)
        {jd0, jd0 + 1.0, "Etc/UTC"}

      tz ->
        {Time.julian_day(local_midnight(date, tz)),
         Time.julian_day(local_midnight(Date.add(date, 1), tz)), tz}
    end
  end

  # DST transitions can skip or repeat midnight in some zones (Cuba, Chile…):
  # take the first valid instant of the civil day.
  defp local_midnight(date, tz) do
    case DateTime.new(date, ~T[00:00:00], tz) do
      {:ok, dt} -> dt
      {:gap, _just_before, just_after} -> just_after
      {:ambiguous, first, _second} -> first
      {:error, reason} -> raise ArgumentError, tz_error(tz, reason)
    end
  end

  defp tz_error(tz, :utc_only_time_zone_database) do
    "time zone #{inspect(tz)} requires a time zone database — add e.g. {:tzdata, \"~> 1.1\"} " <>
      "and configure it with `config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase`"
  end

  defp tz_error(tz, reason), do: "cannot resolve time zone #{inspect(tz)}: #{inspect(reason)}"

  defp node_crossing(jd0, jd1, tz, opts) do
    case Astro.node_crossings(jd0, jd1, opts) do
      [] -> nil
      [%{type: type, jd: jd} | _] -> %{type: type, at: jd |> Time.to_datetime() |> shift(tz)}
    end
  end

  # Picks the day's reported rise/set/transit from the raw event list.
  # High-latitude days can hold two sets (or two rises): the reported set
  # is the one that closes the arc opened by the reported rise — the first
  # set *after* it. Only when the day holds no post-rise set (the Sun rose
  # and stays up past midnight) does the pre-rise set get reported, and
  # then set < rise legitimately describes that day.
  defp select_events(%{events: events}) do
    rise = Enum.find(events, &(&1.type == :rise))

    set =
      case rise do
        nil ->
          Enum.find(events, &(&1.type == :set))

        %{jd: rjd} ->
          Enum.find(events, &(&1.type == :set and &1.jd > rjd)) ||
            Enum.find(events, &(&1.type == :set))
      end

    %{rise: rise, set: set, transit: Enum.find(events, &(&1.type == :transit))}
  end

  defp stamp(nil, _tz), do: nil
  defp stamp(%{jd: jd}, tz), do: jd |> Time.to_datetime() |> shift(tz)

  defp shift(dt, "Etc/UTC"), do: dt

  defp shift(dt, tz) do
    case DateTime.shift_zone(dt, tz) do
      {:ok, shifted} -> shifted
      {:error, reason} -> raise ArgumentError, tz_error(tz, reason)
    end
  end

  # Time the Sun spends above the horizon within the window — always
  # defined, even when the day straddles midnight (high latitudes) or the
  # window is not 24 h long (DST days in local-time mode).
  defp sunlight_minutes(%{state: :always_above}, jd0, jd1), do: (jd1 - jd0) * 1440.0
  defp sunlight_minutes(%{state: :always_below}, _jd0, _jd1), do: 0.0

  defp sunlight_minutes(%{events: events}, jd0, jd1) do
    horizon = Enum.filter(events, &(&1.type in [:rise, :set]))

    # The Sun is up at the window start iff the first crossing is a set
    up0? = match?([%{type: :set} | _], horizon)

    {total, up?, since} =
      Enum.reduce(horizon, {0.0, up0?, jd0}, fn e, {total, _up?, since} ->
        case e.type do
          :set -> {total + (e.jd - since), false, e.jd}
          :rise -> {total, true, e.jd}
        end
      end)

    total = if up?, do: total + (jd1 - since), else: total
    total * 1440.0
  end

  defp trend(before, later, up, down), do: if(later > before, do: up, else: down)

  defp validate_location!({lat, lon}) when is_number(lat) and is_number(lon) do
    if lat < -90 or lat > 90 do
      raise ArgumentError, "latitude must be within -90..90, got: #{lat}"
    end

    if lon < -180 or lon > 180 do
      raise ArgumentError,
            "longitude must be within -180..180, got: #{lon} " <>
              "(note: locations are {latitude, longitude}, in that order)"
    end

    :ok
  end
end
