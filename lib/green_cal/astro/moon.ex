defmodule GreenCal.Astro.Moon do
  @moduledoc """
  Position of the Moon: truncated ELP-2000/82 theory as published by Meeus,
  *Astronomical Algorithms* (2nd ed.), chapter 47.

  **Complete** tables 47.A and 47.B (60 terms in longitude/distance, 60 in
  latitude) plus the additive terms A₁/A₂/A₃. Accuracy stated by Meeus:
  ~10″ in longitude, ~4″ in latitude.

  Every function takes a **JDE** (Julian day in Terrestrial Time). The
  UT → TT conversion is the caller's responsibility, see
  `GreenCal.Astro.Time.jd_to_jde/2`.
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

  @deg 180.0 / :math.pi()

  # Earth equatorial radius, km (IAU 1976) — for the parallax.
  @earth_radius 6378.14

  # Table 47.A — {D, M, M', F, Σl coefficient (1e-6 °), Σr coefficient (1e-3 km)}
  @terms_lr [
    {0, 0, 1, 0, 6_288_774, -20_905_355},
    {2, 0, -1, 0, 1_274_027, -3_699_111},
    {2, 0, 0, 0, 658_314, -2_955_968},
    {0, 0, 2, 0, 213_618, -569_925},
    {0, 1, 0, 0, -185_116, 48_888},
    {0, 0, 0, 2, -114_332, -3_149},
    {2, 0, -2, 0, 58_793, 246_158},
    {2, -1, -1, 0, 57_066, -152_138},
    {2, 0, 1, 0, 53_322, -170_733},
    {2, -1, 0, 0, 45_758, -204_586},
    {0, 1, -1, 0, -40_923, -129_620},
    {1, 0, 0, 0, -34_720, 108_743},
    {0, 1, 1, 0, -30_383, 104_755},
    {2, 0, 0, -2, 15_327, 10_321},
    {0, 0, 1, 2, -12_528, 0},
    {0, 0, 1, -2, 10_980, 79_661},
    {4, 0, -1, 0, 10_675, -34_782},
    {0, 0, 3, 0, 10_034, -23_210},
    {4, 0, -2, 0, 8_548, -21_636},
    {2, 1, -1, 0, -7_888, 24_208},
    {2, 1, 0, 0, -6_766, 30_824},
    {1, 0, -1, 0, -5_163, -8_379},
    {1, 1, 0, 0, 4_987, -16_675},
    {2, -1, 1, 0, 4_036, -12_831},
    {2, 0, 2, 0, 3_994, -10_445},
    {4, 0, 0, 0, 3_861, -11_650},
    {2, 0, -3, 0, 3_665, 14_403},
    {0, 1, -2, 0, -2_689, -7_003},
    {2, 0, -1, 2, -2_602, 0},
    {2, -1, -2, 0, 2_390, 10_056},
    {1, 0, 1, 0, -2_348, 6_322},
    {2, -2, 0, 0, 2_236, -9_884},
    {0, 1, 2, 0, -2_120, 5_751},
    {0, 2, 0, 0, -2_069, 0},
    {2, -2, -1, 0, 2_048, -4_950},
    {2, 0, 1, -2, -1_773, 4_130},
    {2, 0, 0, 2, -1_595, 0},
    {4, -1, -1, 0, 1_215, -3_958},
    {0, 0, 2, 2, -1_110, 0},
    {3, 0, -1, 0, -892, 3_258},
    {2, 1, 1, 0, -810, 2_616},
    {4, -1, -2, 0, 759, -1_897},
    {0, 2, -1, 0, -713, -2_117},
    {2, 2, -1, 0, -700, 2_354},
    {2, 1, -2, 0, 691, 0},
    {2, -1, 0, -2, 596, 0},
    {4, 0, 1, 0, 549, -1_423},
    {0, 0, 4, 0, 537, -1_117},
    {4, -1, 0, 0, 520, -1_571},
    {1, 0, -2, 0, -487, -1_739},
    {2, 1, 0, -2, -399, 0},
    {0, 0, 2, -2, -381, -4_421},
    {1, 1, 1, 0, 351, 0},
    {3, 0, -2, 0, -340, 0},
    {4, 0, -3, 0, 330, 0},
    {2, -1, 2, 0, 327, 0},
    {0, 2, 1, 0, -323, 1_165},
    {1, 1, -1, 0, 299, 0},
    {2, 0, 3, 0, 294, 0},
    {2, 0, -1, -2, 0, 8_752}
  ]

  # Table 47.B — {D, M, M', F, Σb coefficient (1e-6 °)}
  @terms_b [
    {0, 0, 0, 1, 5_128_122},
    {0, 0, 1, 1, 280_602},
    {0, 0, 1, -1, 277_693},
    {2, 0, 0, -1, 173_237},
    {2, 0, -1, 1, 55_413},
    {2, 0, -1, -1, 46_271},
    {2, 0, 0, 1, 32_573},
    {0, 0, 2, 1, 17_198},
    {2, 0, 1, -1, 9_266},
    {0, 0, 2, -1, 8_822},
    {2, -1, 0, -1, 8_216},
    {2, 0, -2, -1, 4_324},
    {2, 0, 1, 1, 4_200},
    {2, 1, 0, -1, -3_359},
    {2, -1, -1, 1, 2_463},
    {2, -1, 0, 1, 2_211},
    {2, -1, -1, -1, 2_065},
    {0, 1, -1, -1, -1_870},
    {4, 0, -1, -1, 1_828},
    {0, 1, 0, 1, -1_794},
    {0, 0, 0, 3, -1_749},
    {0, 1, -1, 1, -1_565},
    {1, 0, 0, 1, -1_491},
    {0, 1, 1, 1, -1_475},
    {0, 1, 1, -1, -1_410},
    {0, 1, 0, -1, -1_344},
    {1, 0, 0, -1, -1_335},
    {0, 0, 3, 1, 1_107},
    {4, 0, 0, -1, 1_021},
    {4, 0, -1, 1, 833},
    {0, 0, 1, -3, 777},
    {4, 0, -2, 1, 671},
    {2, 0, 0, -3, 607},
    {2, 0, 2, -1, 596},
    {2, -1, 1, -1, 491},
    {2, 0, -2, 1, -451},
    {0, 0, 3, -1, 439},
    {2, 0, 2, 1, 422},
    {2, 0, -3, -1, 421},
    {2, 1, -1, 1, -366},
    {2, 1, 0, 1, -351},
    {4, 0, 0, 1, 331},
    {2, -1, 1, 1, 315},
    {2, -2, 0, -1, 302},
    {0, 0, 1, 3, -283},
    {2, 1, 1, -1, -229},
    {1, 1, 0, -1, 223},
    {1, 1, 0, 1, 223},
    {0, 1, -2, -1, -220},
    {2, 1, -1, -1, -220},
    {1, 0, 1, 1, -185},
    {2, -1, -2, -1, 181},
    {0, 1, 2, 1, -177},
    {4, 0, -2, -1, 176},
    {4, -1, -1, -1, 166},
    {1, 0, 1, -1, -164},
    {4, 0, 1, -1, 132},
    {1, 0, -1, -1, -119},
    {4, -1, 0, -1, 115},
    {2, -2, 0, 1, 107}
  ]

  @typedoc """
  Geocentric lunar position.

    * `:longitude` / `:latitude` — **apparent** ecliptic coordinates
      (nutation applied), in degrees
    * `:distance_km` — center-to-center distance
    * `:parallax` — equatorial horizontal parallax π, in degrees
    * `:right_ascension` / `:declination` — apparent equatorial, in degrees
    * `:semidiameter` — geocentric apparent semidiameter, in degrees
  """
  @type position :: %{
          longitude: float(),
          latitude: float(),
          distance_km: float(),
          parallax: float(),
          right_ascension: float(),
          declination: float(),
          semidiameter: float()
        }

  @doc """
  Apparent geocentric position of the Moon for a **JDE** (Terrestrial Time).

  Meeus' example 47.a (1992 April 12, 0h TD):

      iex> m = GreenCal.Astro.Moon.position(2_448_724.5)
      iex> Float.round(m.longitude, 4)   # published: 133.167265
      133.1672
      iex> Float.round(m.latitude, 4)    # published: -3.229126
      -3.2291
      iex> Float.round(m.distance_km, 1) # published: 368409.7
      368409.7
  """
  @spec position(float()) :: position()
  def position(jde) do
    t = julian_century(jde)

    # Fundamental arguments (Meeus 47.1 to 47.5)
    lp =
      norm360(poly(t, [218.3164477, 481_267.88123421, -0.0015786, 1 / 538_841, -1 / 65_194_000]))

    d =
      norm360(poly(t, [297.8501921, 445_267.1114034, -0.0018819, 1 / 545_868, -1 / 113_065_000]))

    m = norm360(poly(t, [357.5291092, 35_999.0502909, -0.0001536, 1 / 24_490_000]))
    mp = norm360(poly(t, [134.9633964, 477_198.8675055, 0.0087414, 1 / 69_699, -1 / 14_712_000]))

    f =
      norm360(poly(t, [93.2720950, 483_202.0175233, -0.0036539, -1 / 3_526_000, 1 / 863_310_000]))

    # Additive terms from Venus (A₁), Jupiter (A₂) and Earth's flattening (A₃)
    a1 = norm360(119.75 + 131.849 * t)
    a2 = norm360(53.09 + 479_264.290 * t)
    a3 = norm360(313.45 + 481_266.484 * t)

    # Eccentricity of Earth's orbit: weights the terms involving M
    e = 1.0 - 0.002516 * t - 0.0000074 * t * t

    {sum_l, sum_r} =
      Enum.reduce(@terms_lr, {0.0, 0.0}, fn {cd, cm, cmp, cf, coef_l, coef_r}, {sl, sr} ->
        arg = cd * d + cm * m + cmp * mp + cf * f
        w = ecc_weight(e, cm)
        {sl + coef_l * w * sin_d(arg), sr + coef_r * w * cos_d(arg)}
      end)

    sum_b =
      Enum.reduce(@terms_b, 0.0, fn {cd, cm, cmp, cf, coef}, acc ->
        arg = cd * d + cm * m + cmp * mp + cf * f
        acc + coef * ecc_weight(e, cm) * sin_d(arg)
      end)

    sum_l =
      sum_l + 3958.0 * sin_d(a1) + 1962.0 * sin_d(lp - f) + 318.0 * sin_d(a2)

    sum_b =
      sum_b - 2235.0 * sin_d(lp) + 382.0 * sin_d(a3) + 175.0 * sin_d(a1 - f) +
        175.0 * sin_d(a1 + f) + 127.0 * sin_d(lp - mp) - 115.0 * sin_d(lp + mp)

    lambda_geo = norm360(lp + sum_l / 1_000_000.0)
    beta = sum_b / 1_000_000.0
    distance = 385_000.56 + sum_r / 1000.0
    parallax = :math.asin(@earth_radius / distance) * @deg

    {dpsi, deps} = nutation(t)
    lambda = norm360(lambda_geo + dpsi)
    eps = mean_obliquity(t) + deps
    {ra, dec} = ecliptic_to_equatorial(lambda, beta, eps)

    %{
      longitude: lambda,
      latitude: beta,
      distance_km: distance,
      parallax: parallax,
      right_ascension: ra,
      declination: dec,
      # k = 0.272481: ratio of lunar to Earth radius
      semidiameter: :math.asin(0.272481 * @earth_radius / distance) * @deg
    }
  end

  @doc """
  Altitude h₀ of the Moon's center at rise/set, in degrees.

  Meeus, ch. 15: `h₀ = 0.7275·π − 34′`. The 0.7275 factor absorbs the
  semidiameter and the parallax, the 34′ the standard atmospheric
  refraction. It **differs** from the Sun's −0.8333°: using the solar value
  for the Moon shifts rise times by several minutes.
  """
  @spec horizon_altitude(position()) :: float()
  def horizon_altitude(%{parallax: pi}), do: 0.7275 * pi - 0.5666667

  # Meeus: terms involving M are multiplied by E^|M|
  defp ecc_weight(_e, 0), do: 1.0
  defp ecc_weight(e, cm) when cm == 1 or cm == -1, do: e
  defp ecc_weight(e, _cm), do: e * e
end
