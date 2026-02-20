defmodule Jido.Lib.Github.Actions do
  @moduledoc false

  alias Jido.Lib.Github.Actions
  alias Jido.Runic.ActionNode

  @retry_policy %{
    Actions.ValidateHostEnv => 0,
    Actions.ProvisionSprite => 0,
    Actions.PrepareGithubAuth => 1,
    Actions.FetchIssue => 1,
    Actions.CloneRepo => 0,
    Actions.RunSetupCommands => 0,
    Actions.ValidateRuntime => 1,
    Actions.PrepareProviderRuntime => 1,
    Actions.RunCodingAgent => 0,
    Actions.EnsureBranch => 0,
    Actions.EnsureCommit => 0,
    Actions.RunCheckCommands => 0,
    Actions.PushBranch => 0,
    Actions.CreatePullRequest => 1,
    Actions.PostIssueComment => 0,
    Actions.TeardownSprite => 0
  }

  @spec node(module(), keyword()) :: ActionNode.t()
  def node(action_mod, opts \\ []) when is_atom(action_mod) and is_list(opts) do
    retries = Map.get(@retry_policy, action_mod, 0)
    ActionNode.new(action_mod, %{}, Keyword.merge([max_retries: retries], opts))
  end

  @spec shared_flow_actions() :: [module()]
  def shared_flow_actions do
    [
      Actions.ValidateHostEnv,
      Actions.ProvisionSprite,
      Actions.PrepareGithubAuth,
      Actions.FetchIssue,
      Actions.CloneRepo,
      Actions.RunSetupCommands,
      Actions.ValidateRuntime,
      Actions.PrepareProviderRuntime
    ]
  end

  @spec triage_tail_actions() :: [module()]
  def triage_tail_actions do
    [
      Actions.RunCodingAgent,
      Actions.PostIssueComment,
      Actions.TeardownSprite
    ]
  end

  @spec pr_tail_actions() :: [module()]
  def pr_tail_actions do
    [
      Actions.EnsureBranch,
      Actions.RunCodingAgent,
      Actions.EnsureCommit,
      Actions.RunCheckCommands,
      Actions.PushBranch,
      Actions.CreatePullRequest,
      Actions.PostIssueComment,
      Actions.TeardownSprite
    ]
  end
end
