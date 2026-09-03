defmodule Chat.AI.OllamaTest do
  use ExUnit.Case, async: false

  alias Chat.AI.Ollama

  setup do
    Application.put_env(:chat, :ollama,
      endpoint: "http://ollama.test/api/chat",
      model: "test-model",
      request_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn -> Application.delete_env(:chat, :ollama) end)
    :ok
  end

  test "returns the assistant response" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/chat"

      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert %{"model" => "test-model", "stream" => false, "messages" => [%{"content" => "Oi"}]} =
               Jason.decode!(body)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{"message" => %{"content" => "Olá!"}}))
    end)

    assert {:ok, "Olá!"} = Ollama.chat("Oi")
  end
end
