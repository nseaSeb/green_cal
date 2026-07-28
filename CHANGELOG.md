# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-07-28

Ergonomics, from feedback after consuming 0.1.1 in a real application. No
change to any computed quantity: every instant and every number 0.1.1
produced, 0.2.0 produces identically.

### Added

- **`GreenCal.Day` `:events`** — the day as one chronology. Everything
  that happens at an instant, sorted, in a single uniform shape
  `%{family:, type:, at:}`: sun and moon rise/transit/set, dawn and dusk,
  and the geocentric instants below. Displaying "what happens today" no
  longer means flattening four lists, tagging them, grouping them by local
  date, merging them with rise/set and sorting the result.

  It is a **projection of the struct**, not a second computation: it is
  built by reading the finished struct back, so a field and its entry in
  the list are the same value by construction. Seven families, split
  between topocentric (`:sun`, `:twilight`, `:moon` — they depend on where
  you stand) and geocentric (`:phase`, `:apsis`, `:node`, `:standstill` —
  the same instants everywhere on Earth). An absent entry is not a
  non-event: `:state` still says whether the Sun failed to rise or failed
  to set.

- **`GreenCal.Day.Moon` `:phase_change`, `:apsis`, `:standstill`** — the
  canonical home of those instants, next to `:node`, which already had
  one. Each is `%{type:, at:, …}` or `nil`, and carries its family's extra
  data (`:eclipse`, `:distance_km`, `:declination`) so that `:events` can
  stay uniform. All four are always computed, so `nil` says something
  about the sky and never about how the day was requested.

  `:phase_change` rather than `:phase_instant`: next to `:phase`, which
  names the day at `sampled_at` (`:waxing_gibbous`), "phase instant" reads
  as "the instant of the phase", which is not what it is. It is the
  instant the Moon crosses into a new principal phase.

- **`GreenCal.Day` `:sampled_at`** — the instant every scalar of the day
  is evaluated at: the middle of the civil day, local noon under a
  `:time_zone`. This was true in 0.1.1 and only discoverable by reading
  the source. `illuminated_fraction` shown at 23:00 is the value it had at
  noon; the moduledoc now says so, and lists every field concerned —
  `phase`, `elongation`, `distance_km`, `declination`,
  `ecliptic_latitude`, the three `*_trend` fields, `constellation`,
  `element` and `organ`.

- **`GreenCal.lunar_timeline/2`** — the four geocentric families as one
  chronological list, each entry tagged with its `:family`. Previously
  `lunar_events/2` returned four lists with heterogeneous keys and no
  discriminant, so merging them meant labelling them yourself.

- **`:parallel` on `lunar_timeline/2` and `lunar_events/2`**, matching
  `calendar/3`. The four families are independent searches over the same
  range, so they are what gets parallelized — not the range. The result is
  therefore identical to the sequential one down to the last bit, with no
  reasoning needed about events landing on a sub-range boundary. Roughly
  halves the wall clock over a year (measured 186 ms → 88 ms, 8
  schedulers); the ceiling is the slowest single family, so this is close
  to all there is to get.

- **The `:time_zone` contract for zones that switch at midnight** (Cuba,
  Chile, Lord Howe…). Where local midnight does not exist, the civil day
  starts at the first instant after the jump and runs 23 h; where it
  happens twice, it starts at the first of the two and runs 25 h. Days
  therefore tile the year: no instant belongs to two of them, and none to
  neither. 0.1.1 already behaved this way — it was a code comment, and
  which 24 h window counts as "the day" decides which events fall in it,
  so it belongs in the contract.

### Changed

- **`lunar_events/2` is now a view over `lunar_timeline/2`**, grouped by
  family, and its events carry the new `:family` key. Same four keys,
  same order, same instants. This is the structural fix for the two paths
  to a node crossing that 0.1.1 had: `day.moon.node` and
  `lunar_events(…).nodes` were verified identical, but nothing prevented
  them drifting. They now come from one list.

- `GreenCal.day/3` runs three geocentric searches it did not run before.
  0.1.1 already ran the fourth for `moon.node`, but that one is by far the
  cheapest: 0.05 ms of the 0.93 ms the four now cost together. The added
  cost depends on whether the day carries an event, since finding one
  means bisecting for it — measured at Paris, a quiet day goes from 2.75
  to 3.05 ms (+0.3), a day carrying a new moon from 2.84 to 3.6 ms
  (+0.76). Nowhere near the doubling a per-day event search might suggest,
  which is why the default is `true` and the escape hatch is an option
  rather than the other way round.

- `lunar_timeline/2` and `lunar_events/2` raise `ArgumentError` on a
  descending `Date.Range` instead of quietly returning nothing. 0.1.1
  handed the finders a backwards window, which they sampled the wrong way
  round.

- `calendar/3` is documented as computing each day exactly as `day/3`
  would, so the two agree bit for bit in every time zone. Sharing one
  geocentric search across the range was implemented and then dropped: it
  measured within noise of the per-day searches — the cost sits in the
  bisections, whose number depends on how many events exist, not on how
  the range is cut — and it made `calendar/3` disagree with `day/3` by a
  few milliseconds under a `:time_zone`, where a DST day is 23 or 25 hours
  long and the sampling grids stop lining up.

### Considered and rejected

- **An `events: false` option** to skip the four geocentric searches. It
  was implemented, then removed before release. Skipping them makes
  `moon.node` and its three new neighbours `nil` for two different
  reasons — no such event today, or not computed — with nothing to tell
  them apart. That is exactly the ambiguity the `:events` contract closes
  for the list, reopened on the fields the list projects, and the
  consumer most likely to pass the option is the one processing volume,
  who would read a configuration artefact as an astronomical fact. At the
  measured cost (+0.3 ms on a quiet day) it did not buy enough to be
  worth a permanently ambiguous struct.

  For many places at once, the answer is not to skip the searches but to
  do them once: the geocentric instants are identical everywhere, so
  `lunar_timeline/2` covers a whole region in one call.

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

[Unreleased]: https://github.com/nseaSeb/green_cal/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/nseaSeb/green_cal/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/nseaSeb/green_cal/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/nseaSeb/green_cal/releases/tag/v0.1.0
