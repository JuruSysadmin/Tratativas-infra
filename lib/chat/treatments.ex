defmodule Chat.Treatments do
  @moduledoc "Contexto de criação, ciclo de vida e auditoria de tratativas."

  import Ecto.Query

  alias Chat.Accounts.User
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Rooms.{MembershipCache, RoomMember}
  alias Chat.Treatments.{AuditEvent, Authorization, Reason, Treatment}

  @doc "Opens the single treatment associated with an order without changing its lifecycle."
  def open_for_order(order_id, user_id) when is_integer(order_id) do
    Repo.transaction(fn ->
      case Repo.get_by(Treatment, order_id: order_id) do
        nil ->
          open_new_treatment(order_id, user_id)

        %Treatment{} = treatment ->
          open_existing_treatment(treatment, user_id)
      end
    end)
  end

  def open_for_order(_order_id, _user_id), do: {:error, :invalid_order_id}

  def open_structured_for_order(order_id, user_id, attrs)
      when is_integer(order_id) and is_map(attrs) do
    Repo.transaction(fn ->
      with {:ok, %Reason{id: reason_id}} <- active_reason(attrs),
           {:ok, description} <- initial_description(attrs),
           nil <- Repo.get_by(Treatment, order_id: order_id),
           {:ok, room} <- Rooms.open_order_room(order_id, user_id),
           {:ok, treatment} <-
             create_structured_treatment(room.id, order_id, user_id, reason_id, description) do
        %{treatment: Repo.preload(treatment, [:room, :reason]), room: room}
      else
        %Treatment{} -> Repo.rollback(:treatment_exists)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def open_structured_for_order(_order_id, _user_id, _attrs), do: {:error, :invalid_order_id}

  def intake_state(order_id) when is_integer(order_id) do
    case Repo.get_by(Treatment, order_id: order_id) do
      nil -> {:missing, list_active_reasons()}
      treatment -> {:existing, treatment}
    end
  end

  def intake_state(_order_id), do: {:error, :invalid_order_id}

  def close(%Treatment{} = treatment, user_id) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      %User{} = user ->
        close_for_user(treatment, user)
    end
  end

  defp close_for_user(treatment, user) do
    Rooms.with_member_room(user.id, treatment.room_id, fn _room ->
      close_persisted_treatment(treatment.id, user)
    end)
    |> normalize_transaction_result()
  end

  defp close_persisted_treatment(treatment_id, user) do
    persisted_treatment = Repo.get!(Treatment, treatment_id)

    case persisted_treatment.status do
      "closed" -> Repo.rollback(:invalid_status)
      _status -> close_active_treatment(persisted_treatment, user)
    end
  end

  defp close_active_treatment(treatment, user) do
    with :ok <- Authorization.authorize_current_operator(user, treatment.assigned_agent_id),
         {:ok, closed_treatment} <-
           treatment
           |> Treatment.changeset(%{status: "closed"})
           |> Repo.update(),
         {:ok, _event} <- record_event(closed_treatment, user.id, "treatment_closed") do
      closed_treatment
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def get_preview(treatment_id, %User{} = user) do
    with {:ok, _} <- Ecto.UUID.cast(treatment_id),
         :ok <- Authorization.authorize(user, "treatment.preview"),
         %Treatment{} = treatment <- Repo.get(Treatment, treatment_id) |> Repo.preload(:reason),
         true <- treatment.status == "open" and is_nil(treatment.assigned_agent_id) do
      customer_summary =
        case Chat.Orders.Mock.get(treatment.order_id) do
          %{customer_id: id, customer_name: name} ->
            %{"customer_id" => id, "customer_name" => name}

          _ ->
            nil
        end

      reason_map =
        if treatment.reason do
          %{"code" => treatment.reason.code, "label" => treatment.reason.label}
        else
          nil
        end

      preview = %{
        "treatment_id" => treatment.id,
        "protocol" => protocol(treatment),
        "order_id" => treatment.order_id,
        "reason" => reason_map,
        "initial_description" => treatment.initial_description,
        "inserted_at" => treatment.inserted_at,
        "status" => treatment.status,
        "customer_summary" => customer_summary
      }

      {:ok, preview}
    else
      :error -> {:error, :invalid_id}
      {:error, :forbidden} -> {:error, :forbidden}
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
    end
  end

  def assign_agent(%Treatment{id: treatment_id}, %User{} = user) do
    case assign_agent_result(treatment_id, user) do
      {:ok, treatment, _result} -> {:ok, treatment}
      error -> error
    end
  end

  def assign_agent_by_id(treatment_id, %User{} = user) do
    with {:ok, treatment_id} <- Ecto.UUID.cast(treatment_id),
         {:ok, treatment, result} <- assign_agent_result(treatment_id, user) do
      {:ok, Repo.preload(treatment, :assigned_agent), result}
    else
      :error -> {:error, :invalid_id}
      error -> error
    end
  end

  def unassign(%Treatment{id: treatment_id, room_id: room_id}, %User{} = user) do
    with :ok <- Authorization.authorize(user, "treatment.unassign") do
      Rooms.with_member_room(user.id, room_id, fn _room ->
        run_unassign_transaction(treatment_id, user)
      end)
      |> normalize_unassign_member_room_result()
    end
  end

  def unassign_for_room(room_id, %User{} = user) do
    with :ok <- Authorization.authorize(user, "treatment.unassign") do
      Rooms.with_member_room(user.id, room_id, fn _room ->
        unassign_room_treatment(room_id, user)
      end)
      |> normalize_unassign_member_room_result()
    end
  end

  def transfer_agent(
        %Treatment{id: treatment_id, room_id: room_id},
        %User{} = current_agent,
        %User{} = target_agent
      ) do
    with :ok <- Authorization.authorize(current_agent, "treatment.transfer") do
      result =
        Rooms.with_member_room(current_agent.id, room_id, fn _room ->
          run_transfer_transaction(treatment_id, current_agent, target_agent)
        end)
        |> normalize_transfer_member_room_result()

      cache_transfer_membership(result)
    end
  end

  def transfer_agent_for_room(room_id, %User{} = current_agent, target_agent_id) do
    with :ok <- Authorization.authorize(current_agent, "treatment.transfer") do
      result =
        Rooms.with_member_room(current_agent.id, room_id, fn _room ->
          transfer_room_treatment(room_id, current_agent, target_agent_id)
        end)
        |> normalize_transfer_member_room_result()

      cache_transfer_membership(result)
    end
  end

  def get_by_room_id(room_id) do
    Treatment
    |> Repo.get_by(room_id: room_id)
    |> case do
      nil -> nil
      treatment -> Repo.preload(treatment, :assigned_agent)
    end
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

  def confirm_resolution(%Treatment{id: treatment_id}, %User{} = user) do
    with :ok <- Authorization.authorize(user, "treatment.confirm_resolution") do
      Repo.transaction(fn -> confirm_resolution_locked(treatment_id, user) end)
      |> normalize_confirmation_transaction_result()
    end
  end

  def confirm_resolution_for_room(room_id, %User{} = user) do
    case get_by_room_id(room_id) do
      nil -> {:error, :not_found}
      %Treatment{} = treatment -> confirm_resolution(treatment, user)
    end
  end

  def reopen(%Treatment{id: treatment_id}, %User{} = user) do
    with :ok <- Authorization.authorize(user, "treatment.reopen") do
      Repo.transaction(fn -> reopen_locked(treatment_id, user) end)
      |> normalize_reopen_transaction_result()
    end
  end

  def reopen_for_room(room_id, %User{} = user) do
    Rooms.with_member_room(user.id, room_id, fn _room ->
      reopen_room_treatment(room_id, user)
    end)
    |> normalize_reopen_member_room_result()
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

  @doc """
  Preloads associations required for public and realtime presentation of a Treatment.
  """
  def preload_for_presentation(%Treatment{} = treatment) do
    Repo.preload(treatment, :assigned_agent)
  end

  @doc """
  Lists eligible transfer candidate agents for a Treatment in progress.
  Pure read-only operation (no mutations, no exclusive locks, no audit events, no broadcasts).
  """
  def list_transfer_candidates(room_id, %User{} = current_user) do
    with {:ok, room_id} <- Ecto.UUID.cast(room_id),
         :ok <- Authorization.authorize(current_user, "treatment.transfer"),
         {:ok, _room} <- Rooms.fetch_member_room(current_user.id, room_id),
         %Treatment{} = treatment <- get_by_room_id(room_id),
         :ok <- validate_transfer_listing_state(treatment, current_user) do
      candidates =
        query_transfer_candidates(room_id, current_user.id, treatment.assigned_agent_id)

      {:ok, candidates}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :invalid_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists active treatments accessible to the given user with keyset cursor pagination.

  Supported options:
  - `:limit` or `"limit"`: Integer between 1 and 100 (defaults to 50).
  - `:cursor` or `"cursor"`: Keyset cursor string generated from previous page.
  """
  def list_queue(%User{} = user, opts \\ %{}) do
    with {:ok, limit} <- parse_queue_limit(get_opt(opts, :limit)),
         {:ok, cursor} <- decode_queue_cursor(get_opt(opts, :cursor)) do
      search = get_opt(opts, :search)
      status = get_opt(opts, :status)
      mine = get_opt(opts, :mine) || get_opt(opts, :assigned_to_me)

      base_query =
        queue_query_for(user)
        |> maybe_filter_queue_status(status)
        |> maybe_filter_queue_mine(mine, user.id)
        |> maybe_filter_queue_search(search)

      query =
        if cursor do
          from(t in base_query,
            where:
              t.inserted_at < ^cursor.inserted_at or
                (t.inserted_at == ^cursor.inserted_at and t.id < ^cursor.id)
          )
        else
          base_query
        end

      results =
        query
        |> limit(^(limit + 1))
        |> Repo.all()

      {items, has_more} =
        if length(results) > limit do
          {Enum.take(results, limit), true}
        else
          {results, false}
        end

      next_cursor =
        if has_more and List.last(items) do
          encode_queue_cursor(List.last(items))
        else
          nil
        end

      {:ok,
       %{
         items: items,
         pagination: %{
           has_more: has_more,
           next_cursor: next_cursor,
           limit: limit
         }
       }}
    end
  end

  defp queue_query_for(%User{role: "logistics_agent", id: user_id}) do
    from(t in Treatment,
      join: r in assoc(t, :room),
      where:
        (t.status == "open" and is_nil(t.assigned_agent_id)) or
          (t.status == "in_progress" and t.assigned_agent_id == ^user_id),
      preload: [:room, :assigned_agent],
      order_by: [desc: t.inserted_at, desc: t.id]
    )
  end

  defp queue_query_for(%User{id: user_id}) do
    from(t in Treatment,
      join: r in assoc(t, :room),
      join: m in assoc(r, :members),
      where: m.id == ^user_id,
      preload: [:room, :assigned_agent],
      order_by: [desc: t.inserted_at, desc: t.id]
    )
  end

  defp maybe_filter_queue_status(query, status)
       when status in ["open", "in_progress", "resolved", "closed"] do
    from(t in query, where: t.status == ^status)
  end

  defp maybe_filter_queue_status(query, _), do: query

  defp maybe_filter_queue_mine(query, mine, user_id) when mine in [true, "true", "1"] do
    from(t in query, where: t.assigned_agent_id == ^user_id)
  end

  defp maybe_filter_queue_mine(query, _mine, _user_id), do: query

  defp maybe_filter_queue_search(query, nil), do: query
  defp maybe_filter_queue_search(query, ""), do: query

  defp maybe_filter_queue_search(query, search_term) when is_binary(search_term) do
    trimmed = String.trim(search_term)

    if trimmed == "" do
      query
    else
      clean_term =
        trimmed
        |> String.replace(~r/^trat-?/i, "")
        |> String.replace_leading("0", "")

      case queue_search_protocol_number(trimmed, clean_term) do
        nil ->
          from(t in query,
            where: fragment("CAST(? AS TEXT) LIKE ?", t.order_id, ^"%#{trimmed}%")
          )

        protocol_number ->
          from(t in query,
            where:
              fragment("CAST(? AS TEXT) LIKE ?", t.order_id, ^"%#{trimmed}%") or
                t.protocol_number == ^protocol_number
          )
      end
    end
  end

  defp maybe_filter_queue_search(query, _), do: query

  defp queue_search_protocol_number(search_term, clean_term) do
    case Integer.parse(search_term) do
      {protocol_number, ""} -> protocol_number
      _ -> parse_protocol_number(clean_term)
    end
  end

  defp parse_protocol_number(value) do
    case Integer.parse(value) do
      {protocol_number, ""} -> protocol_number
      _ -> nil
    end
  end

  def encode_queue_cursor(%Treatment{inserted_at: inserted_at, id: id}) do
    inserted_at_str = DateTime.to_iso8601(inserted_at)
    Base.url_encode64("#{inserted_at_str}|#{id}", padding: false)
  end

  def decode_queue_cursor(nil), do: {:ok, nil}
  def decode_queue_cursor(""), do: {:ok, nil}

  def decode_queue_cursor(cursor_str) when is_binary(cursor_str) do
    with {:ok, decoded} <- Base.url_decode64(cursor_str, padding: false),
         [inserted_at_str, id] <- String.split(decoded, "|", parts: 2),
         {:ok, datetime, _offset} <- DateTime.from_iso8601(inserted_at_str),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, %{inserted_at: datetime, id: id}}
    else
      _ -> {:error, :invalid_cursor}
    end
  end

  def decode_queue_cursor(_), do: {:error, :invalid_cursor}

  def parse_queue_limit(nil), do: {:ok, 50}
  def parse_queue_limit(""), do: {:ok, 50}

  def parse_queue_limit(limit) when is_integer(limit) do
    if limit < 1 or limit > 100, do: {:error, :invalid_limit}, else: {:ok, limit}
  end

  def parse_queue_limit(limit_str) when is_binary(limit_str) do
    case Integer.parse(limit_str) do
      {limit, ""} when limit >= 1 and limit <= 100 -> {:ok, limit}
      _ -> {:error, :invalid_limit}
    end
  end

  def parse_queue_limit(_), do: {:error, :invalid_limit}

  defp get_opt(opts, key) when is_map(opts) do
    Map.get(opts, key) || Map.get(opts, to_string(key))
  end

  defp validate_transfer_listing_state(
         %Treatment{status: status, assigned_agent_id: assigned_agent_id},
         user
       ) do
    cond do
      status != "in_progress" ->
        {:error, :invalid_status}

      assigned_agent_id != user.id ->
        {:error, :not_assigned_agent}

      true ->
        :ok
    end
  end

  defp query_transfer_candidates(room_id, current_user_id, assigned_agent_id) do
    base_query =
      from(user in User,
        join: membership in "room_members",
        on: membership.user_id == user.id,
        where: membership.room_id == type(^room_id, :binary_id),
        where: user.role == "logistics_agent",
        where: user.id != ^current_user_id,
        order_by: [asc: user.username],
        select: %{id: user.id, username: user.username}
      )

    query =
      if is_binary(assigned_agent_id) and assigned_agent_id != current_user_id do
        from(user in base_query, where: user.id != ^assigned_agent_id)
      else
        base_query
      end

    Repo.all(query)
  end

  defp open_new_treatment(order_id, user_id) do
    case Rooms.open_order_room(order_id, user_id) do
      {:ok, room} -> create_treatment(room.id, order_id, user_id)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp open_existing_treatment(%Treatment{status: "closed"} = treatment, user_id) do
    if Rooms.room_member?(user_id, treatment.room_id) do
      room = Repo.get!(Chat.Rooms.Room, treatment.room_id)
      %{treatment: Repo.preload(treatment, :room), room: room}
    else
      Repo.rollback(:forbidden)
    end
  end

  defp open_existing_treatment(%Treatment{} = treatment, user_id) do
    case Rooms.open_order_room(treatment.order_id, user_id) do
      {:ok, room} -> %{treatment: Repo.preload(treatment, :room), room: room}
      {:error, reason} -> Repo.rollback(reason)
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

  defp create_structured_treatment(room_id, order_id, user_id, reason_id, description) do
    %Treatment{}
    |> Treatment.changeset(%{
      order_id: order_id,
      room_id: room_id,
      opened_by_id: user_id,
      status: "open",
      treatment_reason_id: reason_id,
      initial_description: description
    })
    |> Repo.insert()
    |> case do
      {:ok, treatment} ->
        with {:ok, _event} <- record_event(treatment, user_id, "treatment_created") do
          {:ok, treatment}
        end

      error ->
        error
    end
  end

  defp active_reason(%{reason_code: reason_code}) when is_binary(reason_code) do
    case Repo.get_by(Reason, code: reason_code, active: true) do
      nil -> {:error, :invalid_reason}
      reason -> {:ok, reason}
    end
  end

  defp active_reason(_attrs), do: {:error, :invalid_reason}

  defp list_active_reasons do
    from(reason in Reason, where: reason.active, order_by: reason.sort_order)
    |> Repo.all()
  end

  defp initial_description(%{initial_description: description}) when is_binary(description) do
    description = String.trim(description)

    if description == "", do: {:error, :invalid_description}, else: {:ok, description}
  end

  defp initial_description(_attrs), do: {:error, :invalid_description}

  defp record_event(treatment, actor_id, event_type, metadata \\ %{}) do
    changeset =
      AuditEvent.changeset(%AuditEvent{}, %{
        actor_id: actor_id,
        event_type: event_type,
        metadata: metadata,
        treatment_id: treatment.id
      })

    audit_event_inserter().insert(changeset)
  end

  defp audit_event_inserter,
    do: Application.get_env(:chat, :treatment_audit_event_inserter, Repo)

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
      run_assignment_transaction(treatment_id, user)
    end
  end

  defp run_assignment_transaction(treatment_id, user) do
    if Repo.in_transaction?() do
      assign_locked_and_audit(treatment_id, user)
    else
      result =
        Repo.transaction(fn -> assign_locked_and_audit(treatment_id, user) end)
        |> normalize_assignment_transaction_result()

      cache_assignment_membership(result)
    end
  end

  defp cache_assignment_membership({:ok, treatment, result} = assignment)
       when result in [:assigned, :idempotent] do
    MembershipCache.put(user_id_from_assignment(treatment), treatment.room_id, true)
    assignment
  end

  defp cache_assignment_membership(result), do: result

  defp user_id_from_assignment(%Treatment{assigned_agent_id: user_id}), do: user_id

  defp cache_transfer_membership({:ok, %Treatment{} = treatment, :transferred} = result) do
    MembershipCache.put(treatment.assigned_agent_id, treatment.room_id, true)
    result
  end

  defp cache_transfer_membership(result), do: result

  defp run_unassign_transaction(treatment_id, user) do
    if Repo.in_transaction?() do
      unassign_locked_and_audit(treatment_id, user)
    else
      Repo.transaction(fn -> unassign_locked_and_audit(treatment_id, user) end)
      |> normalize_unassign_transaction_result()
    end
  end

  defp run_transfer_transaction(treatment_id, current_agent, target_agent) do
    if Repo.in_transaction?() do
      transfer_locked_and_audit(treatment_id, current_agent, target_agent)
    else
      Repo.transaction(fn ->
        transfer_locked_and_audit(treatment_id, current_agent, target_agent)
      end)
      |> normalize_transfer_transaction_result()
    end
  end

  defp transfer_room_treatment(room_id, current_agent, target_agent_id) do
    case get_by_room_id(room_id) do
      nil ->
        {:error, :not_found}

      %Treatment{id: treatment_id} ->
        with {:ok, target_agent_id} <- Ecto.UUID.cast(target_agent_id),
             %User{} = target_agent <- Repo.get(User, target_agent_id) do
          run_transfer_transaction(treatment_id, current_agent, target_agent)
        else
          :error -> {:error, :invalid_target_agent}
          nil -> {:error, :invalid_target_agent}
        end
    end
  end

  defp assign_room_treatment(room_id, user) do
    case get_by_room_id(room_id) do
      nil ->
        {:error, :not_found}

      %Treatment{id: treatment_id} ->
        assign_agent_result(treatment_id, user)
    end
  end

  defp unassign_room_treatment(room_id, user) do
    case get_by_room_id(room_id) do
      nil ->
        {:error, :not_found}

      %Treatment{id: treatment_id} ->
        run_unassign_transaction(treatment_id, user)
    end
  end

  defp resolve_room_treatment(room_id, user) do
    case get_by_room_id(room_id) do
      nil -> {:error, :not_found}
      %Treatment{id: treatment_id} -> resolve_result(treatment_id, user)
    end
  end

  defp reopen_room_treatment(room_id, user) do
    case get_by_room_id(room_id) do
      nil -> {:error, :not_found}
      %Treatment{} = treatment -> reopen(treatment, user)
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
        with {:ok, _membership} <- ensure_assignment_membership(treatment.room_id, user.id),
             {:ok, _event} <- record_event(treatment, user.id, "treatment_assigned") do
          {:ok, treatment, :assigned}
        else
          {:error, reason} -> Repo.rollback(reason)
        end

      {:ok, treatment, :idempotent} ->
        case ensure_assignment_membership(treatment.room_id, user.id) do
          {:ok, _membership} -> {:ok, treatment, :idempotent}
          {:error, reason} -> Repo.rollback(reason)
        end

      error ->
        error
    end
  end

  defp ensure_assignment_membership(room_id, user_id) do
    %RoomMember{}
    |> RoomMember.changeset(%{room_id: room_id, user_id: user_id})
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:user_id, :room_id]
    )
    |> case do
      {:ok, membership} ->
        {:ok, membership}

      error ->
        error
    end
  end

  defp unassign_locked_and_audit(treatment_id, user) do
    case unassign_locked(treatment_id, user) do
      {:ok, treatment, :unassigned} ->
        case record_event(treatment, user.id, "treatment_unassigned") do
          {:ok, _event} -> {:ok, treatment, :unassigned}
          {:error, reason} -> Repo.rollback(reason)
        end

      error ->
        error
    end
  end

  defp transfer_locked_and_audit(treatment_id, current_agent, target_agent) do
    case transfer_locked(treatment_id, current_agent, target_agent) do
      {:ok, treatment, :transferred} ->
        metadata = %{
          "previous_agent_id" => current_agent.id,
          "assigned_agent_id" => target_agent.id
        }

        case record_event(treatment, current_agent.id, "treatment_transferred", metadata) do
          {:ok, _event} -> {:ok, treatment, :transferred}
          {:error, reason} -> Repo.rollback(reason)
        end

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

  defp unassign_locked(treatment_id, user) do
    treatment = locked_authorized_treatment(treatment_id, user.id)

    case treatment do
      nil ->
        {:error, :not_found}

      %Treatment{status: "in_progress", assigned_agent_id: assigned_agent_id}
      when assigned_agent_id == user.id ->
        unassign_locked_treatment(treatment)

      %Treatment{status: "in_progress"} ->
        {:error, :not_assigned_agent}

      %Treatment{} ->
        {:error, :invalid_status}
    end
  end

  defp confirm_resolution_locked(treatment_id, user) do
    treatment = locked_authorized_treatment(treatment_id, user.id)

    case treatment do
      nil ->
        {:error, :not_found}

      %Treatment{status: "resolved"} ->
        confirm_resolution_locked_and_audit(treatment, user)

      %Treatment{} ->
        {:error, :invalid_status}
    end
  end

  defp confirm_resolution_locked_and_audit(treatment, user) do
    case treatment
         |> Treatment.closure_changeset(user.id, DateTime.utc_now())
         |> Repo.update() do
      {:ok, closed_treatment} ->
        case record_event(closed_treatment, user.id, "treatment_closed") do
          {:ok, _event} -> {:ok, closed_treatment, :closed}
          {:error, reason} -> Repo.rollback(reason)
        end

      error ->
        error
    end
  end

  defp transfer_locked(treatment_id, current_agent, target_agent) do
    treatment = locked_authorized_treatment(treatment_id, current_agent.id)

    case treatment do
      nil ->
        {:error, :not_found}

      %Treatment{status: "in_progress", assigned_agent_id: assigned_agent_id}
      when assigned_agent_id != current_agent.id ->
        {:error, :not_assigned_agent}

      %Treatment{status: "in_progress"} ->
        with :ok <- validate_transfer_target(treatment.room_id, current_agent, target_agent) do
          transfer_locked_treatment(treatment, target_agent)
        end

      %Treatment{} ->
        {:error, :invalid_status}
    end
  end

  defp transfer_locked_treatment(treatment, target_agent) do
    with {:ok, _membership} <- ensure_assignment_membership(treatment.room_id, target_agent.id),
         {:ok, transferred_treatment} <-
           treatment
           |> Treatment.transfer_changeset(target_agent.id, DateTime.utc_now())
           |> Repo.update() do
      {:ok, transferred_treatment, :transferred}
    else
      error -> error
    end
  end

  defp validate_transfer_target(room_id, current_agent, target_agent) do
    cond do
      current_agent.id == target_agent.id ->
        {:error, :same_agent}

      not valid_target_agent?(room_id, target_agent.id) ->
        {:error, :invalid_target_agent}

      true ->
        :ok
    end
  end

  defp valid_target_agent?(_room_id, target_agent_id) do
    case Repo.get(User, target_agent_id) do
      %User{role: "logistics_agent"} -> true
      _ -> false
    end
  end

  defp unassign_locked_treatment(treatment) do
    case treatment |> Treatment.unassignment_changeset() |> Repo.update() do
      {:ok, unassigned_treatment} -> {:ok, unassigned_treatment, :unassigned}
      error -> error
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

  defp reopen_locked(treatment_id, user) do
    treatment = locked_authorized_treatment(treatment_id, user.id)

    case treatment do
      nil ->
        {:error, :not_found}

      %Treatment{status: "resolved", assigned_agent_id: assigned_agent_id} ->
        with :ok <- Authorization.authorize_current_operator(user, assigned_agent_id) do
          reopen_locked_and_audit(treatment, user)
        end

      %Treatment{} ->
        {:error, :invalid_status}
    end
  end

  defp reopen_locked_and_audit(treatment, user) do
    case treatment |> Treatment.reopen_changeset() |> Repo.update() do
      {:ok, reopened_treatment} ->
        case record_event(reopened_treatment, user.id, "treatment_reopened") do
          {:ok, _event} -> {:ok, reopened_treatment, :reopened}
          {:error, reason} -> Repo.rollback(reason)
        end

      error ->
        error
    end
  end

  defp authorized_treatment(treatment_id, user_id) do
    treatment_id
    |> authorized_treatment_query(user_id)
    |> Repo.one()
  end

  defp locked_authorized_treatment(treatment_id, user_id) do
    treatment_id
    |> authorized_treatment_query(user_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp authorized_treatment_query(treatment_id, user_id) do
    from(treatment in Treatment,
      join: membership in "room_members",
      on: membership.room_id == treatment.room_id,
      where: treatment.id == type(^treatment_id, :binary_id),
      where: membership.user_id == type(^user_id, :binary_id)
    )
  end

  defp normalize_transaction_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_transaction_result({:ok, {:ok, result}}), do: {:ok, result}
  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, reason}), do: {:error, reason}

  defp normalize_assignment_transaction_result({:ok, {:ok, treatment, result}}),
    do: {:ok, treatment, result}

  defp normalize_assignment_transaction_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_assignment_transaction_result({:error, reason}), do: {:error, reason}

  defp normalize_unassign_transaction_result({:ok, {:ok, treatment, result}}),
    do: {:ok, treatment, result}

  defp normalize_unassign_transaction_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_unassign_transaction_result({:error, reason}), do: {:error, reason}

  defp normalize_transfer_transaction_result({:ok, {:ok, treatment, result}}),
    do: {:ok, treatment, result}

  defp normalize_transfer_transaction_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_transfer_transaction_result({:error, reason}), do: {:error, reason}

  defp normalize_resolution_transaction_result({:ok, {:ok, treatment, result}}),
    do: {:ok, treatment, result}

  defp normalize_resolution_transaction_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_resolution_transaction_result({:error, reason}), do: {:error, reason}

  defp normalize_confirmation_transaction_result({:ok, {:ok, treatment, result}}),
    do: {:ok, treatment, result}

  defp normalize_confirmation_transaction_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_confirmation_transaction_result({:error, reason}), do: {:error, reason}

  defp normalize_reopen_transaction_result({:ok, {:ok, treatment, result}}),
    do: {:ok, treatment, result}

  defp normalize_reopen_transaction_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_reopen_transaction_result({:error, reason}), do: {:error, reason}

  defp normalize_member_room_result({:ok, {:ok, treatment, result}}),
    do: {:ok, treatment, result}

  defp normalize_member_room_result({:ok, {:ok, result}}), do: {:ok, result}

  defp normalize_member_room_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_member_room_result({:error, reason}), do: {:error, reason}

  defp normalize_reopen_member_room_result({:ok, {:ok, treatment, result}}),
    do: {:ok, treatment, result}

  defp normalize_reopen_member_room_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_reopen_member_room_result({:error, :forbidden}), do: {:error, :not_found}
  defp normalize_reopen_member_room_result({:error, reason}), do: {:error, reason}

  defp normalize_unassign_member_room_result({:ok, {:ok, treatment, result}}),
    do: {:ok, treatment, result}

  defp normalize_unassign_member_room_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_unassign_member_room_result({:error, :forbidden}), do: {:error, :not_found}
  defp normalize_unassign_member_room_result({:error, reason}), do: {:error, reason}

  defp normalize_transfer_member_room_result({:ok, {:ok, treatment, result}}),
    do: {:ok, treatment, result}

  defp normalize_transfer_member_room_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_transfer_member_room_result({:error, :forbidden}), do: {:error, :not_found}
  defp normalize_transfer_member_room_result({:error, reason}), do: {:error, reason}
end
