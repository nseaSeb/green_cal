# GreenCal 🌱🌙

[![CI](https://github.com/nseaSeb/green_cal/actions/workflows/ci.yml/badge.svg)](https://github.com/nseaSeb/green_cal/actions/workflows/ci.yml)

Agricultural sun & moon calendar for Elixir — **pure arithmetic, zero
dependencies, no time zone database required**.

From a geolocation, a date (or a period) and optionally an elevation,
GreenCal computes:

- **Sun** — sunrise, solar noon, sunset, day length, rise/set azimuths,
  civil / nautical / astronomical twilights (Meeus ch. 25, ~1 s of time)
- **Moon** — moonrise, moonset, transit, phase, illuminated fraction,
  distance (full Meeus ch. 47 series, validated against example 47.a to
  0.13″ in longitude)
- **The three independent lunar cycles** used by agricultural calendars:
  waxing/waning (illumination), **ascending/descending** (declination — the
  one biodynamic sowing calendars actually use), perigee/apogee (distance)
- **Exact instants** of everything a printed calendar marks with a symbol
  (`GreenCal.lunar_events/2`): phases (with an eclipse screening flag),
  perigees/apogees, node crossings, and lunar standstills (the exact
  ascending → descending flips)
- The constellation the Moon stands in — equal-sector sidereal zodiac
  (Lahiri) by default, or the real unequal **IAU boundaries** (13
  constellations, Ophiuchus included) with `boundaries: :iau`, the
  convention of printed biodynamic calendars — plus its element
  (fire/earth/air/water) and the traditionally associated plant organ
  (fruit/root/flower/leaf)

Rise/set times are found by numeric search (sampling + bisection) rather
than the closed-form hour-angle formula, so **moonrise is accurate too**
(the closed form can be 15+ minutes off for the Moon) and polar edge cases
(midnight sun, polar night, "no moonrise today") are reported explicitly
instead of producing garbage. ΔT (TT − UT) uses **observed IERS values**
on 2000–2026, the Espenak & Meeus polynomials before that, and a
documented hold-then-bridge extrapolation after — so results don't drift
over the years.

## Usage

```elixir
loc = {48.8566, 2.3522}   # Paris; {lat, lon}, East positive

day = GreenCal.day(loc, ~D[2026-06-21], elevation: 35.0)

day.sun.rise                #=> ~U[2026-06-21 03:45:21Z]
day.sun.day_length_minutes  #=> 974.1
day.twilight.dawn           #=> ~U[2026-06-21 03:04:16Z]
day.moon.phase              #=> :first_quarter
day.moon.trend              #=> :descending   (declination — sowing calendars)
day.moon.illumination_trend #=> :waxing       (independent cycle!)
day.constellation           #=> "Virgo"
day.organ                   #=> :root

# A whole month, with local times (needs a tz database, e.g. tzdata):
GreenCal.calendar(loc, Date.range(~D[2026-07-01], ~D[2026-07-31]),
  time_zone: "Europe/Paris")

# A year in ~160 ms:
GreenCal.calendar(loc, Date.range(~D[2026-01-01], ~D[2026-12-31]), parallel: true)

# Exact instants of phases, apsides, nodes and standstills (geocentric):
GreenCal.lunar_events(Date.range(~D[2026-08-01], ~D[2026-08-31]))
# phases: [%{type: :new_moon, at: ~U[2026-08-12 17:36:40Z], eclipse: :likely}, ...]
```

The low-level astronomy is public too — `GreenCal.Astro` (UT-facing facade),
`GreenCal.Astro.Sun`, `GreenCal.Astro.Moon`, `GreenCal.Astro.RiseSet`,
`GreenCal.Astro.Time` — if you need positions, ephemerides or custom events.

An interactive tour lives in [`livebooks/green_cal.livemd`](livebooks/green_cal.livemd).

## Accuracy

| Quantity | Method | Validated against |
| --- | --- | --- |
| Solar position | Meeus ch. 25 (low accuracy) | Example 25.a |
| Lunar position | Meeus ch. 47, full 60+60 term tables | Example 47.a (0.13″ / 0.03 km) |
| Nutation | Meeus ch. 22 short series (~0.5″) | Example 22.a |
| Sidereal time | Meeus ch. 12 | Examples 12.a / 12.b |
| ΔT | Observed IERS 2000–2026, polynomials before, hold-then-bridge after | USNO `deltat.data` |
| Sun rise/set | numeric search | NOAA-consistent, < 1 min for \|lat\| < 66° |
| Moon rise/set | numeric search with per-instant parallax h₀ | USNO API (Paris, Sydney, Edinburgh — ≤ 30 s) |
| Phase instants | elongation crossings, bisection | Published 2026 instants (≤ 3 min) |
| Eclipse screening | \|β\| at syzygy (Meeus ch. 54 criterion) | All 4 eclipses of 2026, no false positive |
| IAU constellations | boundary table (J2000) + precession | Solar entry dates, all 13 constellations |

**Honesty note.** The astronomy above is science; elements, organs and
"sowing days" are tradition. GreenCal computes the former rigorously and
labels the latter for what it is.

## Known limitations

- **Refraction is the fixed standard 34′.** Real refraction varies with
  temperature and pressure; near the horizon at high latitudes this can
  shift a rise time by several minutes on unusual days. NOAA and USNO
  tables share this convention.
- **`:elevation` models an unobstructed horizon below the observer**
  (hilltop, coast, plain). In a valley the visible horizon is higher, not
  lower — pass `0` and expect the sun later than computed.
- **Moon times are geocentric** apart from the parallax term absorbed in
  h₀; the topocentric transit can differ by a few seconds.
- **Future ΔT is unknowable.** Observed values end in 2026; beyond, the
  last value is held (documented in `GreenCal.Astro.Time`). Error should
  stay under a second for ~a decade, then grow slowly. Override with
  `:delta_t` if you need better.
- **Eclipse flags are screening, not circumstances** — "an eclipse happens
  somewhere on Earth", not where or how deep.

## Installation

```elixir
def deps do
  [
    {:green_cal, "~> 0.1.0"}
  ]
end
```

Documentation: <https://hexdocs.pm/green_cal>.

## License

MIT
