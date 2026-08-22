defmodule ChatWeb.Router do
  @moduledoc "Routes and request pipelines for the Chat web interface."

  use ChatWeb, :router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug Chat.Auth.Plug
  end

  scope "/", ChatWeb do
    pipe_through :api

    get "/health", HealthController, :health
    get "/ready", HealthController, :ready
  end

  scope "/", ChatWeb do
    pipe_through :browser

    live_session :public do
      live "/", LoginLive, :index
    end

    live_session :authenticated, on_mount: [{ChatWeb.UserAuth, :ensure_authenticated}] do
      live "/home", HomeLive, :index
      live "/tratativas", TreatmentLive, :index
      live "/tratativas/:id", TreatmentLive, :show
      live "/chat", ChatLive, :index
      live "/perfil", ProfileLive, :index
    end

    post "/session", SessionController, :create
    delete "/session", SessionController, :delete
  end

  scope "/api/auth", ChatWeb do
    pipe_through :api

    post "/login", AuthController, :login
    post "/refresh", AuthController, :refresh
  end

  scope "/api/auth", ChatWeb do
    pipe_through [:api, :auth]

    get "/me", AuthController, :me
  end

  scope "/api", ChatWeb do
    pipe_through [:api, :auth]

    resources "/order-conversations", OrderConversationController, only: [:index, :create]

    resources "/rooms", RoomController, only: [:index, :create, :show, :delete] do
      post "/join", RoomController, :join
      post "/leave", RoomController, :leave
      get "/online", RoomController, :online
      post "/attachments/presign", MessageAttachmentController, :presign

      resources "/messages", MessageController, only: [:index, :create, :delete]

      post "/attachments/:attachment_id/confirm", MessageAttachmentController, :confirm
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:chat, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]
      live_dashboard "/dashboard", metrics: ChatWeb.Telemetry
    end
  end
end
