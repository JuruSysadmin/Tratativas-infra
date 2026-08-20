defmodule ChatWeb.LoginLive do
  @moduledoc "LiveView for the public Chat login screen."

  use ChatWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:username, Phoenix.Flash.get(socket.assigns.flash, :login_username) || "")
     |> assign(:app_version, Application.spec(:chat, :vsn) |> to_string())}
  end
end
