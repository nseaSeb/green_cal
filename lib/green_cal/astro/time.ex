defmodule GreenCal.Astro.Time do
  @moduledoc """
  Time scales, Julian day, ΔT, sidereal time, nutation and obliquity.

  ## The two time scales, and why they matter

  Two time scales coexist in this kind of computation, and mixing them up is
  the classic mistake:

    * **UT** (universal time, ≈ UTC) — Earth's rotation. It drives
      **sidereal time**, hence hour angles, hence rise/set times.
    * **TT** (terrestrial time) — a uniform scale. It is what the
      **ephemeris series** (Sun and Moon positions) consume.

    TT = UT + ΔT

  ΔT is ≈ 69 s in 2026 and slowly grows. Applying ΔT on both sides (or on
  neither) introduces a systematic bias: ~69 s on rise times, and ~38″ on
  the lunar longitude (the Moon moves 0.55″ per second).

  Naming convention throughout the library:

    * `jd`  — Julian day in **UT**
    * `jde` — Julian day in **TT** (Meeus' "Julian Ephemeris Day")

  ## ΔT

  Three regimes:

    * **Before 2000** — Espenak & Meeus polynomials (NASA GSFC, *Five
      Millennium Canon of Solar Eclipses*), which were fit to the
      historical observations.
    * **2000 to early 2026** — observed IERS values (USNO
      `ser7/deltat.data`, retrieved 2026-07-28), linearly interpolated
      between the January anchors. The Espenak & Meeus 2005–2050 branch is
      **not** used there: Earth's rotation sped up after 2005 and the
      polynomial overshoots by ~6 s in 2026 (75.1 s predicted vs 69.11 s
      observed).
    * **After the table** — the last observed value is held flat until
      2050, then bridged linearly to the long-term parabola at 2150.
      Future ΔT is genuinely unknowable (that is the whole reason IERS
      exists); holding ~69 s is a far better guess for the coming decades
      than the polynomial's 75–93 s. Expect the error to stay < 1 s for
      ~10 years and grow slowly after.

  For use cases that demand better, `delta_t` can be overridden everywhere
  through the `:delta_t` option (in seconds).
  """

  import GreenCal.Astro.Numeric, only: [poly: 2]

  @j2000 2_451_545.0
  @unix_epoch_jd 2_440_587.5
  @rad :math.pi() / 180.0
  @deg 180.0 / :math.pi()

  @doc "The J2000.0 epoch as a Julian day."
  def j2000, do: @j2000

  # ── Julian day ─────────────────────────────────────────────────────────

  @doc """
  Julian day (UT) of a date at 0h, of a `DateTime` or of a `NaiveDateTime`.

  A `DateTime` in a non-UTC zone is converted to UTC through its offset:
  no time zone database is required.

      iex> GreenCal.Astro.Time.julian_day(~U[2000-01-01 12:00:00Z])
      2451545.0

      iex> GreenCal.Astro.Time.julian_day(~D[2000-01-01])
      2451544.5
  """
  @spec julian_day(Date.t() | DateTime.t() | NaiveDateTime.t()) :: float()
  def julian_day(%DateTime{} = dt) do
    DateTime.to_unix(dt, :microsecond) / 86_400_000_000 + @unix_epoch_jd
  end

  def julian_day(%NaiveDateTime{} = ndt) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> julian_day()
  end

  def julian_day(%Date{} = date) do
    julian_day(date.year, date.month, date.day * 1.0)
  end

  @doc """
  Julian day from year / month / decimal day (Gregorian calendar).

  Meeus, *Astronomical Algorithms*, formula 7.1. Gregorian only: before
  1582-10-15 the result is a proleptic extrapolation.

      iex> GreenCal.Astro.Time.julian_day(1957, 10, 4.81)
      2436116.31
  """
  @spec julian_day(integer(), integer(), number()) :: float()
  def julian_day(year, month, day) do
    {y, m} = if month <= 2, do: {year - 1, month + 12}, else: {year, month}
    a = Integer.floor_div(y, 100)
    b = 2 - a + Integer.floor_div(a, 4)

    floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + day + b - 1524.5
  end

  @doc """
  UTC `DateTime` corresponding to a UT Julian day.

  Rounded to the second by default; pass `:microsecond` for full precision.
  """
  @spec to_datetime(float(), :second | :microsecond) :: DateTime.t()
  def to_datetime(jd, precision \\ :second) do
    us = round((jd - @unix_epoch_jd) * 86_400_000_000)

    case precision do
      :second -> DateTime.from_unix!(round(us / 1_000_000), :second)
      :microsecond -> DateTime.from_unix!(us, :microsecond)
    end
  end

  @doc "Julian centuries elapsed since J2000.0."
  @spec julian_century(float()) :: float()
  def julian_century(jd), do: (jd - @j2000) / 36_525.0

  # ── ΔT ─────────────────────────────────────────────────────────────────

  # Observed ΔT (TT − UT1), IERS via USNO ser7/deltat.data, retrieved
  # 2026-07-28. January 1st values; last entry is the file's final month.
  @observed_delta_t [
    {2000.0, 63.8285},
    {2001.0, 64.0908},
    {2002.0, 64.2998},
    {2003.0, 64.4734},
    {2004.0, 64.5736},
    {2005.0, 64.6876},
    {2006.0, 64.8452},
    {2007.0, 65.1464},
    {2008.0, 65.4573},
    {2009.0, 65.7768},
    {2010.0, 66.0699},
    {2011.0, 66.3246},
    {2012.0, 66.6030},
    {2013.0, 66.9069},
    {2014.0, 67.2810},
    {2015.0, 67.6439},
    {2016.0, 68.1024},
    {2017.0, 68.5927},
    {2018.0, 68.9676},
    {2019.0, 69.2202},
    {2020.0, 69.3612},
    {2021.0, 69.3594},
    {2022.0, 69.2945},
    {2023.0, 69.2039},
    {2024.0, 69.1752},
    {2025.0, 69.1377},
    {2026.0, 69.1099},
    {2026.25, 69.1330}
  ]

  @table_end @observed_delta_t |> List.last() |> elem(0)
  @last_observed @observed_delta_t |> List.last() |> elem(1)
  # Consecutive anchor pairs, zipped once at compile time
  @observed_pairs Enum.zip(@observed_delta_t, tl(@observed_delta_t))

  @doc """
  ΔT = TT − UT, in seconds, for a Julian day.

  Observed IERS values on 2000–2026, Espenak & Meeus polynomials before,
  a documented extrapolation after. See the `@moduledoc`.
  """
  @spec delta_t(float()) :: float()
  def delta_t(jd), do: delta_t_for_year(decimal_year(jd))

  @doc """
  Decimal year of a Julian day, the variable of the ΔT polynomials.

  Computed arithmetically as Julian years since 2000-01-01 — valid for any
  date, arbitrarily far in past or future. The ≤ 0.002-year drift against
  the calendar year is far below ΔT's own uncertainty.
  """
  @spec decimal_year(float()) :: float()
  def decimal_year(jd), do: 2000.0 + (jd - 2_451_544.5) / 365.25

  defp delta_t_for_year(y) when y < 500 do
    u = y / 100.0

    poly(u, [
      10_583.6,
      -1014.41,
      33.78311,
      -5.952053,
      -0.1798452,
      0.022174192,
      0.0090316521
    ])
  end

  defp delta_t_for_year(y) when y < 1600 do
    u = (y - 1000) / 100.0

    poly(u, [
      1574.2,
      -556.01,
      71.23472,
      0.319781,
      -0.8503463,
      -0.005050998,
      0.0083572073
    ])
  end

  defp delta_t_for_year(y) when y < 1700 do
    t = y - 1600
    poly(t, [120.0, -0.9808, -0.01532]) + t * t * t / 7129.0
  end

  defp delta_t_for_year(y) when y < 1800 do
    t = y - 1700
    poly(t, [8.83, 0.1603, -0.0059285, 0.00013336]) - :math.pow(t, 4) / 1_174_000.0
  end

  defp delta_t_for_year(y) when y < 1860 do
    poly(y - 1800, [
      13.72,
      -0.332447,
      0.0068612,
      0.0041116,
      -0.00037436,
      0.0000121272,
      -0.0000001699,
      0.000000000875
    ])
  end

  defp delta_t_for_year(y) when y < 1900 do
    t = y - 1860

    poly(t, [7.62, 0.5737, -0.251754, 0.01680668, -0.0004473624]) +
      :math.pow(t, 5) / 233_174.0
  end

  defp delta_t_for_year(y) when y < 1920 do
    poly(y - 1900, [-2.79, 1.494119, -0.0598939, 0.0061966, -0.000197])
  end

  defp delta_t_for_year(y) when y < 1941 do
    poly(y - 1920, [21.20, 0.84493, -0.076100, 0.0020936])
  end

  defp delta_t_for_year(y) when y < 1961 do
    t = y - 1950
    29.07 + 0.407 * t - t * t / 233.0 + t * t * t / 2547.0
  end

  defp delta_t_for_year(y) when y < 1986 do
    t = y - 1975
    45.45 + 1.067 * t - t * t / 260.0 - t * t * t / 718.0
  end

  defp delta_t_for_year(y) when y < 2000 do
    poly(y - 2000, [
      63.86,
      0.3345,
      -0.060374,
      0.0017275,
      0.000651814,
      0.00002373599
    ])
  end

  # Observed IERS values, linearly interpolated between anchors
  defp delta_t_for_year(y) when y <= @table_end do
    {{y0, v0}, {y1, v1}} =
      Enum.find(@observed_pairs, fn {{y0, _}, {y1, _}} -> y >= y0 and y <= y1 end)

    v0 + (v1 - v0) * (y - y0) / (y1 - y0)
  end

  # Beyond observations: hold the last value (see @moduledoc), then bridge
  # linearly to the long-term parabola between 2050 and 2150.
  defp delta_t_for_year(y) when y < 2050, do: @last_observed

  defp delta_t_for_year(y) when y < 2150 do
    @last_observed + (long_term_parabola(2150.0) - @last_observed) * (y - 2050.0) / 100.0
  end

  defp delta_t_for_year(y), do: long_term_parabola(y)

  defp long_term_parabola(y) do
    u = (y - 1820) / 100.0
    -20.0 + 32.0 * u * u
  end

  @doc """
  Converts a UT Julian day to a Julian Ephemeris Day (TT).

  `delta_t` may be forced (seconds) — required to reproduce Meeus'
  published examples, which are given directly in TT.
  """
  @spec jd_to_jde(float(), number() | nil) :: float()
  def jd_to_jde(jd, delta_t \\ nil)
  def jd_to_jde(jd, nil), do: jd + delta_t(jd) / 86_400.0
  def jd_to_jde(jd, dt), do: jd + dt / 86_400.0

  # ── Obliquity and nutation ─────────────────────────────────────────────

  @doc """
  Mean obliquity of the ecliptic ε₀, in degrees (Meeus 22.2).
  """
  @spec mean_obliquity(float()) :: float()
  def mean_obliquity(t) do
    u = t / 100.0

    23.0 + (26.0 + 21.448 / 60.0) / 60.0 +
      poly(u, [
        0.0,
        -4680.93,
        -1.55,
        1999.25,
        -51.38,
        -249.67,
        -39.05,
        7.12,
        27.87,
        5.79,
        2.45
      ]) / 3600.0
  end

  @doc """
  Nutation in longitude and in obliquity, in degrees (Meeus ch. 22,
  short series).

  Accuracy ≈ 0.5″, more than enough here.

  Returns `{delta_psi, delta_eps}`.
  """
  @spec nutation(float()) :: {float(), float()}
  def nutation(t) do
    omega = 125.04452 - 1934.136261 * t
    l = 280.4665 + 36_000.7698 * t
    lp = 218.3165 + 481_267.8813 * t

    dpsi =
      (-17.20 * sin_d(omega) - 1.32 * sin_d(2 * l) - 0.23 * sin_d(2 * lp) +
         0.21 * sin_d(2 * omega)) / 3600.0

    deps =
      (9.20 * cos_d(omega) + 0.57 * cos_d(2 * l) + 0.10 * cos_d(2 * lp) -
         0.09 * cos_d(2 * omega)) / 3600.0

    {dpsi, deps}
  end

  @doc "True obliquity ε = ε₀ + Δε, in degrees."
  @spec true_obliquity(float()) :: float()
  def true_obliquity(t) do
    {_dpsi, deps} = nutation(t)
    mean_obliquity(t) + deps
  end

  # ── Sidereal time ──────────────────────────────────────────────────────

  @doc """
  Greenwich mean sidereal time, in degrees, for a **UT** Julian day
  (Meeus 12.4).
  """
  @spec gmst(float()) :: float()
  def gmst(jd) do
    d = jd - @j2000
    t = d / 36_525.0

    norm360(
      280.46061837 + 360.98564736629 * d + 0.000387933 * t * t -
        t * t * t / 38_710_000.0
    )
  end

  @doc """
  Greenwich apparent sidereal time, in degrees: GMST + Δψ·cos ε.

  Strictly speaking the `t` argument (Julian century) should be in TT;
  using UT instead shifts the result by about 10⁻⁷ degree.
  """
  @spec gast(float()) :: float()
  def gast(jd) do
    t = julian_century(jd)
    {dpsi, deps} = nutation(t)
    norm360(gmst(jd) + dpsi * cos_d(mean_obliquity(t) + deps))
  end

  # ── Coordinate conversions ─────────────────────────────────────────────

  @doc """
  Ecliptic (λ, β) → equatorial (α, δ), in degrees (Meeus 13.3/13.4).
  """
  @spec ecliptic_to_equatorial(float(), float(), float()) :: {float(), float()}
  def ecliptic_to_equatorial(lambda, beta, eps) do
    ra =
      :math.atan2(
        sin_d(lambda) * cos_d(eps) - :math.tan(beta * @rad) * sin_d(eps),
        cos_d(lambda)
      ) * @deg

    dec =
      :math.asin(sin_d(beta) * cos_d(eps) + cos_d(beta) * sin_d(eps) * sin_d(lambda)) *
        @deg

    {norm360(ra), dec}
  end

  # ── Small trigonometric helpers ────────────────────────────────────────

  @doc "Normalizes an angle into [0, 360)."
  @spec norm360(float()) :: float()
  def norm360(x) do
    r = :math.fmod(x, 360.0)
    r = if r < 0.0, do: r + 360.0, else: r
    # A tiny negative fmod result rounds up to exactly 360.0 in the
    # addition above — clamp so the [0, 360) contract really holds.
    if r >= 360.0, do: 0.0, else: r
  end

  @doc "Normalizes an angle into [-180, 180)."
  @spec norm180(float()) :: float()
  def norm180(x), do: norm360(x + 180.0) - 180.0

  @doc "Sine of an angle in degrees."
  def sin_d(x), do: :math.sin(x * @rad)

  @doc "Cosine of an angle in degrees."
  def cos_d(x), do: :math.cos(x * @rad)

  @doc "Radians per degree."
  def rad, do: @rad

  @doc "Degrees per radian."
  def deg, do: @deg
end
