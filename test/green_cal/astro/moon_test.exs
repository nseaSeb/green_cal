defmodule GreenCal.Astro.MoonTest do
  use ExUnit.Case, async: true

  alias GreenCal.Astro.Moon

  doctest GreenCal.Astro.Moon

  describe "Meeus example 47.a — 1992 April 12, 0h TD" do
    # Published values, Astronomical Algorithms 2nd ed., p. 342-343.
    setup do
      {:ok, m: Moon.position(2_448_724.5)}
    end

    test "apparent ecliptic longitude", %{m: m} do
      # Geocentric λ 133.162655°; apparent (with Δψ = +16.595″) 133.167265°
      assert_in_delta m.longitude, 133.167265, 0.0002
    end

    test "ecliptic latitude", %{m: m} do
      assert_in_delta m.latitude, -3.229126, 0.0002
    end

    test "distance", %{m: m} do
      assert_in_delta m.distance_km, 368_409.7, 0.5
    end

    test "equatorial horizontal parallax", %{m: m} do
      assert_in_delta m.parallax, 0.991990, 0.00002
    end

    test "apparent right ascension", %{m: m} do
      assert_in_delta m.right_ascension, 134.688470, 0.0005
    end

    test "apparent declination", %{m: m} do
      assert_in_delta m.declination, 13.768368, 0.0005
    end
  end

  describe "lunar h₀" do
    test "differs markedly from the solar -0.8333°" do
      m = Moon.position(2_448_724.5)
      h0 = Moon.horizon_altitude(m)
      # 0.7275 × 0.99199 − 0.56667 ≈ +0.155°
      assert_in_delta h0, 0.1551, 0.001
    end
  end

  describe "physical consistency over a cycle" do
    test "distance stays within the real perigee/apogee range" do
      for i <- 0..400 do
        jde = 2_460_000.5 + i * 0.7
        %{distance_km: d} = Moon.position(jde)
        assert d > 356_000 and d < 407_000, "aberrant distance #{d} at JDE #{jde}"
      end
    end

    test "ecliptic latitude stays bounded by the orbital inclination" do
      for i <- 0..400 do
        jde = 2_460_000.5 + i * 0.7
        %{latitude: b} = Moon.position(jde)
        assert abs(b) < 5.35, "aberrant latitude #{b} at JDE #{jde}"
      end
    end
  end
end
