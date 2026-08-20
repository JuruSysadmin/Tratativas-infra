defmodule ChatWeb.ChatMessages do
  @moduledoc """
  Gerenciamento de estado de mensagens no LiveView de chat.
  """

  use Phoenix.LiveView

  alias Chat.Messages

  @message_page_size 50

  @doc """
  Prepara o estado inicial de mensagens para o socket.
  """
  def init(socket) do
    socket
    |> stream(:messages, [])
    |> assign(:message_ids, MapSet.new())
    |> assign(:message_order, [])
    |> assign(:oldest_message_id, nil)
    |> assign(:pending_messages, %{})
    |> assign(:pending_message_order, [])
    |> assign(:has_more_messages, false)
    |> assign(:message_map, %{})
    |> assign(:message_statuses, %{})
  end

  @doc """
  Cria uma mensagem pendente (otimista) a partir do texto, usuário e sala.
  """
  def pending_message(content, user, room, client_id \\ Ecto.UUID.generate()) do
    %{
      id: "pending-#{client_id}",
      client_id: client_id,
      content: content,
      user_id: user.id,
      user: user,
      room_id: room.id,
      inserted_at: NaiveDateTime.utc_now(),
      status: :sending
    }
  end

  @doc """
  Carrega a primeira página de mensagens para uma sala.
  """
  def load_room(socket, room, opts \\ []) do
    {messages, has_more?} =
      message_page(
        socket.assigns.current_user.id,
        room.id,
        nil,
        Keyword.get(opts, :through)
      )

    messages =
      messages
      |> Messages.load_read_metadata()
      |> Messages.load_delivery_metadata()

    socket
    |> reset_message_stream(messages)
    |> assign(:message_ids, MapSet.new(messages, & &1.id))
    |> assign(:message_order, Enum.map(messages, & &1.id))
    |> assign(:oldest_message_id, oldest_message_id(messages))
    |> assign(:pending_messages, %{})
    |> assign(:pending_message_order, [])
    |> assign(:has_more_messages, has_more?)
    |> assign(:message_map, build_message_map(messages))
    |> assign(:message_statuses, %{})
  end

  @doc """
  Limpa o estado de mensagens quando nenhuma sala está selecionada.
  """
  def clear(socket) do
    socket
    |> stream(:messages, [], reset: true)
    |> assign(:message_ids, MapSet.new())
    |> assign(:message_order, [])
    |> assign(:oldest_message_id, nil)
    |> assign(:pending_messages, %{})
    |> assign(:pending_message_order, [])
    |> assign(:has_more_messages, false)
    |> assign(:message_map, %{})
    |> assign(:message_statuses, %{})
  end

  @doc """
  Persiste uma mensagem otimista e a remove da lista de pendentes.
  """
  def append_persisted(socket, pending_id, message) do
    socket
    |> remove_pending(pending_id)
    |> append_message(message)
  end

  @doc """
  Carrega mensagens antigas quando solicitado.
  """
  def load_older(socket, oldest_id) do
    {older_messages, has_more?} =
      message_page(socket.assigns.current_user.id, socket.assigns.current_room.id, oldest_id)

    socket
    |> prepend_messages(older_messages)
    |> assign(:has_more_messages, has_more?)
  end

  @doc """
  Atualiza o status de uma mensagem pendente.
  """
  def update_pending_status(socket, message_id, status) do
    case socket.assigns.pending_messages do
      %{^message_id => message} ->
        message = Map.put(message, :status, status)
        update(socket, :pending_messages, &Map.put(&1, message_id, message))

      _pending_messages ->
        socket
    end
  end

  @doc """
  Marca mensagens como lidas e retorna os IDs inseridos.
  """
  def mark_read(socket, message_ids) when is_list(message_ids) do
    user = socket.assigns.current_user
    room = socket.assigns.current_room

    message_ids = Enum.filter(message_ids, &persisted_id?/1)

    if room do
      Messages.mark_room_read(message_ids, user.id, room.id)
    else
      {[], false}
    end
  end

  def mark_read(_socket, _message_ids), do: {[], false}

  @doc """
  Registra a confirmação de entrega de mensagens já renderizadas pelo navegador.
  """
  def mark_delivered(socket, message_ids) when is_list(message_ids) do
    user = socket.assigns.current_user
    room = socket.assigns.current_room
    message_ids = Enum.filter(message_ids, &persisted_id?/1)

    if room do
      case Messages.advance_room_delivery_position(user.id, room.id, message_ids) do
        {:ok, _position} -> {message_ids, true}
        {:error, _reason} -> {[], false}
      end
    else
      {[], false}
    end
  end

  def mark_delivered(_socket, _message_ids), do: {[], false}

  @doc """
  Remove uma mensagem do stream e dos índices.
  """
  def remove(socket, message_id) do
    socket
    |> stream_delete(:messages, %{id: message_id})
    |> update(:message_ids, &MapSet.delete(&1, message_id))
    |> assign(:message_order, List.delete(socket.assigns[:message_order] || [], message_id))
    |> update(:message_map, &Map.delete(&1, message_id))
    |> update(:message_statuses, &Map.delete(&1, message_id))
  end

  @doc """
  Atualiza uma mensagem persistida no stream e nos índices.

  Os metadados de leitura conhecidos (nomes de leitores e contador) são
  preservados, já que a edição não altera o histórico de leitura/entrega.
  """
  def update_message(socket, message) do
    case Enum.find_index(socket.assigns[:message_order] || [], &(&1 == message.id)) do
      nil ->
        socket

      index ->
        previous = Map.get(socket.assigns.message_map || %{}, message.id)
        message = message |> load_counts() |> preserve_read_metadata(previous)

        socket
        |> stream_insert(:messages, message, at: index)
        |> update(:message_map, &Map.put(&1, message.id, message))
        |> update(:message_statuses, &Map.put(&1, message.id, status(socket, message)))
    end
  end

  @doc """
  Atualiza os contadores de leitura de múltiplas mensagens em uma única consulta.
  """
  def refresh_read_counts(socket, message_ids) do
    requested_ids = MapSet.new(message_ids)

    updated_messages =
      socket.assigns.message_order
      |> Enum.filter(&MapSet.member?(requested_ids, &1))
      |> Enum.map(&Map.fetch!(socket.assigns.message_map, &1))
      |> Messages.load_read_metadata()

    Enum.reduce(updated_messages, socket, fn message, socket ->
      socket
      |> stream_update(message)
      |> update(:message_map, &Map.put(&1, message.id, message))
      |> update(:message_statuses, &Map.put(&1, message.id, status(socket, message)))
    end)
  end

  @doc """
  Atualiza os contadores de entrega persistidos para todas as mensagens.
  """
  def refresh_counts(socket) do
    ordered_messages =
      (socket.assigns[:message_order] || [])
      |> Enum.map(&Map.fetch!(socket.assigns.message_map, &1))
      |> Messages.load_delivery_metadata()

    updated_map = build_message_map(ordered_messages)

    socket
    |> reset_message_stream(ordered_messages)
    |> assign(:message_map, updated_map)
  end

  @doc """
  Recalcula os status de entrega/leitura de todas as mensagens.
  """
  def refresh_statuses(socket) do
    statuses =
      socket.assigns.message_map
      |> Enum.map(fn {message_id, message} ->
        {message_id, status(socket, message)}
      end)
      |> Map.new()

    assign(socket, :message_statuses, statuses)
  end

  defp append_message(socket, message) do
    current_room = socket.assigns.current_room

    if current_room && current_room.id == message.room_id &&
         not MapSet.member?(socket.assigns.message_ids, message.id) do
      message =
        if Map.get(message, :status) in [:sending, :failed] do
          message
        else
          load_counts(message)
        end

      socket =
        socket
        |> stream_insert(:messages, message, at: -1)
        |> update(:message_ids, &MapSet.put(&1, message.id))
        |> assign(:message_order, (socket.assigns[:message_order] || []) ++ [message.id])
        |> update(:message_map, &Map.put(&1, message.id, message))

      if Map.get(message, :status) in [:sending, :failed] do
        socket
      else
        update(socket, :message_statuses, &Map.put(&1, message.id, status(socket, message)))
      end
    else
      socket
    end
  end

  defp prepend_messages(socket, older_messages) do
    new_messages =
      Enum.reject(older_messages, &MapSet.member?(socket.assigns.message_ids, &1.id))
      |> Messages.load_read_metadata()
      |> Messages.load_delivery_metadata()

    socket =
      Enum.reduce(Enum.reverse(new_messages), socket, fn message, socket ->
        stream_insert(socket, :messages, message, at: 0)
      end)

    socket
    |> update(
      :message_ids,
      &Enum.reduce(new_messages, &1, fn message, ids -> MapSet.put(ids, message.id) end)
    )
    |> assign(
      :message_order,
      Enum.map(new_messages, fn message -> message.id end) ++
        (socket.assigns[:message_order] || [])
    )
    |> update(
      :message_map,
      &Enum.reduce(new_messages, &1, fn message, map -> Map.put(map, message.id, message) end)
    )
    |> update(
      :message_statuses,
      &Enum.reduce(new_messages, &1, fn message, statuses ->
        Map.put(statuses, message.id, status(socket, message))
      end)
    )
    |> assign(
      :oldest_message_id,
      oldest_message_id(new_messages) || socket.assigns.oldest_message_id
    )
  end

  defp remove_pending(socket, message_id) do
    pending_order = socket.assigns[:pending_message_order] || []

    socket
    |> update(:pending_messages, &Map.delete(&1, message_id))
    |> assign(:pending_message_order, List.delete(pending_order, message_id))
  end

  defp reset_message_stream(socket, messages) do
    socket = stream(socket, :messages, [], reset: true)

    messages
    |> Enum.with_index()
    |> Enum.reduce(socket, fn {message, index}, socket ->
      stream_insert(socket, :messages, message, at: index)
    end)
  end

  defp stream_update(socket, message) do
    case Enum.find_index(socket.assigns[:message_order] || [], &(&1 == message.id)) do
      nil -> socket
      index -> stream_insert(socket, :messages, message, at: index)
    end
  end

  defp load_counts(message) do
    [message] = Messages.load_delivery_metadata([message])
    message
  end

  defp preserve_read_metadata(message, nil), do: message

  defp preserve_read_metadata(message, previous) do
    previous_reader_names = Map.get(previous, :reader_names, [])

    if previous_reader_names == [] do
      message
    else
      %{
        message
        | read_count: Map.get(previous, :read_count, 0),
          reader_names: previous_reader_names
      }
    end
  end

  defp status(_socket, message) do
    Messages.message_status(message.read_count, message.delivered_count)
  end

  defp oldest_message_id([oldest | _messages]), do: oldest.id
  defp oldest_message_id([]), do: nil

  defp build_message_map(messages) do
    Map.new(messages, &{&1.id, &1})
  end

  defp message_page(user_id, room_id, before_id, through_id \\ nil) do
    messages =
      Messages.list_messages_for_member(
        user_id,
        room_id,
        limit: @message_page_size + 1,
        before: before_id,
        through: through_id
      )

    {Enum.take(messages, -@message_page_size), length(messages) > @message_page_size}
  end

  defp persisted_id?(message_id) when is_binary(message_id) do
    match?({:ok, _uuid}, Ecto.UUID.cast(message_id))
  end

  defp persisted_id?(_message_id), do: false
end
