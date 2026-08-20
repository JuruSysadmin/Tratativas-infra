defmodule Chat.Storage.MessageAttachmentVerifierTest do
  use ExUnit.Case, async: false

  alias Chat.Storage.MessageAttachmentVerifier

  setup do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)

    Application.put_env(:chat, :message_attachment_storage,
      bucket: "test-bucket",
      region: "us-east-1",
      host: "127.0.0.1",
      scheme: "http",
      port: port,
      presign_ttl_seconds: 300
    )

    System.put_env("AWS_ACCESS_KEY_ID", "test-access-key")
    System.put_env("AWS_SECRET_ACCESS_KEY", "test-secret-key")
    System.put_env("AWS_SESSION_TOKEN", "test-session-token")
    Application.put_env(:ex_aws, :security_token, "test-session-token")

    on_exit(fn ->
      :gen_tcp.close(listener)
      Application.delete_env(:chat, :message_attachment_storage)
      Application.delete_env(:ex_aws, :security_token)
    end)

    %{listener: listener}
  end

  test "returns object metadata from a successful head request", %{listener: listener} do
    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        request = recv_all(socket)

        :gen_tcp.send(
          socket,
          "HTTP/1.1 200 OK\r\nContent-Type: application/pdf\r\nContent-Length: 128\r\n\r\n"
        )

        :gen_tcp.close(socket)
        request
      end)

    result = MessageAttachmentVerifier.head_object("abc/123.pdf")
    request = Task.await(task, 5000)

    assert {:ok, %{size: 128, content_type: "application/pdf"}} = result
    assert request =~ "HEAD /test-bucket/abc/123.pdf"
    assert request =~ "x-amz-security-token: test-session-token"
  end

  test "returns an error tuple when the object does not exist", %{listener: listener} do
    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        _request = recv_all(socket)

        :gen_tcp.send(
          socket,
          "HTTP/1.1 404 Not Found\r\nContent-Type: application/xml\r\nContent-Length: 0\r\n\r\n"
        )

        :gen_tcp.close(socket)
      end)

    result = MessageAttachmentVerifier.head_object("abc/missing.pdf")
    Task.await(task, 5000)

    assert {:error, _reason} = result
  end

  defp recv_all(socket) do
    receive_loop(socket, [])
  end

  defp receive_loop(socket, acc) do
    case :gen_tcp.recv(socket, 0, 2000) do
      {:ok, data} -> receive_loop(socket, [data | acc])
      {:error, :closed} -> acc |> Enum.reverse() |> IO.iodata_to_binary()
      {:error, _} -> acc |> Enum.reverse() |> IO.iodata_to_binary()
    end
  end
end
