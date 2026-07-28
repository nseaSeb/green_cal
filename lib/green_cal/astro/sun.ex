defmodule GreenCal.Astro.Sun do
  @moduledoc """
  Position of the Sun, Meeus' "low accuracy" method, chapter 25.

  Stated error: ~0.01° on the apparent longitude between 1900 and 2100,
  which is far more than enough to keep rise/set times within the minute.

  As for the Moon, every function takes a **JDE** (Julian day in
  Terrestrial Time).
  """

  import GreenCal.Astro.Time,
    only: [
      julian_century: 1,
      norm360: 1,
      sin_d: 1,
      cos_d: 1,
      mean_obliquity: 1,
      nutation: 1,
      ecliptic_to_equatorial: 3
    ]

  import GreenCal.Astro.Numeric, only: [poly: 2]

  # Standard atmospheric refraction at the horizon (34′) + mean solar
  # semidiameter (16′). This is the convention used by NOAA and published
  # ephemerides: we keep it fixed to stay comparable with reference tables,
  # rather than varying it with the distance (±0.005°).
  @horizon_altitude -0.8333

  @typedoc "Apparent geocentric solar position."
  @type position :: %{
          longitude: float(),
          true_longitude: float(),
          mean_anomaly: float(),
          radius_vector: float(),
          right_ascension: float(),
          declination: float(),
          equation_of_time: float(),
          semidiameter: float()
        }

  @doc """
  Apparent position of the Sun for a **JDE**.

  `:radius_vector` is in astronomical units, `:equation_of_time` in minutes
  of time.

  Meeus' example 25.a (1992 October 13, 0h TD):

      iex> s = GreenCal.Astro.Sun.position(2_448_908.5)
      iex> Float.round(s.longitude, 3)      # published: 199.90895
      199.909
      iex> Float.round(s.declination, 3)    # published: -7.78507
      -7.785
  """
  @spec position(float()) :: position()
  def position(jde) do
    t = julian_century(jde)

    l0 = norm360(poly(t, [280.46646, 36_000.76983, 0.0003032]))
    m = norm360(poly(t, [357.52911, 35_999.05029, -0.0001537]))
    e = poly(t, [0.016708634, -0.000042037, -0.0000001267])

    c =
      poly(t, [1.914602, -0.004817, -0.000014]) * sin_d(m) +
        poly(t, [0.019993, -0.000101]) * sin_d(2 * m) +
        0.000289 * sin_d(3 * m)

    true_longitude = l0 + c
    nu = m + c
    r = 1.000001018 * (1.0 - e * e) / (1.0 + e * cos_d(nu))

    {dpsi, deps} = nutation(t)
    # Annual aberration: −20.4898″ / R (Meeus ch. 25, p. 167)
    aberration = -20.4898 / 3600.0 / r

    lambda = norm360(true_longitude + dpsi + aberration)
    eps = mean_obliquity(t) + deps
    {ra, dec} = ecliptic_to_equatorial(lambda, 0.0, eps)

    %{
      longitude: lambda,
      true_longitude: norm360(true_longitude),
      mean_anomaly: m,
      radius_vector: r,
      right_ascension: ra,
      declination: dec,
      equation_of_time: equation_of_time(eps, l0, m, e),
      semidiameter: 0.2665833 / r
    }
  end

  @doc """
  Equation of time in minutes (Meeus 28.3).

  Example 28.b (1992 October 13, 0h TD): 13 min 42.6 s.
  """
  @spec equation_of_time(float(), float(), float(), float()) :: float()
  def equation_of_time(eps, l0, m, e) do
    y = :math.pow(:math.tan(eps / 2.0 * GreenCal.Astro.Time.rad()), 2)

    radians =
      y * sin_d(2 * l0) - 2.0 * e * sin_d(m) +
        4.0 * e * y * sin_d(m) * cos_d(2 * l0) -
        0.5 * y * y * sin_d(4 * l0) - 1.25 * e * e * sin_d(2 * m)

    radians * GreenCal.Astro.Time.deg() * 4.0
  end

  @doc """
  Altitude of the Sun's center at rise/set: −0.8333°.

  `elevation` in meters above the visible horizon lowers this value by the
  horizon dip, ≈ 0.0347·√h degrees — about one minute of earlier sunrise
  per 100 m.
  """
  @spec horizon_altitude(number()) :: float()
  def horizon_altitude(elevation \\ 0.0), do: @horizon_altitude - horizon_dip(elevation)

  @doc """
  Dip of the visible horizon for an observer `elevation` meters above the
  surrounding terrain: ≈ 0.0347·√h degrees. Zero at or below sea level.
  """
  @spec horizon_dip(number()) :: float()
  def horizon_dip(elevation) when elevation <= 0.0, do: 0.0
  def horizon_dip(elevation), do: 0.0347 * :math.sqrt(elevation)

  @doc """
  Conventional twilight altitudes, in degrees.

      iex> GreenCal.Astro.Sun.twilight_altitude(:civil)
      -6.0
  """
  @spec twilight_altitude(:civil | :nautical | :astronomical) :: float()
  def twilight_altitude(:civil), do: -6.0
  def twilight_altitude(:nautical), do: -12.0
  def twilight_altitude(:astronomical), do: -18.0
end
