defmodule ClusterDroplet.MixProject do
  use Mix.Project

  @url "https://github.com/jsonmaur/libcluster-droplet"

  def project do
    [
      app: :libcluster_droplet,
      version: "1.1.2",
      elixir: "~> 1.13",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      source_url: @url,
      homepage_url: "#{@url}#readme",
      description: "A libcluster strategy for Digital Ocean Droplets",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => @url}
      ],
      docs: [
        main: "readme",
        extras: ["README.md"],
        authors: ["Jason Maurer"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:castore, "~> 0.1 or ~> 1.0"},
      {:ex_doc, "~> 0.27", only: :dev, runtime: false},
      {:exvcr, "~> 0.11", only: :test, runtime: false},
      {:libcluster, "~> 3.0"}
    ]
  end

  defp aliases do
    [
      test: [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "test"
      ]
    ]
  end
end
