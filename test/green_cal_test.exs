defmodule GreenCalTest do
  use ExUnit.Case, async: true

  doctest GreenCal

  @paris {48.8566, 2.3522}
  @tromso {69.6492, 18.9553}

  describe "day/3" do
    setup do
      {:ok, day: GreenCal.day(@paris, ~D[2026-06-21])}
    end

    test "sun block is coherent", %{day: day} do
      assert day.sun.state == :normal
      assert %DateTime{} = day.sun.rise
      assert %DateTime{} = day.sun.set
      assert DateTime.compare(day.sun.rise, day.sun.transit) == :lt
      assert DateTime.compare(day.sun.transit, day.sun.set) == :lt

      # Longest day of the year in Paris: ~16 h 10 min
      assert_in_delta day.sun.day_length_minutes, 970, 15
    end

    test "twilight brackets the day", %{day: day} do
      assert day.twilight.kind == :civil
      assert DateTime.compare(day.twilight.dawn, day.sun.rise) == :lt
      assert DateTime.compare(day.sun.set, day.twilight.dusk) == :lt
    end

    test "moon block carries the three independent trends", %{day: day} do
      assert day.moon.trend in [:ascending, :descending]
      assert day.moon.illumination_trend in [:waxing, :waning]
      assert day.moon.distance_trend in [:approaching, :receding]
      assert day.moon.illuminated_fraction >= 0.0 and day.moon.illuminated_fraction <= 1.0

      assert day.moon.phase in [
               :new_moon,
               :waxing_crescent,
               :first_quarter,
               :waxing_gibbous,
               :full_moon,
               :waning_gibbous,
               :last_quarter,
               :waning_crescent
             ]
    end

    test "constellation, element and organ are consistent", %{day: day} do
      noon_jd = GreenCal.Astro.Time.julian_day(~D[2026-06-21]) + 0.5

      assert {day.constellation, day.element} ==
               GreenCal.constellation_of(GreenCal.Astro.moon(noon_jd).longitude, ~D[2026-06-21])

      assert day.organ ==
               Map.fetch!(%{fire: :fruit, earth: :root, air: :flower, water: :leaf}, day.element)
    end
  end

  describe "trends over time" do
    test "declination trend flips roughly every ~13.7 days" do
      days = GreenCal.calendar(@paris, Date.range(~D[2026-07-01], ~D[2026-08-27]))

      flips =
        days
        |> Enum.map(& &1.moon.trend)
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.count(fn [a, b] -> a != b end)

      # 58 days ≈ 2.1 tropical months → 4 or 5 inversions
      assert flips in 4..5
    end

    test "illumination trend flips at full and new moon" do
      days = GreenCal.calendar(@paris, Date.range(~D[2026-01-01], ~D[2026-01-30]))

      flips =
        days
        |> Enum.map(& &1.moon.illumination_trend)
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.count(fn [a, b] -> a != b end)

      # One full moon (Jan 3) and one new moon (Jan 18) in the window
      assert flips == 2
    end

    test "constellation advances through the whole zodiac in a sidereal month" do
      days = GreenCal.calendar(@paris, Date.range(~D[2026-03-01], ~D[2026-03-28]))
      constellations = days |> Enum.map(& &1.constellation) |> Enum.uniq()

      # 27.3 days: the Moon crosses every sector, ~2 days each
      assert length(constellations) >= 12
    end
  end

  describe "constellation_of/3" do
    # Mid-sector dates of the Sun's stay in each IAU constellation
    # (Wikipedia "Zodiac", IAU 1930 boundaries, retrieved 2026-07-28).
    # We feed our own solar longitude for that date back into
    # constellation_of/3: table and ephemeris must agree.
    @sun_stays [
      {~D[2026-04-30], "Aries"},
      {~D[2026-06-01], "Taurus"},
      {~D[2026-07-05], "Gemini"},
      {~D[2026-07-30], "Cancer"},
      {~D[2026-08-28], "Leo"},
      {~D[2026-10-08], "Virgo"},
      {~D[2026-11-10], "Libra"},
      {~D[2026-11-26], "Scorpius"},
      {~D[2026-12-08], "Ophiuchus"},
      {~D[2027-01-03], "Sagittarius"},
      {~D[2026-02-01], "Capricornus"},
      {~D[2026-02-28], "Aquarius"},
      {~D[2026-03-30], "Pisces"}
    ]

    test "IAU boundaries agree with the Sun's published constellation dates" do
      for {date, expected} <- @sun_stays do
        lon = GreenCal.Astro.sun(GreenCal.Astro.Time.julian_day(date) + 0.5).longitude
        {name, _element} = GreenCal.constellation_of(lon, date, boundaries: :iau)

        assert name == expected,
               "Sun on #{date} (λ=#{Float.round(lon, 2)}°): got #{name}, expected #{expected}"
      end
    end

    test "Ophiuchus only exists in :iau mode and carries :water" do
      assert {"Ophiuchus", :water} =
               GreenCal.constellation_of(250.0, ~D[2026-01-01], boundaries: :iau)

      {name, _} = GreenCal.constellation_of(250.0, ~D[2026-01-01])
      assert name != "Ophiuchus"
    end

    test "ayanamsa is continuous through the year, not stepped on January 1st" do
      # On 2026-06-01 the Aries → Taurus sidereal boundary sits at a
      # tropical longitude of 30° + 23.853° + 26.413 yr × 50.288″/yr
      # ≈ 54.222°. A year-granular ayanamsa would put it at ≈ 54.216°.
      assert {"Aries", :fire} = GreenCal.constellation_of(54.219, ~D[2026-06-01])
      assert {"Taurus", :earth} = GreenCal.constellation_of(54.225, ~D[2026-06-01])
    end

    test "day/3 forwards the :boundaries option" do
      d_equal = GreenCal.day(@paris, ~D[2026-06-21])
      d_iau = GreenCal.day(@paris, ~D[2026-06-21], boundaries: :iau)

      assert d_equal.constellation != nil
      assert d_iau.constellation != nil
      # Both must stay consistent with their own element → organ mapping
      for d <- [d_equal, d_iau] do
        assert d.organ ==
                 Map.fetch!(%{fire: :fruit, earth: :root, air: :flower, water: :leaf}, d.element)
      end
    end
  end

  describe "node crossings" do
    test "alternate and recur every half draconic month" do
      j0 = GreenCal.Astro.Time.julian_day(~D[2026-07-01])
      crossings = GreenCal.Astro.node_crossings(j0, j0 + 60.0)

      # 60 days / 13.6 → 4 or 5 crossings
      assert length(crossings) in 4..5

      crossings
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [a, b] ->
        assert a.type != b.type
        # Half a draconic month: 13.6 days on average, but solar
        # perturbations swing individual intervals by up to ~1 day
        assert_in_delta b.jd - a.jd, 13.6, 1.2
      end)

      # β is truly zero at each crossing
      Enum.each(crossings, fn %{jd: jd} ->
        assert_in_delta GreenCal.Astro.moon(jd).latitude, 0.0, 1.0e-4
      end)
    end

    test "day/3 exposes the crossing on the right day" do
      j0 = GreenCal.Astro.Time.julian_day(~D[2026-07-01])
      [%{jd: jd, type: type} | _] = GreenCal.Astro.node_crossings(j0, j0 + 15.0)
      date = GreenCal.Astro.Time.to_datetime(jd) |> DateTime.to_date()

      day = GreenCal.day(@paris, date)
      assert day.moon.node.type == type
      assert DateTime.to_date(day.moon.node.at) == date

      # And the day before carries no crossing
      assert GreenCal.day(@paris, Date.add(date, -1)).moon.node == nil
    end
  end

  describe "review regressions" do
    test "double-event day pairs rise with the set that closes its arc" do
      # {65.0, -18.0} on 2026-07-03 holds set ~00:00, rise ~02:31, set ~23:58:
      # the reported set must be the post-rise one, not the midnight leftover.
      day = GreenCal.day({65.0, -18.0}, ~D[2026-07-03])

      assert %DateTime{} = day.sun.rise
      assert %DateTime{} = day.sun.set
      assert DateTime.compare(day.sun.rise, day.sun.set) == :lt
      assert day.sun.set.hour == 23
      # Azimuths come from the same selected events
      assert_in_delta day.sun.set_azimuth, 350, 15
    end

    test "a civil day with two rises reports the paired rise/set and the full sunlight" do
      # {-65.0, 123.75} on 2038-08-12: the UTC day is offset from the local
      # one, so it holds rises at 00:00:32 and 23:57:07 with a single set at
      # 07:40:45. The struct must pair the first rise with its own set, and
      # day_length_minutes must count the trailing sunlight too.
      day = GreenCal.day({-65.0, 123.75}, ~D[2038-08-12])

      assert day.sun.rise == ~U[2038-08-12 00:00:32Z]
      assert day.sun.set == ~U[2038-08-12 07:40:45Z]

      paired = DateTime.diff(day.sun.set, day.sun.rise) / 60.0
      assert_in_delta paired, 460.2, 0.5

      # 2.9 more minutes of sun after the second rise, before midnight
      assert_in_delta day.sun.day_length_minutes, 463.1, 0.5
      assert day.sun.day_length_minutes > paired
    end

    test "sub-hour polar day is found, not reported as polar night" do
      # {67.25, 7.5} on the 2026 winter solstice: the Sun is up ~55 min,
      # entirely between two whole-hour samples.
      day = GreenCal.day({67.25, 7.5}, ~D[2026-12-21])

      assert day.sun.state == :normal
      assert %DateTime{} = day.sun.rise
      assert %DateTime{} = day.sun.set
      assert day.sun.day_length_minutes > 20.0 and day.sun.day_length_minutes < 90.0
      assert day.sun.rise.hour == 11
    end

    test "grazing detection agrees with a fine-step search" do
      loc = {67.25, 7.5}
      j0 = GreenCal.Astro.Time.julian_day(~D[2026-12-21])

      coarse = GreenCal.Astro.sun_events(loc, j0, j0 + 1.0)
      fine = GreenCal.Astro.sun_events(loc, j0, j0 + 1.0, step: 1.0 / 1440.0)

      assert coarse.state == :normal
      assert length(coarse.events) == length(fine.events)

      Enum.zip(coarse.events, fine.events)
      |> Enum.each(fn {a, b} ->
        assert a.type == b.type
        assert_in_delta a.jd, b.jd, 2.0e-5
      end)
    end

    test "norm360 honors its [0, 360) contract at the float edge" do
      assert GreenCal.Astro.Time.norm360(-1.0e-15) == 0.0
      # The concrete float that used to crash constellation_of
      assert {name, _} = GreenCal.constellation_of(24.216190822222195, ~D[2026-01-01])
      assert is_binary(name)
    end

    test "far-future dates no longer crash on decimal_year" do
      day = GreenCal.day({48.8566, 2.3522}, ~D[9999-12-31])
      assert %GreenCal.Day{} = day
      assert %DateTime{} = day.sun.rise
    end

    test "lunar_events raises the friendly tz error without a tz database" do
      assert_raise ArgumentError, ~r/time zone database/, fn ->
        GreenCal.lunar_events(Date.range(~D[2026-08-01], ~D[2026-08-31]),
          time_zone: "Europe/Paris"
        )
      end
    end

    test "parallel calendar failures are rescuable exceptions" do
      assert_raise ArgumentError, ~r/time zone database/, fn ->
        GreenCal.calendar({48.85, 2.35}, Date.range(~D[2026-07-01], ~D[2026-07-03]),
          parallel: true,
          time_zone: "Europe/Paris"
        )
      end
    end

    test "elevation shifts sunrise but leaves dawn untouched" do
      base = GreenCal.day(@paris, ~D[2026-04-15])
      high = GreenCal.day(@paris, ~D[2026-04-15], elevation: 2000.0)

      assert DateTime.compare(high.sun.rise, base.sun.rise) == :lt
      assert high.twilight.dawn == base.twilight.dawn
    end
  end

  describe "documentation examples stay true" do
    # The README and the GreenCal moduledoc quote concrete outputs. Pin
    # them here so they cannot drift silently when the ephemerides change.
    test "README quick-start block" do
      day = GreenCal.day(@paris, ~D[2026-06-21], elevation: 35.0)

      assert day.sun.rise == ~U[2026-06-21 03:45:21Z]
      assert Float.round(day.sun.day_length_minutes, 1) == 974.1
      assert day.twilight.dawn == ~U[2026-06-21 03:04:16Z]
      assert day.moon.phase == :first_quarter
      assert day.moon.trend == :descending
      assert day.moon.illumination_trend == :waxing
      assert day.constellation == "Virgo"
      assert day.organ == :root
    end

    test "moduledoc quick start (no elevation)" do
      day = GreenCal.day(@paris, ~D[2026-06-21])
      assert day.sun.rise == ~U[2026-06-21 03:46:57Z]
      assert day.moon.phase == :first_quarter
      assert day.moon.trend == :descending
    end

    test "lunar_events example line" do
      events = GreenCal.lunar_events(Date.range(~D[2026-08-01], ~D[2026-08-31]))
      new = Enum.find(events.phases, &(&1.type == :new_moon))
      assert new.at == ~U[2026-08-12 17:36:40Z]
      assert new.eclipse == :likely
    end

    test "lunar_timeline example block, in the order it is printed" do
      timeline = GreenCal.lunar_timeline(Date.range(~D[2026-08-01], ~D[2026-08-31]))

      assert [first, second, third, fourth | _] = timeline

      assert first == %{
               family: :phase,
               type: :last_quarter,
               at: ~U[2026-08-06 02:21:49Z],
               eclipse: :none
             }

      assert second.family == :standstill
      assert second.type == :northernmost
      assert second.at == ~U[2026-08-08 23:38:08Z]
      assert_in_delta second.declination, 28.107933344152, 1.0e-9

      assert third.family == :apsis
      assert third.type == :perigee
      assert third.at == ~U[2026-08-10 11:16:35Z]
      assert_in_delta third.distance_km, 363_285.244284283, 1.0e-6

      assert fourth.family == :phase
      assert fourth.type == :new_moon
      assert fourth.at == ~U[2026-08-12 17:36:40Z]
    end

    test "README day.events line" do
      day = GreenCal.day(@paris, ~D[2026-06-21], elevation: 35.0)

      assert [{:twilight, :dawn, _}, {:sun, :rise, _} | rest] =
               Enum.map(day.events, &{&1.family, &1.type, &1.at})

      assert Enum.any?(rest, &match?({:moon, :transit, _}, &1))
      assert Enum.any?(rest, &match?({:phase, :first_quarter, _}, &1))
      assert Enum.any?(rest, &match?({:sun, :set, _}, &1))
    end
  end

  describe "polar edge cases" do
    test "apparent midnight sun starts below the Arctic circle" do
      # Rise/set is defined at h₀ = -0.8333° (refraction + semidiameter),
      # not at the geometric horizon, so the Sun stops setting about a
      # degree south of the Arctic circle (66.56°). At 66.0° on the June
      # solstice it bottoms out at -0.56° — above the threshold.
      assert GreenCal.day({66.0, 0.0}, ~D[2026-06-21]).sun.state == :always_above

      # Below the apparent limit (~65.7°) the Sun still sets, barely.
      day = GreenCal.day({65.0, 0.0}, ~D[2026-06-21])
      assert day.sun.state == :normal
      assert %DateTime{} = day.sun.set
    end

    test "midnight sun day" do
      day = GreenCal.day(@tromso, ~D[2026-06-21])
      assert day.sun.state == :always_above
      assert day.sun.rise == nil
      assert day.sun.day_length_minutes == 1440.0
    end

    test "polar night still has civil twilight" do
      day = GreenCal.day(@tromso, ~D[2026-12-21])
      assert day.sun.state == :always_below
      assert day.sun.day_length_minutes == 0.0
      assert day.twilight.state == :normal
      assert %DateTime{} = day.twilight.dawn
    end
  end

  describe "calendar/3" do
    test "returns one entry per date" do
      range = Date.range(~D[2026-07-01], ~D[2026-07-07])
      days = GreenCal.calendar(@paris, range)
      assert length(days) == 7
      assert Enum.map(days, & &1.date) == Enum.to_list(range)
      assert Enum.all?(days, &match?(%GreenCal.Day{}, &1))
    end

    test "parallel: true returns the same days in the same order" do
      range = Date.range(~D[2026-02-25], ~D[2026-03-05])
      assert GreenCal.calendar(@paris, range) == GreenCal.calendar(@paris, range, parallel: true)
    end
  end

  describe "lunar_events/2" do
    test "August 2026: the eclipse new moon, apsides, nodes and standstills" do
      events = GreenCal.lunar_events(Date.range(~D[2026-08-01], ~D[2026-08-31]))

      new = Enum.find(events.phases, &(&1.type == :new_moon))
      assert new.eclipse == :likely
      assert_in_delta DateTime.to_unix(new.at), DateTime.to_unix(~U[2026-08-12 17:37:00Z]), 180

      assert Enum.any?(events.apsides, &(&1.type == :perigee))
      assert Enum.any?(events.nodes, &(&1.type == :descending))
      assert length(events.standstills) in 2..3

      # Everything is stamped as DateTime, no Julian days leak out
      for list <- Map.values(events), e <- list do
        assert %DateTime{} = e.at
        refute Map.has_key?(e, :jd)
      end
    end
  end

  describe "day events" do
    # Rebuilt from the struct fields by hand, so the projection is checked
    # against the struct rather than against itself.
    defp canonical_instants(day) do
      fixed = [
        {:sun, :rise, day.sun.rise},
        {:sun, :transit, day.sun.transit},
        {:sun, :set, day.sun.set},
        {:twilight, :dawn, day.twilight.dawn},
        {:twilight, :dusk, day.twilight.dusk},
        {:moon, :rise, day.moon.rise},
        {:moon, :transit, day.moon.transit},
        {:moon, :set, day.moon.set}
      ]

      geocentric =
        for {family, event} <- [
              {:phase, day.moon.phase_change},
              {:apsis, day.moon.apsis},
              {:node, day.moon.node},
              {:standstill, day.moon.standstill}
            ],
            event != nil,
            do: {family, event.type, event.at}

      for {family, type, at} <- fixed ++ geocentric, at != nil, do: {family, type, at}
    end

    defp as_tuples(events), do: Enum.map(events, &{&1.family, &1.type, &1.at})

    test "the list is exactly the struct's instants, neither dropped nor invented" do
      for date <- Date.range(~D[2026-08-01], ~D[2026-08-31]) do
        day = GreenCal.day(@paris, date)
        canonical = canonical_instants(day)

        assert Enum.sort(as_tuples(day.events)) == Enum.sort(canonical),
               "projection diverged from the struct on #{date}"

        # No duplicates: same length, not just the same set
        assert length(day.events) == length(canonical)
      end
    end

    test "no geocentric field escapes the projection" do
      # Catches a fifth event field being added to Day.Moon without being
      # projected — as soon as it is non-nil on any day of the month.
      for date <- Date.range(~D[2026-08-01], ~D[2026-08-31]) do
        day = GreenCal.day(@paris, date)
        families = day.events |> Enum.map(& &1.family) |> MapSet.new()

        for {key, value} <- Map.from_struct(day.moon),
            is_map(value) and Map.has_key?(value, :at) do
          assert Enum.any?(families, &(&1 in [:phase, :apsis, :node, :standstill])),
                 "#{key} holds an instant on #{date} but no geocentric family is in :events"
        end
      end
    end

    test "entries are uniform: three keys, no optional extras" do
      # August holds all four geocentric families, so every shape is seen.
      events =
        Date.range(~D[2026-08-01], ~D[2026-08-31])
        |> Enum.flat_map(&GreenCal.day(@paris, &1).events)

      assert Enum.any?(events, &(&1.family == :phase))
      assert Enum.any?(events, &(&1.family == :apsis))
      assert Enum.any?(events, &(&1.family == :node))
      assert Enum.any?(events, &(&1.family == :standstill))

      for e <- events do
        assert Enum.sort(Map.keys(e)) == [:at, :family, :type]
        assert %DateTime{} = e.at
      end
    end

    test "the list is chronological" do
      for date <- Date.range(~D[2026-08-01], ~D[2026-08-31]) do
        times = GreenCal.day(@paris, date).events |> Enum.map(& &1.at)
        assert times == Enum.sort(times, DateTime)
      end
    end

    test "a nil geocentric field means the sky, never the configuration" do
      # There is no option to skip these searches, so the only reading of
      # nil is "no such event today" — the ambiguity the :events contract
      # closes for the list must not reopen on the fields it projects.
      busy = GreenCal.day(@paris, ~D[2026-08-12])
      assert busy.moon.phase_change.type == :new_moon

      quiet = GreenCal.day(@paris, ~D[2026-08-03])
      assert quiet.moon.phase_change == nil

      # No option turns them off, whatever a caller passes
      assert GreenCal.day(@paris, ~D[2026-08-12], events: false) == busy
      assert is_list(GreenCal.day(@paris, ~D[2026-08-12], events: false).events)
    end

    test "a quiet day still gets a list, not nil" do
      # No geocentric event, but sun and moon still rise and set
      day = GreenCal.day(@paris, ~D[2026-08-03])
      assert day.moon.phase_change == nil
      assert day.moon.node == nil
      assert day.events != []
      assert Enum.all?(day.events, &(&1.family in [:sun, :twilight, :moon]))
    end

    test "sampled_at is the middle of the civil day" do
      day = GreenCal.day(@paris, ~D[2026-08-12])
      assert day.sampled_at == ~U[2026-08-12 12:00:00Z]
    end

    test "polar day: no sunrise entry, and state says why" do
      day = GreenCal.day(@tromso, ~D[2026-06-21])
      assert day.sun.state == :always_above
      refute Enum.any?(day.events, &(&1.family == :sun and &1.type == :rise))
      refute Enum.any?(day.events, &(&1.family == :sun and &1.type == :set))
    end

    test "polar night: same absence, opposite state" do
      day = GreenCal.day(@tromso, ~D[2026-12-21])
      assert day.sun.state == :always_below
      refute Enum.any?(day.events, &(&1.family == :sun and &1.type == :rise))
    end

    test "calendar/3 gives each day exactly what day/3 gives it" do
      range = Date.range(~D[2026-08-01], ~D[2026-08-31])
      from_calendar = GreenCal.calendar(@paris, range)
      one_by_one = for d <- range, do: GreenCal.day(@paris, d)

      assert from_calendar == one_by_one
    end

    test "calendar/3 accepts any enumerable, including out of order and lazy" do
      dates = [~D[2026-08-12], ~D[2026-08-28], ~D[2026-08-06]]

      from_list = GreenCal.calendar(@paris, dates)
      assert Enum.map(from_list, & &1.date) == dates
      assert from_list == Enum.map(dates, &GreenCal.day(@paris, &1))

      # A stream must be walked exactly once
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      stream =
        Stream.map(dates, fn d ->
          Agent.update(counter, &(&1 + 1))
          d
        end)

      assert GreenCal.calendar(@paris, stream) == from_list
      assert Agent.get(counter, & &1) == 3
    end

    test "a descending range still yields one day per date" do
      descending = Date.range(~D[2026-08-03], ~D[2026-08-01], -1)
      days = GreenCal.calendar(@paris, descending)

      assert Enum.map(days, & &1.date) == [~D[2026-08-03], ~D[2026-08-02], ~D[2026-08-01]]
      assert days == Enum.map(descending, &GreenCal.day(@paris, &1))
    end

    test "parallel: true changes nothing, events included" do
      range = Date.range(~D[2026-08-01], ~D[2026-08-31])
      assert GreenCal.calendar(@paris, range, parallel: true) == GreenCal.calendar(@paris, range)
    end
  end

  describe "lunar_timeline/2" do
    setup do
      {:ok, timeline: GreenCal.lunar_timeline(Date.range(~D[2026-08-01], ~D[2026-08-31]))}
    end

    test "is chronological and tagged by family", %{timeline: timeline} do
      assert timeline != []
      assert Enum.map(timeline, & &1.at) == Enum.sort(Enum.map(timeline, & &1.at), DateTime)

      assert timeline |> Enum.map(& &1.family) |> MapSet.new() ==
               MapSet.new([:phase, :apsis, :node, :standstill])

      for e <- timeline do
        assert %DateTime{} = e.at
        refute Map.has_key?(e, :jd)
      end
    end

    test "carries each family's extra keys", %{timeline: timeline} do
      by_family = Enum.group_by(timeline, & &1.family)

      assert Enum.all?(by_family[:phase], &Map.has_key?(&1, :eclipse))
      assert Enum.all?(by_family[:apsis], &Map.has_key?(&1, :distance_km))
      assert Enum.all?(by_family[:standstill], &Map.has_key?(&1, :declination))
      assert Enum.all?(by_family[:node], &(Map.keys(&1) |> Enum.sort() == [:at, :family, :type]))
    end

    test "lunar_events/2 is the same data, grouped", %{timeline: timeline} do
      events = GreenCal.lunar_events(Date.range(~D[2026-08-01], ~D[2026-08-31]))

      assert Map.keys(events) |> Enum.sort() == [:apsides, :nodes, :phases, :standstills]

      regrouped =
        Enum.group_by(timeline, fn
          %{family: :phase} -> :phases
          %{family: :apsis} -> :apsides
          %{family: :node} -> :nodes
          %{family: :standstill} -> :standstills
        end)

      assert events == regrouped
    end

    test "parallel: true is bit-identical, not merely equivalent", %{timeline: timeline} do
      range = Date.range(~D[2026-08-01], ~D[2026-08-31])
      assert GreenCal.lunar_timeline(range, parallel: true) == timeline
      assert GreenCal.lunar_events(range, parallel: true) == GreenCal.lunar_events(range)
    end

    test "day/3 and the timeline agree on the instants they share", %{timeline: timeline} do
      # Same finders, same windows: the day struct must report exactly the
      # instant the range-wide timeline reports.
      for e <- timeline do
        day = GreenCal.day(@paris, DateTime.to_date(e.at))

        field =
          case e.family do
            :phase -> day.moon.phase_change
            :apsis -> day.moon.apsis
            :node -> day.moon.node
            :standstill -> day.moon.standstill
          end

        assert field.type == e.type
        assert field.at == e.at, "#{e.family} #{e.type} differs between day/3 and the timeline"
      end
    end

    test "rejects a descending range instead of quietly returning nothing" do
      descending = Date.range(~D[2026-08-31], ~D[2026-08-01], -1)

      assert_raise ArgumentError, ~r/ascending date range/, fn ->
        GreenCal.lunar_timeline(descending)
      end

      assert_raise ArgumentError, ~r/ascending date range/, fn ->
        GreenCal.lunar_events(descending)
      end
    end
  end

  describe "input validation" do
    test "rejects out-of-range latitude" do
      assert_raise ArgumentError, ~r/latitude/, fn ->
        GreenCal.day({95.0, 2.0}, ~D[2026-06-21])
      end
    end

    test "rejects out-of-range longitude and hints at argument order" do
      assert_raise ArgumentError, ~r/latitude, longitude/, fn ->
        GreenCal.day({48.85, 200.0}, ~D[2026-06-21])
      end
    end
  end

  describe "sunlight minutes at the polar transition" do
    test "always defined and consistent through Tromsø's midnight-sun onset" do
      # Mid-May: the Sun starts skipping settings — days may hold a single
      # crossing. day_length_minutes must stay defined and grow toward 1440.
      days = GreenCal.calendar(@tromso, Date.range(~D[2026-05-10], ~D[2026-05-25]))

      for d <- days do
        assert is_float(d.sun.day_length_minutes)
        assert d.sun.day_length_minutes >= 0.0 and d.sun.day_length_minutes <= 1440.0
      end

      first = hd(days).sun.day_length_minutes
      last = List.last(days).sun.day_length_minutes
      assert last > first
      assert last > 1400.0
    end
  end
end
