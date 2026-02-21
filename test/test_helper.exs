ExUnit.start()

Application.put_env(:jido_harness, :providers, %{
  claude: Jido.Claude.Adapter,
  amp: Jido.Amp.Adapter,
  codex: Jido.Codex.Adapter,
  gemini: Jido.Gemini.Adapter
})

Application.put_env(:jido_harness, :default_provider, :claude)
