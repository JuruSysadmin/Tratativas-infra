defmodule ChatWeb.MarkReadHookTest do
  use ExUnit.Case, async: true

  test "acknowledges delivery after rendering a message from another user" do
    script_path = Path.expand("../../assets/mark_read_hook_test.mjs", __DIR__)

    assert {"mark read hook: ok\n", 0} =
             System.cmd("node", [script_path], stderr_to_stdout: true)
  end
end
