defmodule PaperTiger.BootstrapTest do
  use ExUnit.Case, async: false

  alias PaperTiger.Bootstrap

  setup do
    original_repo = Application.fetch_env(:paper_tiger, :repo)
    Application.delete_env(:paper_tiger, :repo)
    PaperTiger.flush()

    on_exit(fn ->
      case original_repo do
        {:ok, repo} -> Application.put_env(:paper_tiger, :repo, repo)
        :error -> Application.delete_env(:paper_tiger, :repo)
      end

      PaperTiger.flush()
    end)

    :ok
  end

  test "bootstrap completes when no repo is configured" do
    assert {:noreply, %{}} = Bootstrap.handle_info(:bootstrap, %{})
  end
end
