defmodule Chat.Realtime.Payloads do
  @moduledoc """
  Canonical public payloads shared by realtime snapshots, replies and broadcasts.

  These functions are transport projections. They contain persisted state only and
  make nullable fields explicit so clients never need to merge partial resources.
  """

  alias Chat.Repo
  alias Chat.Messages.Attachments
  alias Chat.Treatments.Treatment

  @doc "Returns the complete message projection used by every message event."
  def message(message, opts \\ []) do
    %{
      id: message.id,
      room_id: message.room_id,
      client_id: message.client_id,
      content: message.content,
      user: %{id: message.user.id, username: message.user.username},
      inserted_at: iso8601_timestamp(message.inserted_at),
      edited_at: iso8601_timestamp(message.edited_at),
      attachments: Enum.map(message.attachments, &attachment_payload(&1, opts))
    }
  end

  def iso8601_timestamp(nil), do: nil
  def iso8601_timestamp(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)

  def iso8601_timestamp(%NaiveDateTime{} = timestamp) do
    timestamp
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  @doc "Returns the tombstone projection used by message removal."
  def message_removed(room_id, message_id) do
    %{id: message_id, room_id: room_id}
  end

  @doc "Returns the complete Treatment projection for snapshots and transitions."
  def treatment(%Treatment{} = treatment) do
    treatment = Repo.preload(treatment, [:assigned_agent, :reason])

    %{
      id: treatment.id,
      treatment_id: treatment.id,
      room_id: treatment.room_id,
      order_id: treatment.order_id,
      protocol: protocol(treatment.protocol_number),
      status: treatment.status,
      assigned_agent_id: treatment.assigned_agent_id,
      assigned_agent_username: assigned_agent_username(treatment),
      assigned_agent_name: assigned_agent_username(treatment),
      assigned_at: treatment.assigned_at,
      resolved_by_id: treatment.resolved_by_id,
      resolved_at: treatment.resolved_at,
      closed_by_id: treatment.closed_by_id,
      closed_at: treatment.closed_at,
      sla_paused_seconds: treatment.sla_paused_seconds,
      inserted_at: treatment.inserted_at,
      can_assign: is_nil(treatment.assigned_agent_id) and treatment.status == "open",
      reason: reason_payload(treatment.reason)
    }
  end

  defp protocol(protocol_number),
    do: "TRAT-" <> String.pad_leading(Integer.to_string(protocol_number), 6, "0")

  defp assigned_agent_username(%{assigned_agent: %{username: username}}), do: username
  defp assigned_agent_username(_treatment), do: nil

  defp reason_payload(nil), do: nil
  defp reason_payload(%Ecto.Association.NotLoaded{}), do: nil

  defp reason_payload(reason) do
    %{code: reason.code, label: reason.label, priority: reason.priority}
  end

  defp attachment_payload(attachment, opts), do: Attachments.payload(attachment, opts)
end
