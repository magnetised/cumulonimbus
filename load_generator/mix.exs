defmodule LoadGenerator.MixProject do
  use Mix.Project

  def project do
    [
      app: :load_generator,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {LoadGenerator.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:postgrex, ">= 0.0.0"},
      {:nimble_options, "~> 1.1"},
      {:plug, "~>1.16"},
      {:bandit, "~>1.6"},
      {:postgresql_uri, "~> 0.1.0"},
      {:req, "~> 0.5"},
      {:uuid, "~> 1.1"},
      {:electric_client,
       github: "electric-sql/electric",
       branch: "2606-error-shape-storage-cleanup",
       subdir: "packages/elixir-client",
       depth: 1}
    ]
  end
end
