defmodule ClusterDroplet.MixProject do
  use Mix.Project

  def project do
    [
      app: :libcluster_droplet,
      version: "1.0.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:libcluster, "~> 3.0"}
    ]
  end
end
