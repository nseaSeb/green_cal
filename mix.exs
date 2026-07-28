defmodule GreenCal.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/sebastienportrait/green_cal"

  def project do
    [
      app: :green_cal,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Agricultural sun & moon calendar: rise/set, twilights, lunar phases and " <>
          "biodynamic cycles from Meeus' algorithms. Pure Elixir, zero dependencies.",
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
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "GreenCal",
      source_ref: "v#{@version}",
      extras: ["README.md", "livebooks/green_cal.livemd"],
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
