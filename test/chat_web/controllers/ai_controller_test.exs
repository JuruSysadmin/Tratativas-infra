defmodule ChatWeb.AIControllerTest do
  use ChatWeb.ConnCase, async: false

  alias Chat.Auth.Identity

  setup do
    {:ok, user} = Identity.sync_user(%{"sub" => "ai-controller-user"}, %{})

    previous_module = Application.get_env(:chat, :authenticator_module)
    previous_pid = Application.get_env(:chat, :authenticator_spy_pid)
    previous_user = Application.get_env(:chat, :authenticator_spy_user)
    previous_ollama = Application.get_env(:chat, :ollama)

    Application.put_env(:chat, :authenticator_module, Chat.AuthenticatorSpy)
    Application.put_env(:chat, :authenticator_spy_pid, self())
    Application.put_env(:chat, :authenticator_spy_user, user)

    Application.put_env(:chat, :ollama,
      endpoint: "http://ollama.test/api/chat",
      model: "test-model",
      request_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn ->
      restore_env(:authenticator_module, previous_module)
      restore_env(:authenticator_spy_pid, previous_pid)
      restore_env(:authenticator_spy_user, previous_user)
      restore_env(:ollama, previous_ollama)
    end)

    :ok
  end

  test "returns an answer from the local LLM", %{conn: conn} do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{"message" => %{"content" => "A tratativa está em andamento."}})
      )
    end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> post("/api/ai/ask", %{prompt: "Qual é o status da tratativa?"})

    assert %{"answer" => "A tratativa está em andamento."} = json_response(conn, 200)
  end

  test "rejects a missing prompt", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> post("/api/ai/ask", %{})

    assert %{"error" => "invalid_prompt"} = json_response(conn, 400)
  end

  test "maps an Ollama failure to bad gateway", %{conn: conn} do
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 500, "failure") end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> post("/api/ai/ask", %{prompt: "Resuma a tratativa."})

    assert %{"error" => "llm_unavailable"} = json_response(conn, 502)
  end

  defp restore_env(key, nil), do: Application.delete_env(:chat, key)
  defp restore_env(key, value), do: Application.put_env(:chat, key, value)
end
