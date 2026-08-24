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
    "treatment.transfer",
    "treatment.preview"
  ]

  @role_permissions %{
    "commercial" => ["treatment.confirm_resolution", "treatment.reopen"],
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

  @doc "Separates room membership reading access from operational access."
  def authorize_room_action(%User{}, _assigned_agent_id, :read, member?) do
    if member?, do: :ok, else: {:error, :forbidden}
  end

  def authorize_room_action(%User{} = user, assigned_agent_id, action, member?)
      when action in [:write, :lifecycle] do
    cond do
      not member? -> {:error, :forbidden}
      user.role == "commercial" -> :ok
      user.role == "logistics_agent" and user.id == assigned_agent_id -> :ok
      user.role == "logistics_agent" -> {:error, :not_assigned_agent}
      true -> {:error, :forbidden}
    end
  end

  def authorize_room_action(_user, _assigned_agent_id, _action, _member?),
    do: {:error, :forbidden}

  def authorize_current_operator(%User{} = user, assigned_agent_id) do
    cond do
      user.role == "commercial" -> :ok
      user.role == "logistics_agent" and user.id == assigned_agent_id -> :ok
      user.role == "logistics_agent" -> {:error, :not_assigned_agent}
      true -> {:error, :forbidden}
    end
  end

  def authorize_current_operator(_user, _assigned_agent_id), do: {:error, :forbidden}

  @doc "Returns whether a user can claim an unassigned open Treatment."
  def eligible_for_assignment?(%User{role: "logistics_agent"}, "open", nil), do: true
  def eligible_for_assignment?(_user, _status, _assigned_agent_id), do: false
end
