defmodule Composite.MixProject do
  use Mix.Project

  def project do
    [
      app: :composite,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:ecto]],
      package: package()
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
end
