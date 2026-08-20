defmodule ChatWeb.RoomController do
  use ChatWeb, :controller

  alias Chat.Repo
  alias Chat.Rooms
  alias ChatWeb.Presence

  def index(conn, _params) do
    user = conn.assigns.current_user
    # get_user_rooms/1 already preloads members (single batched query); a
    # second Repo.preload here would be a redundant no-op.
    rooms = Rooms.get_user_rooms(user.id)

    rooms_data =
      Enum.map(rooms, fn room ->
        %{
          id: room.id,
          name: room.name,
          description: room.description,
          created_by: room.creator_id,
          members_count: length(room.members),
          inserted_at: room.inserted_at
        }
      end)

    json(conn, %{rooms: rooms_data})
  end

  def create(conn, %{"room" => room_params}) do
    user = conn.assigns.current_user

    case Rooms.create_room(room_params, user.id) do
      {:ok, room} ->
        conn
        |> put_status(:created)
        |> json(%{
          room: %{
            id: room.id,
            name: room.name,
            description: room.description,
            created_by: room.creator_id,
            inserted_at: room.inserted_at
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Rooms.fetch_member_room(user.id, id) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "room_not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "not_a_member"})

      {:ok, room} ->
        room = room |> Repo.preload([:members, :creator])

        json(conn, %{
          room: %{
            id: room.id,
            name: room.name,
            description: room.description,
            created_by: room.creator_id,
            members_count: length(room.members)
          }
        })
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    room = Rooms.get_room(id)

    cond do
      room == nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "room_not_found"})

      room.creator_id != user.id ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "not_authorized"})

      true ->
        Rooms.delete_room(room)
        send_resp(conn, :no_content, "")
    end
  end

  def join(conn, %{"room_id" => id}) do
    user = conn.assigns.current_user

    case Rooms.get_room(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "room_not_found"})

      _room ->
        case Rooms.join_room(user.id, id) do
          {:ok, _} ->
            send_resp(conn, :no_content, "")

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "could_not_join"})
        end
    end
  end

  def leave(conn, %{"room_id" => id}) do
    user = conn.assigns.current_user

    case Rooms.leave_room(user.id, id) do
      {:ok, _count} ->
        send_resp(conn, :no_content, "")

      {:error, :creator_cannot_leave} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "creator_cannot_leave"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "room_not_found"})

      {:error, :not_member} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "not_a_member"})
    end
  end

  def online(conn, %{"room_id" => id}) do
    user = conn.assigns.current_user

    case Rooms.fetch_member_room(user.id, id) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "room_not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "not_a_member"})

      {:ok, _room} ->
        online_users = Presence.list_online_users("room:#{id}")

        json(conn, %{
          room_id: id,
          online_users: online_users,
          online_count: length(online_users)
        })
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
