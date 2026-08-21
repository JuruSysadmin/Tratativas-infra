defmodule Chat.Treatments do
  @moduledoc "Contexto de criação, ciclo de vida e auditoria de tratativas."

  import Ecto.Query

  alias Chat.Accounts.User
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments.{AuditEvent, Authorization, Treatment}

  @doc "Abre ou reabre a tratativa única associada ao pedido."
  def open_for_order(order_id, user_id) when is_integer(order_id) do
    Repo.transaction(fn ->
      case Rooms.open_order_room(order_id, user_id) do
        {:ok, room} -> open_or_reopen(room, order_id, user_id)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def open_for_order(_order_id, _user_id), do: {:error, :invalid_order_id}

  def close(%Treatment{} = treatment, user_id) do
    Rooms.with_member_room(user_id, treatment.room_id, fn _room ->
      Repo.transaction(fn ->
        treatment = Repo.get!(Treatment, treatment.id)

        {:ok, closed_treatment} =
          treatment
          |> Treatment.changeset(%{status: "closed"})
          |> Repo.update()

        {:ok, _event} = record_event(closed_treatment, user_id, "treatment_closed")
        closed_treatment
      end)
    end)
    |> normalize_transaction_result()
  end

  def assign_agent(%Treatment{id: treatment_id}, %User{} = user) do
    case assign_agent_result(treatment_id, user) do
      {:ok, treatment, _result} -> {:ok, treatment}
      error -> error
    end
  end

  def get_by_room_id(room_id) do
    Repo.get_by(Treatment, room_id: room_id)
  end

  def assign_agent_for_room(room_id, %User{} = user) do
    Rooms.with_member_room(user.id, room_id, fn _room -> assign_room_treatment(room_id, user) end)
    |> normalize_member_room_result()
  end

  def resolve(%Treatment{id: treatment_id}, %User{} = user) do
    case resolve_result(treatment_id, user) do
      {:ok, treatment, :resolved} -> {:ok, treatment}
      error -> error
    end
  end

  def resolve_for_room(room_id, %User{} = user) do
    Rooms.with_member_room(user.id, room_id, fn _room -> resolve_room_treatment(room_id, user) end)
    |> normalize_member_room_result()
  end

  def list_audit_events(treatment_id, user_id) do
    with {:ok, treatment_id} <- Ecto.UUID.cast(treatment_id),
         {:ok, user_id} <- Ecto.UUID.cast(user_id) do
      from(event in AuditEvent,
        join: treatment in assoc(event, :treatment),
        join: membership in "room_members",
        on:
          membership.room_id == treatment.room_id and
            membership.user_id == type(^user_id, :binary_id),
        where: event.treatment_id == type(^treatment_id, :binary_id),
        order_by: [desc: event.inserted_at],
        preload: [:actor]
      )
      |> Repo.all()
    else
      _invalid_id -> []
    end
  end

  def get_for_user(treatment_id, user_id) do
    with {:ok, treatment_id} <- Ecto.UUID.cast(treatment_id),
         {:ok, user_id} <- Ecto.UUID.cast(user_id),
         %Treatment{} = treatment <- authorized_treatment(treatment_id, user_id) do
      {:ok, Repo.preload(treatment, [:room, :opened_by])}
    else
      nil -> {:error, :not_found}
      _invalid_id -> {:error, :not_found}
    end
  end

  def protocol(%Treatment{protocol_number: protocol_number}) do
    "TRAT-" <> String.pad_leading(Integer.to_string(protocol_number), 6, "0")
  end

  defp open_or_reopen(room, order_id, user_id) do
    case Repo.get_by(Treatment, order_id: order_id) do
      nil -> create_treatment(room.id, order_id, user_id)
      %Treatment{status: "closed"} = treatment -> reopen_treatment(treatment, room.id, user_id)
      %Treatment{} = treatment -> %{treatment: Repo.preload(treatment, :room), room: room}
    end
  end

  defp create_treatment(room_id, order_id, user_id) do
    {:ok, treatment} =
      %Treatment{}
      |> Treatment.changeset(%{
        order_id: order_id,
        room_id: room_id,
        opened_by_id: user_id,
        status: "open"
      })
      |> Repo.insert()

    {:ok, _event} = record_event(treatment, user_id, "treatment_created")
    %{treatment: Repo.preload(treatment, :room), room: Repo.get!(Chat.Rooms.Room, room_id)}
  end

  defp reopen_treatment(treatment, room_id, user_id) do
    {:ok, treatment} =
      treatment
      |> Treatment.changeset(%{status: "open"})
      |> Repo.update()

    {:ok, _event} = record_event(treatment, user_id, "treatment_reopened")
    %{treatment: Repo.preload(treatment, :room), room: Repo.get!(Chat.Rooms.Room, room_id)}
  end

  defp record_event(treatment, actor_id, event_type, metadata \\ %{}) do
    %AuditEvent{}
    |> AuditEvent.changeset(%{
      actor_id: actor_id,
      event_type: event_type,
      metadata: metadata,
      treatment_id: treatment.id
    })
    |> Repo.insert()
  end

  defp assign_locked(treatment_id, user) do
    treatment =
      from(treatment in Treatment,
        where: treatment.id == ^treatment_id,
        lock: "FOR UPDATE"
      )
      |> Repo.one()

    assign_locked_state(treatment, user)
  end

  defp assign_locked_state(nil, _user), do: {:error, :not_found}

  defp assign_locked_state(%Treatment{assigned_agent_id: nil, status: "open"} = treatment, user) do
    case persist_assignment(treatment, user) do
      {:ok, assigned_treatment} -> {:ok, assigned_treatment, :assigned}
      error -> error
    end
  end

  defp assign_locked_state(%Treatment{assigned_agent_id: nil}, _user),
    do: {:error, :invalid_status}

  defp assign_locked_state(
         %Treatment{status: "in_progress", assigned_agent_id: assigned_agent_id} = treatment,
         %User{id: assigned_agent_id}
       ),
       do: {:ok, treatment, :idempotent}

  defp assign_locked_state(%Treatment{status: status}, _user)
       when status in ["resolved", "closed"],
       do: {:error, :invalid_status}

  defp assign_locked_state(%Treatment{assigned_agent_id: assigned_agent_id}, %User{
         id: assigned_agent_id
       }),
       do: {:error, :invalid_status}

  defp assign_locked_state(%Treatment{}, _user), do: {:error, :already_assigned}

  defp persist_assignment(treatment, user) do
    treatment
    |> Treatment.assignment_changeset(%{
      assigned_agent_id: user.id,
      assigned_at: DateTime.utc_now(),
      status: "in_progress"
    })
    |> Repo.update()
  end

  defp assign_agent_result(treatment_id, user) do
    with :ok <- Authorization.authorize(user, "treatment.assign") do
      Repo.transaction(fn -> assign_locked_and_audit(treatment_id, user) end)
      |> normalize_assignment_transaction_result()
    end
  end

  defp assign_room_treatment(room_id, user) do
    case get_by_room_id(room_id) do
      nil ->
        {:error, :not_found}

      %Treatment{id: treatment_id} ->
        with :ok <- Authorization.authorize(user, "treatment.assign") do
          assign_locked_and_audit(treatment_id, user)
        end
    end
  end

  defp resolve_room_treatment(room_id, user) do
    case get_by_room_id(room_id) do
      nil -> {:error, :not_found}
      %Treatment{id: treatment_id} -> resolve_result(treatment_id, user)
    end
  end

  defp resolve_result(treatment_id, user) do
    with :ok <- Authorization.authorize(user, "treatment.resolve") do
      Repo.transaction(fn -> resolve_locked(treatment_id, user) end)
      |> normalize_resolution_transaction_result()
    end
  end

  defp assign_locked_and_audit(treatment_id, user) do
    case assign_locked(treatment_id, user) do
      {:ok, treatment, :assigned} ->
        case record_event(treatment, user.id, "treatment_assigned") do
          {:ok, _event} -> {:ok, treatment, :assigned}
          {:error, reason} -> Repo.rollback(reason)
        end

      {:ok, treatment, :idempotent} ->
        {:ok, treatment, :idempotent}

      error ->
        error
    end
  end

  defp resolve_locked(treatment_id, user) do
    treatment =
      from(treatment in Treatment,
        where: treatment.id == ^treatment_id,
        lock: "FOR UPDATE"
      )
      |> Repo.one()

    case treatment do
      nil ->
        {:error, :not_found}

      %Treatment{status: "in_progress", assigned_agent_id: assigned_agent_id}
      when assigned_agent_id == user.id ->
        resolve_locked_and_audit(treatment, user)

      %Treatment{status: "in_progress"} ->
        {:error, :not_assigned_agent}

      %Treatment{} ->
        {:error, :invalid_status}
    end
  end

  defp resolve_locked_treatment(treatment, user) do
    treatment
    |> Treatment.resolution_changeset(user.id, DateTime.utc_now())
    |> Repo.update()
  end

  defp resolve_locked_and_audit(treatment, user) do
    case resolve_locked_treatment(treatment, user) do
      {:ok, resolved_treatment} ->
        case record_event(resolved_treatment, user.id, "treatment_resolved") do
          {:ok, _event} -> {:ok, resolved_treatment, :resolved}
          {:error, reason} -> Repo.rollback(reason)
        end

      error ->
        error
    end
  end

  defp authorized_treatment(treatment_id, user_id) do
    from(treatment in Treatment,
      join: membership in "room_members",
      on: membership.room_id == treatment.room_id,
      where: treatment.id == type(^treatment_id, :binary_id),
      where: membership.user_id == type(^user_id, :binary_id)
    )
    |> Repo.one()
  end

  defp normalize_transaction_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_transaction_result({:ok, {:ok, result}}), do: {:ok, result}
  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, reason}), do: {:error, reason}

  defp normalize_assignment_transaction_result({:ok, {:ok, treatment, result}}),
    do: {:ok, treatment, result}

  defp normalize_assignment_transaction_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_assignment_transaction_result({:error, reason}), do: {:error, reason}

  defp normalize_resolution_transaction_result({:ok, {:ok, treatment, result}}),
    do: {:ok, treatment, result}

  defp normalize_resolution_transaction_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_resolution_transaction_result({:error, reason}), do: {:error, reason}

  defp normalize_member_room_result({:ok, {:ok, treatment, result}}),
    do: {:ok, treatment, result}

  defp normalize_member_room_result({:ok, {:ok, result}}), do: {:ok, result}

  defp normalize_member_room_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_member_room_result({:error, reason}), do: {:error, reason}
end
