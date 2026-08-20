defmodule Chat.AuthTokenStub do
  @moduledoc false

  def validate_jwks_token("valid-token") do
    {:ok, %{"sub" => "alice", "exp" => System.system_time(:second) + 60}}
  end

  def validate_jwks_token(_token), do: {:error, :invalid_token}
end
