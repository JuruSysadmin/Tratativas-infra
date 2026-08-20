defmodule ChatWeb.MessageEditDialogComponent do
  @moduledoc """
  Diálogo para edição de mensagens.
  """

  use Phoenix.Component

  import ChatWeb.CoreComponents

  attr :message_id, :string, default: nil
  attr :content, :string, default: ""

  def message_edit_dialog(%{message_id: nil} = assigns),
    do: ~H"""
    """

  def message_edit_dialog(assigns) do
    ~H"""
    <div class="modal-backdrop">
      <section
        class="carbon-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="message-edit-dialog-title"
        phx-click-away="cancel_edit_message"
      >
        <form id="message-edit-form" phx-submit="save_edit_message">
          <input type="hidden" name="message_id" value={@message_id} />

          <header class="carbon-modal-header">
            <h2 id="message-edit-dialog-title">Editar mensagem</h2>
            <button
              type="button"
              class="carbon-modal-close"
              phx-click="cancel_edit_message"
              aria-label="Fechar"
            >
              <.icon name="carbon-close" />
            </button>
          </header>

          <div class="carbon-modal-content">
            <.input
              type="textarea"
              id="message-edit-input"
              name="content"
              value={@content}
              class="message-edit-input"
              rows="4"
              maxlength="4000"
              aria-label="Conteúdo da mensagem"
            />
            <p class="message-edit-hint">
              O histórico de leitura e entrega não é alterado pela edição.
            </p>
          </div>

          <footer class="carbon-modal-footer fluid-actions">
            <button
              id="message-edit-cancel"
              type="button"
              class="modal-button modal-button--secondary"
              phx-click="cancel_edit_message"
            >
              Cancelar
            </button>
            <button
              id="message-edit-save"
              type="submit"
              class="modal-button modal-button--primary"
            >
              Salvar alterações
            </button>
          </footer>
        </form>
      </section>
    </div>
    """
  end
end
