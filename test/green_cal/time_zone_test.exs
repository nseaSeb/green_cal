defmodule GreenCal.TestTimeZoneDatabase do
  @moduledoc false
  # A two-zone time zone database, so the local-midnight and local-noon
  # handling can be tested without adding a dependency on tzdata.
  #
  #   "Test/Paris"    UTC+1, UTC+2 in summer, switching at 02:00 local —
  #                   the ordinary European shape.
  #   "Test/Midnight" the same offsets, switching at 00:00 local — the
  #                   Cuba/Chile shape, where the civil day itself starts
  #                   inside a DST gap in spring and inside an ambiguous
  #                   hour in autumn.

  @behaviour Calendar.TimeZoneDatabase

  # {instant summer time starts, instant it ends}, both in UTC
  @zones %{
    "Test/Paris" => {~N[2026-03-29 01:00:00], ~N[2026-10-25 01:00:00]},
    "Test/Midnight" => {~N[2026-03-28 23:00:00], ~N[2026-10-24 23:00:00]}
  }

  @winter %{utc_offset: 3600, std_offset: 0, zone_abbr: "TST"}
  @summer %{utc_offset: 3600, std_offset: 3600, zone_abbr: "TSTS"}

  @impl true
  def time_zone_period_from_utc_iso_days(iso_days, zone) do
    with {:ok, {starts, ends}} <- Map.fetch(@zones, zone) do
      utc = naive(iso_days)
      summer? = not before?(utc, starts) and before?(utc, ends)
      {:ok, if(summer?, do: @summer, else: @winter)}
    else
      :error -> {:error, :time_zone_not_found}
    end
  end

  @impl true
  def time_zone_periods_from_wall_datetime(wall, zone) do
    with {:ok, {starts, ends}} <- Map.fetch(@zones, zone) do
      # On the wall clock the gap opens where winter time would have
      # reached the transition, and the ambiguous hour where summer time
      # does — one hour later in both cases.
      gap_from = NaiveDateTime.add(starts, 3600)
      gap_to = NaiveDateTime.add(starts, 7200)
      ambiguous_from = NaiveDateTime.add(ends, 3600)
      ambiguous_to = NaiveDateTime.add(ends, 7200)

      cond do
        before?(wall, gap_from) -> {:ok, @winter}
        before?(wall, gap_to) -> {:gap, {@winter, gap_from}, {@summer, gap_to}}
        before?(wall, ambiguous_from) -> {:ok, @summer}
        before?(wall, ambiguous_to) -> {:ambiguous, @summer, @winter}
        true -> {:ok, @winter}
      end
    else
      :error -> {:error, :time_zone_not_found}
    end
  end

  defp naive(iso_days) do
    {y, m, d, h, min, s, _} = Calendar.ISO.naive_datetime_from_iso_days(iso_days)
    {:ok, naive} = NaiveDateTime.new(y, m, d, h, min, s)
    naive
  end

  defp before?(a, b), do: NaiveDateTime.compare(a, b) == :lt
end

defmodule GreenCal.TimeZoneTest do
  # Not async: it swaps the global time zone database. ExUnit runs sync
  # modules after every async one, so the tests asserting the UTC-only
  # error message elsewhere are already done by the time this runs.
  use ExUnit.Case, async: false

  @paris {48.8566, 2.3522}
  @august Date.range(~D[2026-08-01], ~D[2026-08-31])

  setup do
    previous = Calendar.get_time_zone_database()
    Calendar.put_time_zone_database(GreenCal.TestTimeZoneDatabase)
    on_exit(fn -> Calendar.put_time_zone_database(previous) end)
  end

  describe "a local civil day" do
    test "every instant comes back in the requested zone" do
      day = GreenCal.day(@paris, ~D[2026-08-12], time_zone: "Test/Paris")

      instants =
        [day.sampled_at, day.sun.rise, day.sun.set, day.twilight.dawn, day.moon.rise] ++
          Enum.map(day.events, & &1.at)

      for instant <- instants, instant != nil do
        assert instant.time_zone == "Test/Paris"
      end
    end

    test "geocentric events are stamped in the zone too, not left in UTC" do
      # The new moon of 2026-08-12 is at 17:36:40 UTC, i.e. 19:36:40 local
      day = GreenCal.day(@paris, ~D[2026-08-12], time_zone: "Test/Paris")

      assert day.moon.phase_instant.type == :new_moon
      assert day.moon.phase_instant.at.time_zone == "Test/Paris"
      assert DateTime.to_time(day.moon.phase_instant.at) == ~T[19:36:40]

      phase = Enum.find(day.events, &(&1.family == :phase))
      assert phase.at == day.moon.phase_instant.at
    end

    test "the day runs local midnight to local midnight, so sampled_at is local noon" do
      day = GreenCal.day(@paris, ~D[2026-08-12], time_zone: "Test/Paris")

      assert DateTime.to_time(day.sampled_at) == ~T[12:00:00]
      assert DateTime.to_date(day.sampled_at) == ~D[2026-08-12]
    end

    test "the events list stays sorted once shifted" do
      for date <- @august do
        times = GreenCal.day(@paris, date, time_zone: "Test/Paris").events |> Enum.map(& &1.at)
        assert times == Enum.sort(times, DateTime)
      end
    end

    test "calendar/3 still equals day/3 date by date" do
      assert GreenCal.calendar(@paris, @august, time_zone: "Test/Paris") ==
               Enum.map(@august, &GreenCal.day(@paris, &1, time_zone: "Test/Paris"))
    end

    test "parallel: true changes nothing in a zone either" do
      assert GreenCal.calendar(@paris, @august, time_zone: "Test/Paris", parallel: true) ==
               GreenCal.calendar(@paris, @august, time_zone: "Test/Paris")
    end

    test "lunar_timeline/2 follows the zone and stays chronological" do
      timeline = GreenCal.lunar_timeline(@august, time_zone: "Test/Paris")

      assert timeline != []
      assert Enum.map(timeline, & &1.at) == Enum.sort(Enum.map(timeline, & &1.at), DateTime)
      assert Enum.all?(timeline, &(&1.at.time_zone == "Test/Paris"))
    end
  end

  describe "DST days" do
    test "the spring day is 23 hours long, the autumn day 25" do
      spring = GreenCal.day(@paris, ~D[2026-03-29], time_zone: "Test/Paris")
      autumn = GreenCal.day(@paris, ~D[2026-10-25], time_zone: "Test/Paris")

      # sampled_at is the middle of the window, so it drifts off 12:00 by
      # half the hour gained or lost.
      assert DateTime.to_time(spring.sampled_at) == ~T[12:30:00]
      assert DateTime.to_time(autumn.sampled_at) == ~T[11:30:00]
    end

    test "a midnight transition does not lose or duplicate the civil day" do
      # "Test/Midnight" switches at 00:00 local: the spring civil day
      # starts inside a gap, the autumn one inside an ambiguous hour.
      spring = GreenCal.day(@paris, ~D[2026-03-29], time_zone: "Test/Midnight")
      autumn = GreenCal.day(@paris, ~D[2026-10-25], time_zone: "Test/Midnight")

      for day <- [spring, autumn] do
        assert %DateTime{} = day.sun.rise
        assert %DateTime{} = day.sun.set
        assert day.events != []
        times = Enum.map(day.events, & &1.at)
        assert times == Enum.sort(times, DateTime)
      end
    end

    test "no day of the year is skipped or served twice across a transition" do
      range = Date.range(~D[2026-03-27], ~D[2026-03-31])
      days = GreenCal.calendar(@paris, range, time_zone: "Test/Midnight")

      assert Enum.map(days, & &1.date) == Enum.to_list(range)
    end
  end

  describe "an unknown zone" do
    test "reports the zone rather than blaming the database" do
      assert_raise ArgumentError, ~r/cannot resolve time zone/, fn ->
        GreenCal.day(@paris, ~D[2026-08-12], time_zone: "Nowhere/Nothing")
      end
    end
  end
end
