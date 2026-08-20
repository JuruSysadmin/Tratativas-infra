defmodule ChatWeb.NotificationSoundHookTest do
  use ExUnit.Case, async: true

  test "plays notifications while the chat tab is visible" do
    script_path = Path.expand("../../assets/notification_sound_hook_test.mjs", __DIR__)

    assert {"notification sound hook: ok\n", 0} =
             System.cmd("node", [script_path], stderr_to_stdout: true)
  end
end
