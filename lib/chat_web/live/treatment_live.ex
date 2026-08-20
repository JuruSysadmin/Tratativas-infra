defmodule ChatWeb.TreatmentLive do
  @moduledoc """
  MVP de seleção de pedidos e abertura automática da tratativa.
  """

  use ChatWeb, :live_view

  alias Chat.Orders.Mock
  alias Chat.Treatments

  @fixture_customer_id 491_564

  @impl true
  def mount(_params, _session, socket) do
    treatments = Mock.list_treatments_for_customer(@fixture_customer_id)

    {:ok,
     socket
     |> assign(:customer_id, @fixture_customer_id)
     |> assign(:treatments, treatments)
     |> assign(:selected_treatment, nil)
     |> assign(:selected_chat_path, nil)
     |> assign(:audit_events, [])}
  end

  @impl true
  def handle_params(%{"id" => treatment_id}, _uri, socket) do
    case Treatments.get_for_user(treatment_id, socket.assigns.current_user.id) do
      {:ok, treatment} ->
        {:noreply,
         socket
         |> assign(:selected_treatment, treatment)
         |> assign(:selected_chat_path, ~p"/chat?room_id=#{treatment.room_id}")
         |> assign(
           :audit_events,
           Treatments.list_audit_events(treatment.id, socket.assigns.current_user.id)
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Tratativa não encontrada")}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("open_treatment", %{"order_id" => order_id}, socket)
      when is_binary(order_id) do
    with {order_id, ""} <- Integer.parse(order_id),
         {:ok, %{treatment: treatment}} <-
           Treatments.open_for_order(order_id, socket.assigns.current_user.id) do
      {:noreply, push_navigate(socket, to: ~p"/tratativas/#{treatment.id}")}
    else
      :error ->
        {:noreply, put_flash(socket, :error, "Pedido inválido")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível abrir a tratativa")}
    end
  end

  def handle_event("open_treatment", _params, socket), do: {:noreply, socket}
end
