defmodule Jido.Lib.Github.Actions.Common.MutationGuardTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.Common.MutationGuard

  test "requires explicit apply in safe_fix mode" do
    refute MutationGuard.mutation_allowed?(%{mode: :safe_fix, apply: false})
    assert MutationGuard.mutation_allowed?(%{mode: :safe_fix, apply: true})
  end

  test "publish_only mode requires publish flag" do
    refute MutationGuard.mutation_allowed?(%{apply: true, publish: false}, publish_only: true)
    assert MutationGuard.mutation_allowed?(%{apply: false, publish: true}, publish_only: true)
  end

  test "require helpers return typed errors" do
    assert {:error, :mutation_not_allowed} = MutationGuard.require_mutation_allowed(%{})
    assert {:error, :publish_not_allowed} = MutationGuard.require_publish_allowed(%{})
  end
end
