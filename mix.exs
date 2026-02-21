defmodule Jido.Lib.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/jido_lib"

  def project do
    [
      app: :jido_lib,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      # Documentation
      name: "Jido Lib",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "docs/github_issue_triage_workflow.md",
          "docs/github_pr_bot_workflow.md"
        ]
      ],
      # Hex
      package: [
        name: :jido_lib,
        licenses: ["Apache-2.0"],
        maintainers: ["Agent Jido Community"],
        links: %{"GitHub" => @source_url}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Jido ecosystem
      {:jido, "~> 2.0.0-rc.5"},
      {:jido_runic, github: "agentjido/jido_runic", branch: "main"},
      {:jido_action, github: "agentjido/jido_action", branch: "main", override: true},
      {:libgraph, github: "zblanco/libgraph", branch: "zw/multigraph-indexes", override: true},
      {:jido_shell, github: "agentjido/jido_shell", branch: "main", override: true},
      {:jido_harness, github: "agentjido/jido_harness", branch: "main", override: true},
      {:jido_claude, github: "agentjido/jido_claude", branch: "main"},
      {:jido_amp, github: "agentjido/jido_amp", branch: "main"},
      {:jido_codex, github: "agentjido/jido_codex", branch: "main"},
      {:jido_gemini, github: "agentjido/jido_gemini", branch: "main"},
      {:jido_vfs, github: "agentjido/jido_vfs", branch: "main", override: true},
      {:sprites, git: "https://github.com/mikehostetler/sprites-ex.git"},

      # Schemas & validation
      {:zoi, "~> 0.17"},

      # Error handling
      {:splode, "~> 0.2"},

      # JSON
      {:jason, "~> 1.4"},

      # Dev & test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:doctor, "~> 0.21", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      quality: ["format", "credo --strict", "dialyzer", "doctor --raise"],
      setup: ["deps.get", "deps.compile"]
    ]
  end
end
