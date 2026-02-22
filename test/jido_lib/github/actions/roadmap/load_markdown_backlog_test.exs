defmodule Jido.Lib.Github.Actions.Roadmap.LoadMarkdownBacklogTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.Roadmap.LoadMarkdownBacklog

  test "extracts roadmap items and dependencies from markdown stories" do
    repo_dir = Path.join(System.tmp_dir!(), "roadmap-md-#{System.unique_integer([:positive])}")
    stories_dir = Path.join(repo_dir, "specs/stories")
    :ok = File.mkdir_p(stories_dir)

    story_file = Path.join(stories_dir, "sample.md")

    :ok =
      File.write(
        story_file,
        """
        ### ST-CORE-001 Implement Bot Runtime
        #### Dependencies
        - ST-CORE-000
        #### Acceptance
        - done

        ### ST-CORE-002 Add Release Flow
        #### Dependencies
        - ST-CORE-001
        #### Acceptance
        - done
        """
      )

    params = %{repo_dir: repo_dir, stories_dirs: ["specs/stories"]}
    assert {:ok, result} = Jido.Exec.run(LoadMarkdownBacklog, params, %{})
    assert length(result.markdown_items) == 2

    [first | _] = result.markdown_items
    assert first.id == "ST-CORE-001"
    assert "ST-CORE-000" in first.dependencies
  end
end
