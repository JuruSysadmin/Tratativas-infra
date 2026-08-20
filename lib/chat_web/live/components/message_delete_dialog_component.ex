defmodule ChatWeb.MessageDeleteDialogComponent do
  @moduledoc """
  Diálogo de confirmação para exclusão de mensagens.
  """

  use Phoenix.Component

  import ChatWeb.CoreComponents

  attr :message_id, :string, default: nil

  def message_delete_dialog(%{message_id: nil} = assigns),
    do: ~H"""
    """

  def message_delete_dialog(assigns) do
    ~H"""
    <div class="modal-backdrop">
      <section
        class="carbon-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="message-delete-dialog-title"
        phx-click-away="cancel_delete_message"
      >
        <header class="carbon-modal-header">
          <h2 id="message-delete-dialog-title">Excluir mensagem</h2>
          <button
            type="button"
            class="carbon-modal-close"
            phx-click="cancel_delete_message"
            aria-label="Fechar"
          >
            <.icon name="carbon-close" />
          </button>
        </header>

        <div class="carbon-modal-content">
          <p>Excluir esta mensagem para todos os participantes?</p>
          <p>Esta ação não pode ser desfeita.</p>
        </div>

        <footer class="carbon-modal-footer fluid-actions">
          <button type="button" class="modal-button modal-button--secondary" phx-click="cancel_delete_message">
            Cancelar
          </button>
          <button
            type="button"
            class="modal-button modal-button--danger"
            phx-click="delete_message"
            phx-value-message_id={@message_id}
          >
            Excluir mensagem
          </button>
        </footer>
      </section>
    </div>
    """
  end
end
