defmodule GreenCal.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/nseaSeb/green_cal"

  def project do
    [
      app: :green_cal,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Sun and moon ephemerides for agricultural calendars: rise/set, twilights, " <>
          "lunar phases, node crossings and the declination cycle biodynamic sowing " <>
          "calendars are built on. Meeus' algorithms, pure Elixir, zero dependencies.",
      package: package(),
      docs: docs(),
      name: "GreenCal",
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "GreenCal",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "livebooks/green_cal.livemd"],
      groups_for_modules: [
        "High-level API": [GreenCal],
        Astronomy: [
          GreenCal.Astro,
          GreenCal.Astro.Sun,
          GreenCal.Astro.Moon,
          GreenCal.Astro.RiseSet,
          GreenCal.Astro.Time
        ]
      ]
    ]
  end
end
