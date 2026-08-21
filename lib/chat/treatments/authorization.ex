defmodule Chat.Treatments.Authorization do
  @moduledoc """
  Autoriza ações de Tratativas com base no papel operacional do usuário.

  Este módulo é a única fonte da matriz de permissões do domínio. Entradas
  web, Channels e contexts devem consultar `authorize/2` em vez de duplicar
  regras por papel.
  """

  alias Chat.Accounts.User

  @permissions [
    "treatment.assign",
    "treatment.resolve",
    "treatment.reopen",
    "treatment.unassign",
    "treatment.transfer"
  ]

  @role_permissions %{
    "commercial" => ["treatment.reopen"],
    "logistics_agent" => @permissions
  }

  @doc "Retorna as permissões de Tratativas para um papel conhecido."
  def permissions(role) when is_binary(role), do: Map.get(@role_permissions, role, [])
  def permissions(_role), do: []

  @doc "Verifica se o usuário pode executar uma permissão de Tratativa."
  def allowed?(%User{role: role}, permission) when is_binary(permission) do
    permission in permissions(role)
  end

  def allowed?(_user, _permission), do: false

  @doc "Autoriza uma ação ou retorna um erro de domínio estável."
  def authorize(user, permission) do
    if allowed?(user, permission), do: :ok, else: {:error, :forbidden}
  end
end
