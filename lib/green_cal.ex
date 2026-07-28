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

  Everything the day holds that happens *at an instant* is also available
  as one sorted list — sunrise and moonset next to the exact full moon:

      for e <- day.events, do: {e.family, e.type, e.at}

  See `GreenCal.Day` for the shape and guarantees of that list, and
  `lunar_timeline/2` for the same idea over a whole range without a
  location.

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

      In zones that change offset at midnight (Cuba, Chile, Lord Howe…)
      local midnight can be missing or happen twice a year. Where it is
      **missing**, the day starts at the first instant after the jump —
      01:00 local for a one-hour spring forward, and the day is 23 h long.
      Where it happens **twice**, the day starts at the first of the two,
      before the clocks go back, and is 25 h long. Days therefore always
      tile the year: no instant belongs to two civil days, and none to
      neither.
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

    geo = geocentric_of_day(jd0, jd1, tz, opts)

    day = %GreenCal.Day{
      date: date,
      location: loc,
      sampled_at: noon_jd |> Time.to_datetime() |> shift(tz),
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
        # The geocentric instants falling within the civil day, at most one
        # per family. The node crossing (~2 days per month) is the one
        # biodynamic calendars mark: they treat the surrounding hours as
        # unfavorable.
        phase_change: geo.phase,
        apsis: geo.apsis,
        node: geo.node,
        standstill: geo.standstill,
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

    %{day | events: project_events(day)}
  end

  @doc """
  One `GreenCal.Day` per date of the range (or any enumerable of dates).

  Days are independent computations: pass `parallel: true` to spread them
  over the schedulers with `Task.async_stream/3`. Order is preserved either
  way, and exceptions stay rescuable in both modes.

      GreenCal.calendar(loc, Date.range(~D[2026-07-01], ~D[2026-07-31]))
      GreenCal.calendar(loc, Date.range(~D[2026-01-01], ~D[2026-12-31]), parallel: true)

  Every day is computed exactly as `day/3` would compute it alone, so the
  two functions agree bit for bit. Sharing one geocentric search across the
  range was tried and dropped: it measured within noise of the per-day
  searches (the cost sits in the bisections, whose count depends on how
  many events exist, not on how the range is cut), and it made
  `calendar/3` disagree with `day/3` by a few milliseconds under a
  `:time_zone`, where a DST day is 23 or 25 hours long and the sampling
  grids stop lining up.
  """
  @spec calendar(location(), Enumerable.t(), keyword()) :: [GreenCal.Day.t()]
  def calendar(loc, dates, opts \\ []) do
    validate_location!(loc)
    {parallel, opts} = Keyword.pop(opts, :parallel, false)

    map_maybe_parallel(dates, parallel, &day(loc, &1, opts))
  end

  # Exceptions inside linked tasks would kill the caller as an exit signal;
  # capture and re-raise them here so both branches fail the same way (a
  # rescuable exception).
  defp map_maybe_parallel(items, false, fun), do: Enum.map(items, fun)

  defp map_maybe_parallel(items, true, fun) do
    items
    |> Task.async_stream(
      fn item ->
        try do
          {:ok, fun.(item)}
        rescue
          e -> {:raise, e, __STACKTRACE__}
        end
      end,
      ordered: true,
      timeout: :infinity
    )
    |> Enum.map(fn
      {:ok, {:ok, value}} -> value
      {:ok, {:raise, e, stacktrace}} -> reraise e, stacktrace
    end)
  end

  @doc """
  Geocentric lunar events over a date range, as one chronology.

  No location involved: these instants are the same everywhere on Earth.
  Everything a printed lunar calendar marks with a symbol, in the order it
  happens, each entry tagged with its `:family`:

      GreenCal.lunar_timeline(Date.range(~D[2026-08-01], ~D[2026-08-31]))
      #=> [%{family: :phase, type: :last_quarter, at: ~U[2026-08-06 02:21:49Z],
      #      eclipse: :none},
      #    %{family: :standstill, type: :northernmost,
      #      at: ~U[2026-08-08 23:38:08Z], declination: 28.107933344152},
      #    %{family: :apsis, type: :perigee, at: ~U[2026-08-10 11:16:35Z],
      #      distance_km: 363285.244284283},
      #    %{family: :phase, type: :new_moon, at: ~U[2026-08-12 17:36:40Z],
      #      eclipse: :likely},
      #    ...]

  | Family | Types | Extra keys |
  |---|---|---|
  | `:phase` | `:new_moon`, `:first_quarter`, `:full_moon`, `:last_quarter` | `:eclipse` (see `GreenCal.Astro.phase_events/3`) |
  | `:apsis` | `:perigee`, `:apogee` | `:distance_km` |
  | `:node` | `:ascending`, `:descending` | — |
  | `:standstill` | `:northernmost`, `:southernmost` | `:declination` |

  Unlike `GreenCal.Day` `:events`, entries here carry their family's extra
  keys: there is no struct behind this list to hold them.

  The four families are independent searches over the same range, so
  `parallel: true` runs them on separate schedulers. The result is
  identical either way, down to the last bit — same range, same sampling
  grid, same bisection.

  Times are UTC `DateTime`s, or local ones with the `:time_zone` option.
  """
  @spec lunar_timeline(Date.Range.t(), keyword()) :: [map()]
  def lunar_timeline(%Date.Range{first: first, last: last} = range, opts \\ []) do
    # A descending range would hand the finders a backwards window, which
    # they would sample the wrong way round and quietly report as empty.
    if Date.compare(first, last) == :gt do
      raise ArgumentError,
            "lunar_timeline/2 and lunar_events/2 need an ascending date range, " <>
              "got: #{inspect(range)}"
    end

    {parallel, opts} = Keyword.pop(opts, :parallel, false)

    # Same civil-day windows as calendar/3: with a :time_zone the range
    # runs from the first date's local midnight to the day after the last
    # date's local midnight, so both functions agree on what "August" is.
    {jd0, _, tz} = civil_day_window(first, opts)
    {_, jd1, _} = civil_day_window(last, opts)

    jd0
    |> geocentric_events(jd1, opts, parallel)
    |> Enum.map(&stamp_event(&1, tz))
  end

  @doc """
  `lunar_timeline/2` grouped by family — the four lists a printed lunar
  calendar keeps apart.

    * `:phases` — new moon, quarters, full moon, with the `:eclipse`
      screening flag (see `GreenCal.Astro.phase_events/3`)
    * `:apsides` — perigees and apogees, with distances
    * `:nodes` — ascending / descending node crossings
    * `:standstills` — northernmost / southernmost declination, i.e. the
      exact flips between ascending and descending Moon

  This is a view over `lunar_timeline/2`, not a second computation, so the
  two cannot report different instants. Each list is chronological; reach
  for `lunar_timeline/2` when you want the families interleaved instead.

      GreenCal.lunar_events(Date.range(~D[2026-08-01], ~D[2026-08-31]))
      #=> %{phases: [%{family: :phase, type: :new_moon,
      #                at: ~U[2026-08-12 17:36:40Z], eclipse: :likely}, ...],
      #     apsides: [...], nodes: [...], standstills: [...]}
  """
  @spec lunar_events(Date.Range.t(), keyword()) :: %{
          phases: [map()],
          apsides: [map()],
          nodes: [map()],
          standstills: [map()]
        }
  def lunar_events(%Date.Range{} = range, opts \\ []) do
    range
    |> lunar_timeline(opts)
    |> Enum.group_by(&group_key(&1.family))
    |> then(&Map.merge(%{phases: [], apsides: [], nodes: [], standstills: []}, &1))
  end

  defp group_key(:phase), do: :phases
  defp group_key(:apsis), do: :apsides
  defp group_key(:node), do: :nodes
  defp group_key(:standstill), do: :standstills

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

  # DST transitions can skip or repeat midnight in some zones (Cuba,
  # Chile…): take the first valid instant of the civil day. Documented in
  # the `:time_zone` option — what this picks decides which 24 h window is
  # "the day", so it belongs in the contract, not just here.
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

  # ── Geocentric events ──────────────────────────────────────────────────

  # The four families, in the order they take in a chronology on the (very
  # rare) instant two of them share. Each is an independent search over the
  # same window: parallelizing *these* rather than the range is what makes
  # `parallel: true` bit-for-bit identical to the sequential run, with no
  # reasoning needed about events landing on a sub-range boundary.
  #
  # The result is flat and chronological, and still carries `:jd` —
  # stamping into `DateTime`s happens at the edges, so nothing downstream
  # has to work from times already rounded to the second.
  defp geocentric_events(jd0, jd1, opts, parallel) do
    [
      {:phase, &Astro.phase_events/3},
      {:apsis, &Astro.apsis_events/3},
      {:node, &Astro.node_crossings/3},
      {:standstill, &Astro.declination_extrema/3}
    ]
    |> map_maybe_parallel(parallel, fn {family, find} ->
      jd0 |> find.(jd1, opts) |> Enum.map(&Map.put(&1, :family, family))
    end)
    |> Enum.concat()
    |> Enum.sort_by(& &1.jd)
  end

  defp stamp_event(%{jd: jd} = event, tz) do
    event |> Map.delete(:jd) |> Map.put(:at, jd |> Time.to_datetime() |> shift(tz))
  end

  @no_geocentric %{phase: nil, apsis: nil, node: nil, standstill: nil}

  # At most one event per family within a civil day: the shortest of these
  # cycles is 7.4 days (successive principal phases). Keeping the first is
  # therefore keeping the only one.
  #
  # Always run, never behind an option: a `nil` here has to mean "no such
  # event today" and nothing else, or every reader of `moon.node` has to
  # know how the day was built before trusting it.
  defp geocentric_of_day(jd0, jd1, tz, opts) do
    jd0
    |> geocentric_events(jd1, opts, false)
    |> Enum.reduce(@no_geocentric, fn event, acc ->
      {family, event} = Map.pop!(event, :family)

      case Map.fetch!(acc, family) do
        nil -> Map.put(acc, family, stamp_event(event, tz))
        _already_seen -> acc
      end
    end)
  end

  # `:events` is built by reading the finished struct back, so a field and
  # its entry in the list are the same value by construction — they cannot
  # drift apart the way two parallel computations of the same fact would.
  defp project_events(%GreenCal.Day{sun: sun, twilight: twilight, moon: moon}) do
    instants =
      [
        {:sun, :rise, sun.rise},
        {:sun, :transit, sun.transit},
        {:sun, :set, sun.set},
        {:twilight, :dawn, twilight.dawn},
        {:twilight, :dusk, twilight.dusk},
        {:moon, :rise, moon.rise},
        {:moon, :transit, moon.transit},
        {:moon, :set, moon.set}
      ] ++
        for {family, event} <- [
              {:phase, moon.phase_change},
              {:apsis, moon.apsis},
              {:node, moon.node},
              {:standstill, moon.standstill}
            ],
            do: {family, event && event.type, event && event.at}

    for {family, type, at} <- instants, at != nil do
      %{family: family, type: type, at: at}
    end
    # Stable, so families that share an instant keep the order above.
    |> Enum.sort_by(& &1.at, DateTime)
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
