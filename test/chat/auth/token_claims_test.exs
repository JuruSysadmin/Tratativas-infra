defmodule Chat.Auth.TokenClaimsTest do
  use ExUnit.Case, async: false

  alias Chat.Accounts
  alias Chat.Auth.{JwksStrategy, Token}

  setup do
    previous = Application.get_env(:chat, :auth)

    Application.put_env(:chat, :auth,
      server_url: "https://auth.example.com",
      jwks_uri: "https://auth.example.com/.well-known/jwks.json",
      issuer: "auth.example.com",
      audience: "chat"
    )

    on_exit(fn -> Application.put_env(:chat, :auth, previous) end)
  end

  test "JWKS strategy accepts only RS256" do
    assert JwksStrategy.init_opts([])[:explicit_alg] == "RS256"
  end

  test "registers JokenJwks as the verification hook" do
    assert {JokenJwks, [strategy: JwksStrategy]} in Token.__hooks__()
    refute {JwksStrategy, []} in Token.__hooks__()
  end

  test "does not expose a local HMAC token fallback" do
    refute function_exported?(Token, :generate, 1)
    refute function_exported?(Token, :verify_hmac, 1)
    refute function_exported?(Token, :get_user_id, 1)

    login_live = File.read!(Path.expand("../../../lib/chat_web/live/login_live.ex", __DIR__))
    refute login_live =~ "Token.generate"
    refute login_live =~ "authenticate_by_username"
    refute login_live =~ "?token="
    refute function_exported?(Accounts, :create_user, 1)
    refute function_exported?(Accounts, :authenticate_user, 2)
    refute function_exported?(Accounts, :authenticate_by_username, 2)
  end

  test "accepts complete, unexpired claims" do
    claims = %{
      "sub" => "alice",
      "exp" => System.system_time(:second) + 60,
      "iss" => "auth.example.com",
      "aud" => "chat"
    }

    assert {:ok, ^claims} = Token.validate_claims(claims)
  end

  test "rejects missing or expired required claims" do
    assert {:error, :missing_subject} = Token.validate_claims(%{})

    assert {:error, :token_expired} =
             Token.validate_claims(%{
               "sub" => "alice",
               "exp" => System.system_time(:second) - 1,
               "iss" => "auth.example.com",
               "aud" => "chat"
             })
  end

  test "production requires JWKS, issuer and audience configuration" do
    runtime = File.read!(Path.expand("../../../config/runtime.exs", __DIR__))

    assert runtime =~ "JWKS_URI is missing"
    assert runtime =~ "JWT_ISSUER is missing"
    assert runtime =~ "JWT_AUDIENCE is missing"
  end
end
