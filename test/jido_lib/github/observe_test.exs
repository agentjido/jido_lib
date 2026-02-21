defmodule Jido.Lib.Github.ObserveTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Observe

  @doc false
  def handle_telemetry(received_event, measurements, metadata, %{pid: pid}) do
    send(pid, {:telemetry_event, received_event, measurements, metadata})
  end

  test "emit/3 uses canonical namespace and required metadata keys" do
    event = Observe.coding_agent(:summary)
    handler_id = "jido-lib-observe-test-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_telemetry/4,
        %{pid: test_pid}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    Observe.emit(event, %{duration_ms: 123}, %{run_id: "run-1", provider: :claude})

    assert_receive {:telemetry_event, ^event, %{duration_ms: 123}, metadata}
    assert metadata.run_id == "run-1"
    assert metadata.provider == :claude
    assert Map.has_key?(metadata, :request_id)
    assert Map.has_key?(metadata, :owner)
    assert Map.has_key?(metadata, :repo)
    assert Map.has_key?(metadata, :issue_number)
    assert Map.has_key?(metadata, :session_id)
  end

  test "sanitize_sensitive/1 redacts token/key fields recursively" do
    payload = %{
      token: "abc",
      nested: %{
        "api_key" => "xyz",
        keep: "ok",
        list: [%{"client_secret" => "s1"}, %{visible: "yes"}]
      }
    }

    sanitized = Observe.sanitize_sensitive(payload)

    assert sanitized.token == "[REDACTED]"
    assert sanitized.nested["api_key"] == "[REDACTED]"
    assert sanitized.nested.keep == "ok"
    assert Enum.at(sanitized.nested.list, 0)["client_secret"] == "[REDACTED]"
    assert Enum.at(sanitized.nested.list, 1).visible == "yes"
  end
end
