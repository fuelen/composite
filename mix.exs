defmodule Composite.MixProject do
  use Mix.Project

  @version "0.2.1"
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
      description: "A library that allows writing composable queries",
      licenses: ["Apache 2"],
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
      deps: [ecto: "https://hexdocs.pm/ecto/"],
      source_url: "https://github.com/fuelen/composite",
      source_ref: "v#{@version}"
    ]
  end
end
