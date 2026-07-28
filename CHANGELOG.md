# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-07-28

### Changed

- Reworded the package description. The previous wording listed
  "biodynamic cycles" alongside the astronomy, which reads as an
  endorsement of the tradition rather than a description of what the
  library computes. It now leads with the verifiable ephemerides and
  attributes the declination cycle to the calendars that use it, matching
  the separation the README and the `GreenCal` moduledoc already draw.

No code changes: 0.1.0 and 0.1.1 are functionally identical.

## [0.1.0] - 2026-07-28

First release.

### Added

- `GreenCal.day/3` — everything about one civil day at one location: sun
  rise/transit/set with azimuths, time above the horizon, twilights, moon
  rise/transit/set, phase, illuminated fraction, distance, declination,
  node crossing, and the constellation the Moon stands in.
- `GreenCal.calendar/3` — one day per date of a range, with `parallel: true`
  to spread independent days over the schedulers.
- `GreenCal.lunar_events/2` — exact instants of the events a printed lunar
  calendar marks with a symbol: phases (with an eclipse screening flag),
  perigees and apogees, node crossings, and lunar standstills.
- `GreenCal.constellation_of/3` — equal-sector sidereal zodiac (Lahiri
  ayanamsa) by default, or the real unequal IAU boundaries with
  `boundaries: :iau` (13 constellations, Ophiuchus included), the
  convention printed biodynamic calendars use.
- The three independent lunar cycles kept distinct: waxing/waning
  (illumination), ascending/descending (declination), approaching/receding
  (distance).
- Low-level astronomy is public: `GreenCal.Astro` (UT-facing facade),
  `GreenCal.Astro.Sun`, `GreenCal.Astro.Moon`, `GreenCal.Astro.RiseSet`
  (generic crossing finder over any body) and `GreenCal.Astro.Time`.
- Options: `:elevation`, `:time_zone`, `:twilight`, `:boundaries`,
  `:delta_t`, `:parallel`.

### Notes on the approach

- **Zero runtime dependencies**, and no time zone database needed unless
  `:time_zone` is used.
- **Rise/set by numeric search**, not the closed-form hour-angle formula:
  the latter assumes a constant declination and can be more than 15 minutes
  off for the Moon. Crossings shorter than the sampling step are caught by
  probing the culmination, so a 55-minute polar day is found rather than
  reported as polar night.
- **UT and TT are kept apart** (`jd` vs `jde`), converted in one place.
  ΔT uses observed IERS values over 2000–2026, the Espenak & Meeus
  polynomials before, and a documented hold-then-bridge extrapolation
  after.
- **Degenerate cases are reported, not faked**: `:always_above` /
  `:always_below` states, and a `nil` moonrise on the ~1 day per month the
  Moon does not rise.
- **Astronomy and tradition are labelled apart.** Rise/set times, phases
  and declination trends are validated against published references;
  elements, organs and sowing days are presented as the tradition they are.

### Validated against

- Meeus, *Astronomical Algorithms* (2nd ed.), examples 7.1, 12.a, 12.b,
  22.a, 25.a, 28.b and 47.a — the complete chapter 47 tables reproduce
  example 47.a to 0.13″ in longitude and 0.03 km in distance.
- USNO rise/set API for moonrise/moonset at Paris, Sydney and Edinburgh,
  within 30 s (the USNO publishes whole minutes).
- Published 2026 phase instants, and all four 2026 eclipses found by the
  screening flag with no false positive over the year.
- Property tests and physical invariants (bounded distance and latitude,
  event ordering, chained daily windows equal to one continuous search).

[Unreleased]: https://github.com/nseaSeb/green_cal/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/nseaSeb/green_cal/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/nseaSeb/green_cal/releases/tag/v0.1.0
