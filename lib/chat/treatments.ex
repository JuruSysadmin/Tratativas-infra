defmodule Chat.Treatments do
  @moduledoc "Contexto de criação, ciclo de vida e auditoria de tratativas."

  import Ecto.Query

  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments.{AuditEvent, Treatment}

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

  defp authorized_treatment(treatment_id, user_id) do
    from(treatment in Treatment,
      join: membership in "room_members",
      on: membership.room_id == treatment.room_id,
      where: treatment.id == type(^treatment_id, :binary_id),
      where: membership.user_id == type(^user_id, :binary_id)
    )
    |> Repo.one()
  end

  defp normalize_transaction_result({:ok, {:ok, result}}), do: {:ok, result}
  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, reason}), do: {:error, reason}
end
