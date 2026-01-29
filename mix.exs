defmodule CTF.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :ctf,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "BEAM compact term format encoder/decoder",
      package: package(),

      # Docs
      name: "CTF",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:stream_data, "~> 1.0", only: [:test, :dev]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/QuinnWilton/ctf"}
    ]
  end

  defp docs do
    [
      main: "CTF",
      extras: ["README.md"]
    ]
  end
end
