defmodule Chat.MixProject do
  @moduledoc "Mix project definition for the Chat application."

  use Mix.Project

  def project do
    [
      app: :chat,
      version: "0.2.1",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      releases: [
        chat: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent, sasl: :permanent],
          steps: [:assemble, :tar]
        ]
      ]
    ]
  end

  def application do
    [
      mod: {Chat.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:tidewave, "~> 0.8", only: [:dev]},
      {:dotenvy, "~> 1.1", only: :dev},
      {:phoenix, "~> 1.8.8"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:oban, "~> 2.23"},
      {:ex_aws, "~> 2.7"},
      {:ex_aws_s3, "~> 2.5"},
      {:live_debugger, "~> 1.0.0", only: :dev},
      {:postgrex, "~> 0.22.4"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:phoenix_html, "~> 4.1"},
      {:lazy_html, "~> 0.1", only: :test},
      {:phoenix_live_reload, "~> 1.4", only: :dev},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:hackney, "~> 4.7", override: true},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.12"},
      {:joken, "~> 2.6"},
      {:joken_jwks, "~> 1.6"},
      {:tzdata, "~> 1.1"},
      {:ok, "~> 2.3"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:test]}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build", "ecto.setup"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["esbuild default"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "test"
      ]
    ]
  end
end
