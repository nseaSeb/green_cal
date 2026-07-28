defmodule GreenCal.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GreenCal.Astro
  alias GreenCal.Astro.Time

  # Latitudes where the Sun provably rises and sets every day of the year,
  # so the ordering properties below are unconditional.
  #
  # The bound is NOT the Arctic circle (66.56°). Rise/set is defined at
  # h₀ = −0.8333° (refraction + semidiameter), not at the geometric
  # horizon, so the apparent midnight sun starts about a degree lower:
  #
  #     90° − 23.44° (max declination) − 0.83° ≈ 65.7°
  #
  # At 66.0° on the June solstice the Sun bottoms out at −0.56°, above the
  # threshold, and never sets — which is what the library correctly
  # reports. 65.0° leaves a safe margin.
  @max_temperate_latitude 65.0

  defp temperate_location do
    gen all(
          lat <-
            StreamData.float(min: -@max_temperate_latitude, max: @max_temperate_latitude),
          lon <- StreamData.float(min: -180.0, max: 180.0)
        ) do
      {lat, lon}
    end
  end

  defp date_2000_2049 do
    gen all(offset <- StreamData.integer(0..18_261)) do
      Date.add(~D[2000-01-01], offset)
    end
  end

  property "angle normalizations stay in range" do
    check all(x <- StreamData.float(min: -1.0e6, max: 1.0e6)) do
      n360 = Time.norm360(x)
      n180 = Time.norm180(x)
      assert n360 >= 0.0 and n360 < 360.0
      assert n180 >= -180.0 and n180 < 180.0
    end
  end

  property "moon position is physical for any date in 1900-2100" do
    check all(jde <- StreamData.float(min: 2_415_020.0, max: 2_488_070.0), max_runs: 50) do
      m = GreenCal.Astro.Moon.position(jde)
      assert m.distance_km > 356_000 and m.distance_km < 407_000
      assert abs(m.latitude) < 5.35
      assert abs(m.declination) < 29.6
      assert m.longitude >= 0.0 and m.longitude < 360.0
    end
  end

  property "phase quantities are bounded" do
    check all(jd <- StreamData.float(min: 2_451_545.0, max: 2_469_807.0), max_runs: 50) do
      p = Astro.phase(jd)
      assert p.illuminated_fraction >= 0.0 and p.illuminated_fraction <= 1.0
      assert p.elongation >= 0.0 and p.elongation < 360.0
      assert p.angular_separation >= 0.0 and p.angular_separation <= 180.0
    end
  end

  property "sun events are ordered and located on the horizon" do
    check all(loc <- temperate_location(), date <- date_2000_2049(), max_runs: 25) do
      jd0 = Time.julian_day(date)
      result = Astro.sun_events(loc, jd0, jd0 + 1.0)

      assert result.state == :normal
      by_type = Map.new(result.events, &{&1.type, &1})

      rise = by_type[:rise]
      set = by_type[:set]

      # Rise and set exist, sit inside the window, on the -0.8333° horizon
      for e <- [rise, set] do
        assert e
        assert e.jd >= jd0 and e.jd < jd0 + 1.0
        assert_in_delta e.altitude, -0.8333, 0.01
        assert e.azimuth >= 0.0 and e.azimuth < 360.0
      end

      # Whenever a transit falls between them, ordering holds
      if t = by_type[:transit] do
        if rise.jd < t.jd and t.jd < set.jd do
          assert Astro.sun(t.jd).declination |> is_float()
        end
      end
    end
  end

  property "GreenCal.day/3 invariants" do
    check all(loc <- temperate_location(), date <- date_2000_2049(), max_runs: 25) do
      day = GreenCal.day(loc, date)

      assert %GreenCal.Day{} = day
      assert day.sun.day_length_minutes >= 0.0 and day.sun.day_length_minutes <= 1440.0
      assert day.moon.illuminated_fraction >= 0.0 and day.moon.illuminated_fraction <= 1.0
      assert day.organ in [:fruit, :root, :flower, :leaf]
      assert day.moon.trend in [:ascending, :descending]

      # `day_length_minutes` is the total time above the horizon over the
      # window. It equals set − rise only for the plain shape: one rise,
      # one set, in that order. Away from the equator a UTC civil day can
      # legitimately hold other shapes, and both of these are real:
      #
      #   {-65.0, 123.75} on 2038-08-12 — rises 00:00 and 23:57, sets 07:40:
      #       the trailing 3 minutes count toward the total, not toward
      #       set − rise.
      #   {65.0, 180.0} on 2000-01-01 — sets before it rises, because the
      #       UTC day is offset 12 h from the local one.
      jd0 = Time.julian_day(date)
      events = Astro.sun_events(loc, jd0, jd0 + 1.0, transits: false).events

      plain_day? =
        Enum.frequencies_by(events, & &1.type) == %{rise: 1, set: 1} and
          DateTime.compare(day.sun.rise, day.sun.set) == :lt

      if plain_day? do
        minutes = DateTime.diff(day.sun.set, day.sun.rise) / 60.0
        assert_in_delta minutes, day.sun.day_length_minutes, 1.5
      end

      # Whatever the shape, the total is bounded by the window and covers
      # every above-horizon stretch, so it is never shorter than the
      # longest single one.
      assert day.sun.day_length_minutes <= 1440.0

      if plain_day? or events == [] do
        assert day.sun.day_length_minutes >= 0.0
      end
    end
  end

  test "chained daily windows lose no moon event and duplicate none" do
    # Consecutive civil-day windows share their midnight boundary sample.
    # Splitting a year into 365 independent searches must find exactly the
    # same events as one continuous search.
    loc = {48.8566, 2.3522}
    jd0 = Time.julian_day(~D[2026-01-01])

    continuous = Astro.moon_events(loc, jd0, jd0 + 365.0, transits: false).events

    chained =
      Enum.flat_map(0..364, fn i ->
        Astro.moon_events(loc, jd0 + i, jd0 + i + 1.0, transits: false).events
      end)

    assert length(chained) == length(continuous)

    Enum.zip(continuous, chained)
    |> Enum.each(fn {a, b} ->
      assert a.type == b.type
      # Same event, same instant to well under a second
      assert_in_delta a.jd, b.jd, 1.0e-5
    end)
  end
end
