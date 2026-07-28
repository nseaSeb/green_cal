defmodule GreenCal.Astro.SunTest do
  use ExUnit.Case, async: true

  alias GreenCal.Astro.Sun

  doctest GreenCal.Astro.Sun

  describe "Meeus example 25.a — 1992 October 13, 0h TD" do
    setup do
      {:ok, s: Sun.position(2_448_908.5)}
    end

    test "apparent longitude", %{s: s} do
      assert_in_delta s.longitude, 199.90895, 0.001
    end

    test "radius vector", %{s: s} do
      assert_in_delta s.radius_vector, 0.99766, 0.0001
    end

    test "apparent right ascension", %{s: s} do
      # 13h13m31.4s = 198.38083°
      assert_in_delta s.right_ascension, 198.38083, 0.002
    end

    test "apparent declination", %{s: s} do
      # -7°47'06" = -7.78507°
      assert_in_delta s.declination, -7.78507, 0.002
    end

    test "equation of time — Meeus example 28.b: 13m42.6s", %{s: s} do
      assert_in_delta s.equation_of_time, 13.71, 0.02
    end
  end

  describe "horizon_altitude/1" do
    test "sea level is the standard -0.8333°" do
      assert Sun.horizon_altitude(0.0) == -0.8333
    end

    test "elevation lowers the horizon by 0.0347·√h" do
      assert_in_delta Sun.horizon_altitude(100.0), -0.8333 - 0.347, 1.0e-9
    end
  end
end
