defmodule GreenCal.Astro.TimeTest do
  use ExUnit.Case, async: true

  alias GreenCal.Astro.Time

  doctest GreenCal.Astro.Time

  describe "julian_day/3 — Meeus ch. 7 examples" do
    test "Sputnik launch, 1957 October 4.81" do
      assert_in_delta Time.julian_day(1957, 10, 4.81), 2_436_116.31, 1.0e-6
    end

    test "J2000.0" do
      assert Time.julian_day(2000, 1, 1.5) == 2_451_545.0
    end

    test "1987 January 27.0" do
      assert Time.julian_day(1987, 1, 27) == 2_446_822.5
    end

    test "1988 June 19.5" do
      assert Time.julian_day(1988, 6, 19.5) == 2_447_332.0
    end
  end

  describe "julian_day/1 vs julian_day/3" do
    test "DateTime and Y/M/D forms agree" do
      dt = ~U[2026-07-28 18:30:00Z]
      assert_in_delta Time.julian_day(dt), Time.julian_day(2026, 7, 28 + 18.5 / 24.0), 1.0e-9
    end

    test "round-trips through to_datetime" do
      dt = ~U[2026-03-20 14:45:51Z]
      assert Time.to_datetime(Time.julian_day(dt)) == dt
    end
  end

  describe "gmst/1 — Meeus ch. 12 examples" do
    test "example 12.b: 1987 April 10, 19h21m UT" do
      jd = Time.julian_day(1987, 4, 10 + (19 + 21 / 60.0) / 24.0)
      assert_in_delta Time.gmst(jd), 128.7378734, 0.0001
    end

    test "example 12.a: 1987 April 10, 0h UT" do
      # 13h10m46.3668s sidereal = 197.693195°
      assert_in_delta Time.gmst(2_446_895.5), 197.693195, 0.0001
    end
  end

  describe "nutation and obliquity — Meeus example 22.a" do
    setup do
      {:ok, t: Time.julian_century(2_446_895.5)}
    end

    test "nutation in longitude", %{t: t} do
      {dpsi, _} = Time.nutation(t)
      # Published (full series): -3.788″. Short series tolerance: 0.5″.
      assert_in_delta dpsi * 3600.0, -3.788, 0.5
    end

    test "nutation in obliquity", %{t: t} do
      {_, deps} = Time.nutation(t)
      assert_in_delta deps * 3600.0, 9.443, 0.5
    end

    test "mean obliquity", %{t: t} do
      # 23°26'27.407"
      assert_in_delta Time.mean_obliquity(t), 23.440947, 1.0e-5
    end

    test "true obliquity", %{t: t} do
      # 23°26'36.850"
      assert_in_delta Time.true_obliquity(t), 23.443569, 3.0e-4
    end
  end

  describe "delta_t/1" do
    # Reference: observed IERS values, USNO ser7/deltat.data (2026-07-28)
    test "observed anchors are honored" do
      for {year, expected} <- [{2000, 63.83}, {2010, 66.07}, {2020, 69.36}, {2026, 69.11}] do
        assert_in_delta Time.delta_t(Time.julian_day(year, 1, 1)), expected, 0.05
      end
    end

    test "interpolates between January anchors" do
      # July 2015 sits between 67.6439 and 68.1024
      mid = Time.delta_t(Time.julian_day(2015, 7, 1))
      assert mid > 67.65 and mid < 68.10
    end

    test "year 1990 matches the observed ~56.9 s (polynomial branch)" do
      assert_in_delta Time.delta_t(Time.julian_day(1990, 7, 1)), 56.9, 1.0
    end

    test "continuous at the polynomial → table junction (2000)" do
      before = Time.delta_t(Time.julian_day(1999, 12, 15))
      after_ = Time.delta_t(Time.julian_day(2000, 1, 15))
      assert abs(after_ - before) < 0.5
    end

    test "holds the last observed value after the table" do
      assert_in_delta Time.delta_t(Time.julian_day(2035, 6, 1)), 69.13, 0.1
    end

    test "monotonic and finite on the far future bridge" do
      v2049 = Time.delta_t(Time.julian_day(2049, 6, 1))
      v2100 = Time.delta_t(Time.julian_day(2100, 6, 1))
      v2200 = Time.delta_t(Time.julian_day(2200, 6, 1))
      assert v2049 < v2100 and v2100 < v2200
    end

    test "delta_t override is honored by jd_to_jde" do
      assert Time.jd_to_jde(2_451_545.0, 0) == 2_451_545.0
      assert_in_delta Time.jd_to_jde(2_451_545.0, 86_400.0), 2_451_546.0, 1.0e-9
    end
  end

  describe "angle helpers" do
    test "norm360" do
      assert Time.norm360(370.0) == 10.0
      assert Time.norm360(-10.0) == 350.0
      assert Time.norm360(720.0) == 0.0
    end

    test "norm180" do
      assert Time.norm180(190.0) == -170.0
      assert Time.norm180(-190.0) == 170.0
      assert Time.norm180(10.0) == 10.0
    end
  end
end
