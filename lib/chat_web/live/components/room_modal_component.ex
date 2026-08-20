defmodule ChatWeb.RoomModalComponent do
  @moduledoc """
  Componente de modal para criação, exploração e exclusão de salas.
  """

  use Phoenix.Component

  import ChatWeb.CoreComponents

  attr :dialog, :atom, required: true
  attr :pending_room, :any, default: nil
  attr :available_rooms, :list, required: true
  attr :room_search, :string, required: true

  def room_modal(%{dialog: nil} = assigns),
    do: ~H"""
    """

  def room_modal(assigns) do
    ~H"""
    <div class="modal-backdrop">
      <section
        class="carbon-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="room-dialog-title"
        phx-click-away="close_room_dialog"
      >
        <header class="carbon-modal-header">
          <h2 id="room-dialog-title"><%= dialog_title(@dialog) %></h2>
          <button
            type="button"
            class="carbon-modal-close"
            phx-click="close_room_dialog"
            aria-label="Fechar"
          >
            <.icon name="carbon-close" />
          </button>
        </header>

        <%= case @dialog do %>
          <% :new -> %>
            <.new_room_form />
          <% :explore -> %>
            <.room_explorer
              available_rooms={@available_rooms}
              room_search={@room_search}
            />
          <% :delete -> %>
            <.delete_room_dialog pending_room={@pending_room} />
        <% end %>
      </section>
    </div>
    """
  end

  defp dialog_title(:new), do: "Criar sala"
  defp dialog_title(:explore), do: "Explorar salas"
  defp dialog_title(:delete), do: "Excluir sala"

  defp new_room_form(assigns) do
    ~H"""
    <form class="fluid-form room-create-form" phx-submit="create_room">
      <div class="carbon-modal-content">
        <.input name="room[name]" label="Nome" placeholder="Nome da sala" required />
        <.input name="room[description]" label="Descrição" placeholder="Descrição opcional" />
      </div>
      <footer class="carbon-modal-footer fluid-actions">
        <button type="button" class="modal-button modal-button--secondary" phx-click="close_room_dialog">
          Cancelar
        </button>
        <button type="submit" class="modal-button modal-button--primary">Criar sala</button>
      </footer>
    </form>
    """
  end

  defp room_explorer(assigns) do
    ~H"""
    <div class="carbon-modal-content room-explorer">
      <form role="search" class="room-search" phx-change="search_rooms">
        <div class="room-search-field">
          <.icon name="carbon-search" />
          <.input
            id="room-search-input"
            name="query"
            type="search"
            value={@room_search}
            placeholder="Buscar salas"
            aria-label="Buscar salas"
            aria-controls="room-explorer-results"
            aria-describedby="room-search-count"
            maxlength="100"
            phx-debounce="150"
            autocomplete="off"
          />
          <button
            :if={@room_search != ""}
            type="button"
            class="room-search-clear"
            phx-click="clear_room_search"
            aria-label="Limpar busca"
            title="Limpar busca"
          >
            <.icon name="carbon-close" />
          </button>
        </div>
      </form>
      <p id="room-search-count" class="room-search-count" aria-live="polite">
        <%= length(@available_rooms) %> salas encontradas
      </p>
      <div id="room-explorer-results" aria-live="polite">
        <%= if Enum.empty?(@available_rooms) do %>
          <div class="room-explorer-empty">
            <%= if @room_search == "" do %>
              <p>Você já participa de todas as salas disponíveis.</p>
            <% else %>
              <p>Nenhuma sala corresponde a "<%= @room_search %>".</p>
              <button type="button" class="btn btn-ghost" phx-click="clear_room_search">
                Limpar busca
              </button>
            <% end %>
          </div>
        <% else %>
          <ul class="room-explorer-list">
            <li :for={room <- @available_rooms}>
              <div>
                <strong><%= room.name %></strong>
                <p><%= room.description || "Sem descrição" %></p>
              </div>
              <button
                type="button"
                class="btn btn-primary room-join-button"
                phx-click="join_room"
                phx-value-room_id={room.id}
              >
                Entrar
              </button>
            </li>
          </ul>
        <% end %>
      </div>
    </div>
    """
  end

  defp delete_room_dialog(assigns) do
    ~H"""
    <div class="carbon-modal-content">
      <p>Excluir a sala <strong><%= @pending_room && @pending_room.name %></strong> e todas as mensagens?</p>
    </div>
    <footer class="carbon-modal-footer fluid-actions">
      <button type="button" class="modal-button modal-button--secondary" phx-click="close_room_dialog">
        Cancelar
      </button>
      <button
        type="button"
        class="modal-button modal-button--danger"
        phx-click="delete_room"
        phx-value-room_id={@pending_room && @pending_room.id}
      >
        Excluir sala
      </button>
    </footer>
    """
  end
end
