defmodule GreenCal.Day do
  @moduledoc """
  One computed civil day — the return type of `GreenCal.day/3`.

  All `DateTime` fields are UTC unless a `:time_zone` option was given.
  A `nil` event time means the event does not occur within the civil day;
  check the matching `:state` field to know why.
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
    @moduledoc "Lunar part of a `GreenCal.Day`."

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
      :node,
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
            node: %{type: :ascending | :descending, at: DateTime.t()} | nil,
            trend: :ascending | :descending,
            illumination_trend: :waxing | :waning,
            distance_trend: :approaching | :receding
          }
  end

  defstruct [
    :date,
    :location,
    :sun,
    :twilight,
    :moon,
    :constellation,
    :element,
    :organ
  ]

  @type t :: %__MODULE__{
          date: Date.t(),
          location: GreenCal.location(),
          sun: Sun.t(),
          twilight: Twilight.t(),
          moon: Moon.t(),
          constellation: String.t(),
          element: :fire | :earth | :air | :water,
          organ: :fruit | :root | :flower | :leaf
        }
end
