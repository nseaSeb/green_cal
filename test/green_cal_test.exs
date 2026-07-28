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
  end

  describe "polar edge cases" do
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
