defmodule GreenCal.Day do
  @moduledoc """
  One computed civil day — the return type of `GreenCal.day/3`.

  All `DateTime` fields are UTC unless a `:time_zone` option was given.
  A `nil` event time means the event does not occur within the civil day;
  check the matching `:state` field to know why.

  ## Instants versus scalars

  The day holds two kinds of value, and they are not sampled the same way.

  **Instants** — `sun.rise`, `twilight.dawn`, `moon.set`, `moon.node.at`,
  `moon.phase_change.at` … — are exact: each is searched for within the
  civil day and reported to the second.

  **Scalars** are a snapshot taken at `sampled_at`, the middle of the civil
  day (local noon when a `:time_zone` is given). That covers every number
  and label the day carries: `moon.phase`, `moon.elongation`,
  `moon.illuminated_fraction`, `moon.distance_km`, `moon.declination`,
  `moon.ecliptic_latitude`, the three `*_trend` fields (computed from ±12 h
  around `sampled_at`), and `constellation` / `element` / `organ`.

  So `illuminated_fraction` displayed at 23:00 is the value it had at noon,
  not at 23:00 — the Moon's illumination moves by about 1.5 points over a
  day. For a value at an arbitrary instant, call `GreenCal.Astro.phase/2`
  or `GreenCal.Astro.moon/2` directly.

  ## `:events` — the day's chronology

  `:events` is the **ordered view of the instants this struct already
  holds**, not a second computation. Every entry has a canonical home in a
  field (`sun.rise`, `twilight.dusk`, `moon.node`, `moon.apsis`…) and the
  list is a projection of those fields, so the two cannot drift apart.

      for e <- day.events, do: {e.family, e.type, e.at}
      #=> [{:twilight, :dawn, ...}, {:sun, :rise, ...}, {:moon, :set, ...},
      #    {:phase, :full_moon, ...}, {:sun, :set, ...}, ...]

  Its contract:

    * **Sorted** by `:at`, ascending. Guaranteed, not incidental.
    * **Uniform shape**: every entry is exactly `%{family: atom, type:
      atom, at: DateTime.t()}` — no optional keys, ever. The azimuth of a
      sunrise, the distance of a perigee, the declination of a standstill
      live in the structured field, which is made for them.
    * **Same time zone** as the rest of the struct.
    * Always present. There is no option to skip it, so `[]` means the day
      holds nothing, never "not computed".

  ### An absent event is not a non-event

  A missing `{:sun, :rise}` entry can mean polar day or polar night, and
  the flat list cannot tell you which — `sun.state` can
  (`:always_above` / `:always_below`), and so can `twilight.state` and
  `moon.state`. Reach for `:state` before rendering a dash: above the
  Arctic circle in June the honest label is "the Sun does not set", not
  "—".

  Being a projection, `:events` also inherits what the struct chooses to
  report: on the rare high-latitude day holding two moonrises, the struct
  keeps one, and so does the list.

  ### Families: topocentric and geocentric

  | | Family | Types |
  |---|---|---|
  | **Topocentric** — depends on the location | `:sun` | `:rise`, `:transit`, `:set` |
  | | `:twilight` | `:dawn`, `:dusk` |
  | | `:moon` | `:rise`, `:transit`, `:set` |
  | **Geocentric** — the same everywhere on Earth | `:phase` | `:new_moon`, `:first_quarter`, `:full_moon`, `:last_quarter` |
  | | `:apsis` | `:perigee`, `:apogee` |
  | | `:node` | `:ascending`, `:descending` |
  | | `:standstill` | `:northernmost`, `:southernmost` |

  The split is worth knowing when you compute several places at once: over
  a set of plots on the same farm, only the topocentric families change.
  The geocentric ones are the same instants for everyone — compute them
  once with `GreenCal.lunar_timeline/2` rather than once per plot.
  """

  defmodule Sun do
    @moduledoc "Solar part of a `GreenCal.Day`."

    defstruct [
      :state,
      :rise,
      :set,
      :transit,
      :day_length_minutes,
      :rise_azimuth,
      :set_azimuth
    ]

    @typedoc """
    `:day_length_minutes` is the time the Sun spends above the horizon
    within the civil day — always defined, `0.0` during polar night and
    the full window length (usually 1440) under the midnight sun, and it
    stays correct on days where the Sun rises before midnight or sets
    after it.
    """
    @type t :: %__MODULE__{
            state: :normal | :always_above | :always_below,
            rise: DateTime.t() | nil,
            set: DateTime.t() | nil,
            transit: DateTime.t() | nil,
            day_length_minutes: float(),
            rise_azimuth: float() | nil,
            set_azimuth: float() | nil
          }
  end

  defmodule Twilight do
    @moduledoc "Twilight part of a `GreenCal.Day`."

    defstruct [:kind, :state, :dawn, :dusk]

    @type t :: %__MODULE__{
            kind: :civil | :nautical | :astronomical | float(),
            state: :normal | :always_above | :always_below,
            dawn: DateTime.t() | nil,
            dusk: DateTime.t() | nil
          }
  end

  defmodule Moon do
    @moduledoc """
    Lunar part of a `GreenCal.Day`.

    Four fields carry a geocentric event instant when the day holds one,
    and `nil` otherwise: `:phase_change`, `:apsis`, `:node` and
    `:standstill`. They are the canonical home of those instants — the
    matching `GreenCal.Day` `:events` entries are a view of them, and
    `GreenCal.lunar_events/2` is the same computation over a whole range.
    All three come from the same finders in `GreenCal.Astro`, so they
    cannot report different times.

    They are always computed, so `nil` states a fact about the sky — this
    day holds no such event — and never a fact about how the day was
    built.

    At most one of each per day: the shortest of these cycles is 7.4 days
    (successive principal phases), the longest 13.8 (apsides).

    Note `:phase` and `:phase_change` answer different questions. `:phase`
    names the day — the eight-sector name at `sampled_at`, so a day reads
    `:full_moon` for the whole 24 h around the exact instant.
    `:phase_change` is the instant the Moon crosses into a new principal
    phase, present only on the day it falls.

        day.moon.phase         #=> :full_moon
        day.moon.phase_change  #=> %{type: :full_moon, at: ~U[...], eclipse: :none}
    """

    defstruct [
      :state,
      :rise,
      :set,
      :transit,
      :phase,
      :elongation,
      :illuminated_fraction,
      :distance_km,
      :declination,
      :ecliptic_latitude,
      :phase_change,
      :apsis,
      :node,
      :standstill,
      :trend,
      :illumination_trend,
      :distance_trend
    ]

    @typedoc """
    The three trend fields are the three **independent** lunar cycles:
    `:trend` follows the declination (ascending/descending — the cycle
    biodynamic sowing calendars use), `:illumination_trend` the phase
    (waxing/waning), `:distance_trend` the orbit (approaching/receding).
    """
    @type t :: %__MODULE__{
            state: :normal | :always_above | :always_below,
            rise: DateTime.t() | nil,
            set: DateTime.t() | nil,
            transit: DateTime.t() | nil,
            phase:
              :new_moon
              | :waxing_crescent
              | :first_quarter
              | :waxing_gibbous
              | :full_moon
              | :waning_gibbous
              | :last_quarter
              | :waning_crescent,
            elongation: float(),
            illuminated_fraction: float(),
            distance_km: float(),
            declination: float(),
            ecliptic_latitude: float(),
            phase_change:
              %{
                type: :new_moon | :first_quarter | :full_moon | :last_quarter,
                at: DateTime.t(),
                eclipse: :none | :possible | :likely
              }
              | nil,
            apsis: %{type: :perigee | :apogee, at: DateTime.t(), distance_km: float()} | nil,
            node: %{type: :ascending | :descending, at: DateTime.t()} | nil,
            standstill:
              %{
                type: :northernmost | :southernmost,
                at: DateTime.t(),
                declination: float()
              }
              | nil,
            trend: :ascending | :descending,
            illumination_trend: :waxing | :waning,
            distance_trend: :approaching | :receding
          }
  end

  @typedoc """
  One entry of `GreenCal.Day` `:events` — see the module doc for the
  families and their types, and for why the shape carries nothing else.
  """
  @type event :: %{family: atom(), type: atom(), at: DateTime.t()}

  defstruct [
    :date,
    :location,
    :sampled_at,
    :sun,
    :twilight,
    :moon,
    :constellation,
    :element,
    :organ,
    :events
  ]

  @type t :: %__MODULE__{
          date: Date.t(),
          location: GreenCal.location(),
          sampled_at: DateTime.t(),
          sun: Sun.t(),
          twilight: Twilight.t(),
          moon: Moon.t(),
          constellation: String.t(),
          element: :fire | :earth | :air | :water,
          organ: :fruit | :root | :flower | :leaf,
          events: [event()]
        }
end
