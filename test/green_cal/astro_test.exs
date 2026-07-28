defmodule GreenCal.AstroTest do
  use ExUnit.Case, async: true

  alias GreenCal.Astro
  alias GreenCal.Astro.Time

  @paris {48.8566, 2.3522}
  @quito {-0.1807, -78.4678}
  @tromso {69.6492, 18.9553}

  defp day_window(date), do: {Time.julian_day(date), Time.julian_day(Date.add(date, 1))}

  defp find_event(%{events: events}, type), do: Enum.find(events, &(&1.type == type))

  describe "sun_events/4 — external anchors" do
    test "Paris, 2026 summer solstice: sunrise ≈ 03:47 UTC, sunset ≈ 19:58 UTC" do
      {j0, j1} = day_window(~D[2026-06-21])
      result = Astro.sun_events(@paris, j0, j1)

      assert result.state == :normal
      rise = find_event(result, :rise)
      set = find_event(result, :set)

      rise_utc = Time.to_datetime(rise.jd)
      set_utc = Time.to_datetime(set.jd)

      assert_in_delta DateTime.to_unix(rise_utc), DateTime.to_unix(~U[2026-06-21 03:47:00Z]), 300
      assert_in_delta DateTime.to_unix(set_utc), DateTime.to_unix(~U[2026-06-21 19:58:00Z]), 300
    end

    test "Paris, 2026 winter solstice: sunrise ≈ 07:41 UTC, sunset ≈ 15:56 UTC" do
      {j0, j1} = day_window(~D[2026-12-21])
      result = Astro.sun_events(@paris, j0, j1)

      rise = find_event(result, :rise)
      set = find_event(result, :set)

      assert_in_delta DateTime.to_unix(Time.to_datetime(rise.jd)),
                      DateTime.to_unix(~U[2026-12-21 07:41:00Z]),
                      360

      assert_in_delta DateTime.to_unix(Time.to_datetime(set.jd)),
                      DateTime.to_unix(~U[2026-12-21 15:56:00Z]),
                      360
    end
  end

  describe "sun_events/4 — physical invariants" do
    test "equinox day length is close to 12 h at very different latitudes" do
      for loc <- [@paris, @quito] do
        {j0, j1} = day_window(~D[2026-03-20])
        result = Astro.sun_events(loc, j0, j1)
        rise = find_event(result, :rise)
        set = find_event(result, :set)

        length_minutes = (set.jd - rise.jd) * 1440.0
        # Refraction + semidiameter make the equinox day slightly longer than 12 h
        assert_in_delta length_minutes, 727, 10
      end
    end

    test "equinox sunrise azimuth is close to due East" do
      {j0, j1} = day_window(~D[2026-03-20])
      rise = @paris |> Astro.sun_events(j0, j1) |> find_event(:rise)
      assert_in_delta rise.azimuth, 90.0, 1.5
    end

    test "transit altitude equals 90° − lat + declination" do
      {j0, j1} = day_window(~D[2026-05-10])
      transit = @paris |> Astro.sun_events(j0, j1) |> find_event(:transit)

      {lat, _} = @paris
      dec = Astro.sun(transit.jd).declination
      assert_in_delta transit.altitude, 90.0 - lat + dec, 0.1
    end

    test "elevation makes the day longer" do
      {j0, j1} = day_window(~D[2026-05-10])

      sea = Astro.sun_events(@paris, j0, j1)
      mountain = Astro.sun_events(@paris, j0, j1, elevation: 1500.0)

      day = fn r -> find_event(r, :set).jd - find_event(r, :rise).jd end
      # ~1 min earlier sunrise + ~1 min later sunset per 100 m... at 1500 m
      # the day stretches by several minutes on each side.
      assert day.(mountain) > day.(sea) + 10.0 / 1440.0
    end

    test "midnight sun and polar night in Tromsø" do
      {j0, j1} = day_window(~D[2026-06-21])
      assert Astro.sun_events(@tromso, j0, j1).state == :always_above

      {j0, j1} = day_window(~D[2026-12-21])
      assert Astro.sun_events(@tromso, j0, j1).state == :always_below
    end
  end

  describe "twilight_events/5" do
    test "civil dawn precedes sunrise, dusk follows sunset" do
      {j0, j1} = day_window(~D[2026-04-15])

      sun_rise = @paris |> Astro.sun_events(j0, j1) |> find_event(:rise)
      dawn = @paris |> Astro.twilight_events(j0, j1, :civil) |> find_event(:rise)

      assert dawn.jd < sun_rise.jd
      # Civil twilight lasts roughly half an hour at Paris latitudes
      assert_in_delta (sun_rise.jd - dawn.jd) * 1440.0, 32, 8
    end

    test "civil twilight still happens during Tromsø's polar night" do
      {j0, j1} = day_window(~D[2026-12-21])
      result = Astro.twilight_events(@tromso, j0, j1, :civil)
      assert result.state == :normal
      assert find_event(result, :rise)
    end
  end

  describe "moon_events/4 — USNO anchors" do
    # Reference times from the USNO rise/set API
    # (https://aa.usno.navy.mil/api/rstt/oneday, tz=0), retrieved 2026-07-28.
    # USNO publishes whole minutes; 90 s tolerance covers their rounding
    # plus our method error.
    @usno_anchors [
      {"Paris", {48.8566, 2.3522}, ~D[2026-08-13],
       [
         rise: ~U[2026-08-13 05:22:00Z],
         transit: ~U[2026-08-13 12:36:00Z],
         set: ~U[2026-08-13 19:31:00Z]
       ]},
      {"Sydney", {-33.8688, 151.2093}, ~D[2026-03-10],
       [
         set: ~U[2026-03-10 02:10:00Z],
         rise: ~U[2026-03-10 11:53:00Z],
         transit: ~U[2026-03-10 19:28:00Z]
       ]},
      {"Edinburgh", {55.9533, -3.1883}, ~D[2026-11-05],
       [
         rise: ~U[2026-11-05 02:46:00Z],
         transit: ~U[2026-11-05 08:59:00Z],
         set: ~U[2026-11-05 14:53:00Z]
       ]}
    ]

    for {name, loc, date, expected} <- @usno_anchors do
      test "#{name}, #{date}" do
        {j0, j1} = day_window(unquote(Macro.escape(date)))
        result = Astro.moon_events(unquote(Macro.escape(loc)), j0, j1)
        assert result.state == :normal

        for {type, ref} <- unquote(Macro.escape(expected)) do
          event = Enum.find(result.events, &(&1.type == type))
          assert event, "missing #{type}"

          assert_in_delta DateTime.to_unix(GreenCal.Astro.Time.to_datetime(event.jd)),
                          DateTime.to_unix(ref),
                          90,
                          "#{type} off USNO reference #{ref}"
        end
      end
    end
  end

  describe "moon_events/4" do
    test "roughly one moonrise per day over a synodic month" do
      j0 = Time.julian_day(~D[2026-07-01])
      result = Astro.moon_events(@paris, j0, j0 + 29.5)
      rises = Enum.count(result.events, &(&1.type == :rise))

      # The Moon rises ~50 min later each day: 28 or 29 rises in 29.5 days
      assert rises in 27..30
    end

    test "rises and sets alternate" do
      j0 = Time.julian_day(~D[2026-07-01])
      result = Astro.moon_events(@paris, j0, j0 + 10.0, transits: false)

      result.events
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [a, b] -> assert a.type != b.type end)
    end
  end

  describe "phase_events/3" do
    test "published instants of early 2026" do
      j0 = Time.julian_day(~D[2026-01-01])
      events = Astro.phase_events(j0, j0 + 31.0)

      full = Enum.find(events, &(&1.type == :full_moon))
      new = Enum.find(events, &(&1.type == :new_moon))

      # Timeanddate/USNO: full 2026-01-03 10:03 UTC, new 2026-01-18 19:52 UTC
      assert_in_delta DateTime.to_unix(Time.to_datetime(full.jd)),
                      DateTime.to_unix(~U[2026-01-03 10:03:00Z]),
                      180

      assert_in_delta DateTime.to_unix(Time.to_datetime(new.jd)),
                      DateTime.to_unix(~U[2026-01-18 19:52:00Z]),
                      180
    end

    test "the four phases cycle in order, ~7.4 days apart" do
      j0 = Time.julian_day(~D[2026-03-01])
      events = Astro.phase_events(j0, j0 + 60.0)

      order = [:new_moon, :first_quarter, :full_moon, :last_quarter]

      events
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [a, b] ->
        ia = Enum.find_index(order, &(&1 == a.type))
        assert Enum.at(order, rem(ia + 1, 4)) == b.type
        # Quarter spacing swings with the Moon's orbital eccentricity
        assert_in_delta b.jd - a.jd, 7.38, 1.2
      end)
    end

    test "2026 eclipse screening finds the four real eclipses and no false alarm on quarters" do
      j0 = Time.julian_day(~D[2026-01-01])
      events = Astro.phase_events(j0, j0 + 365.0)

      flagged =
        for %{eclipse: e, type: t, jd: jd} <- events, e != :none do
          {t, Time.to_datetime(jd) |> DateTime.to_date()}
        end

      # 2026: annular solar Feb 17, total lunar Mar 3, total solar Aug 12,
      # partial lunar Aug 28.
      assert {:new_moon, ~D[2026-02-17]} in flagged
      assert {:full_moon, ~D[2026-03-03]} in flagged
      assert {:new_moon, ~D[2026-08-12]} in flagged
      assert {:full_moon, ~D[2026-08-28]} in flagged

      # USNO gave 17:37 UTC for the August 12 new moon
      aug = Enum.find(events, &(&1.type == :new_moon and &1.jd > Time.julian_day(~D[2026-08-01])))

      assert_in_delta DateTime.to_unix(Time.to_datetime(aug.jd)),
                      DateTime.to_unix(~U[2026-08-12 17:37:00Z]),
                      180

      assert Enum.all?(events, fn e ->
               e.type in [:new_moon, :full_moon] or e.eclipse == :none
             end)
    end

    test "a synodic year holds 12 or 13 of each phase" do
      j0 = Time.julian_day(~D[2026-01-01])
      events = Astro.phase_events(j0, j0 + 365.0)

      by_type = Enum.frequencies_by(events, & &1.type)

      for type <- [:new_moon, :first_quarter, :full_moon, :last_quarter] do
        assert by_type[type] in 12..13
      end
    end
  end

  describe "apsis_events/3 and declination_extrema/3" do
    test "perigee and apogee alternate with sane distances" do
      j0 = Time.julian_day(~D[2026-01-01])
      events = Astro.apsis_events(j0, j0 + 60.0)

      assert length(events) >= 4

      events
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [a, b] ->
        assert a.type != b.type
        # Half an anomalistic month, with real-world spread
        assert_in_delta b.jd - a.jd, 13.8, 2.5
      end)

      for %{type: :perigee, distance_km: d} <- events, do: assert(d < 370_400)
      for %{type: :apogee, distance_km: d} <- events, do: assert(d > 404_000)
    end

    test "declination extrema are the ascending/descending flips" do
      j0 = Time.julian_day(~D[2026-06-01])
      events = Astro.declination_extrema(j0, j0 + 60.0)

      assert length(events) >= 4

      events
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [a, b] ->
        assert a.type != b.type
        assert_in_delta b.jd - a.jd, 13.66, 1.0
      end)

      # 2025-2026 sits near a major lunar standstill: |δ| reaches ~28°
      for %{type: :northernmost, declination: d} <- events, do: assert(d > 18.0 and d < 29.5)
      for %{type: :southernmost, declination: d} <- events, do: assert(d < -18.0 and d > -29.5)

      # The daily trend derived in GreenCal.day flips at these instants
      %{jd: jd, type: type} = hd(events)
      before_day = Time.to_datetime(jd - 1.5) |> DateTime.to_date()
      after_day = Time.to_datetime(jd + 1.5) |> DateTime.to_date()
      expected_before = if type == :northernmost, do: :ascending, else: :descending
      expected_after = if type == :northernmost, do: :descending, else: :ascending
      assert GreenCal.day(@paris, before_day).moon.trend == expected_before
      assert GreenCal.day(@paris, after_day).moon.trend == expected_after
    end
  end

  describe "phase/2" do
    test "full moon of 2026 January 3 (~10:03 UTC)" do
      # Timeanddate/USNO give 2026-01-03 10:03 UTC for this full moon.
      jd = Time.julian_day(~U[2026-01-03 10:03:00Z])
      p = Astro.phase(jd)

      assert_in_delta p.elongation, 180.0, 0.5
      assert p.illuminated_fraction > 0.99
      assert Astro.phase_name(p.elongation) == :full_moon
    end

    test "new moon of 2026 January 18 (~19:52 UTC)" do
      jd = Time.julian_day(~U[2026-01-18 19:52:00Z])
      p = Astro.phase(jd)

      assert p.elongation < 2.0 or p.elongation > 358.0
      assert p.illuminated_fraction < 0.01
      assert Astro.phase_name(p.elongation) == :new_moon
    end

    test "illuminated fraction sweeps the full range over a month" do
      j0 = GreenCal.Astro.Time.julian_day(~D[2026-03-01])
      fractions = for i <- 0..59, do: Astro.phase(j0 + i * 0.5).illuminated_fraction

      assert Enum.min(fractions) < 0.02
      assert Enum.max(fractions) > 0.98
    end
  end
end
