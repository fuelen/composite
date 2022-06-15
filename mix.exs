defmodule Composite.MixProject do
  use Mix.Project

  @version "0.4.2"
  def project do
    [
      app: :composite,
      version: @version,
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:ecto]],
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def package do
    [
      description: "A utility for writing dynamic queries.",
      licenses: ["Apache-2.0"],
      links: %{
        GitHub: "https://github.com/fuelen/composite"
      }
    ]
  end

  defp deps do
    [
      {:ecto, ">= 1.0.0", optional: true},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "Composite",
      deps: [ecto: "https://hexdocs.pm/ecto/"],
      source_url: "https://github.com/fuelen/composite",
      source_ref: "v#{@version}"
    ]
  end
end
