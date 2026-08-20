defmodule ChatWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :chat

  @session_options [
    store: :cookie,
    key: "_chat_key",
    signing_salt: "1QRqPTMP",
    http_only: true,
    secure: Application.compile_env(:chat, :secure_session_cookie, false),
    same_site: "Lax",
    max_age: 28_800
  ]

  socket "/socket", ChatWeb.UserSocket,
    websocket: true,
    longpoll: false

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :chat,
    gzip: not code_reloading?,
    only: ChatWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if Mix.env() == :dev do
    plug Tidewave
  end

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :chat
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug ChatWeb.Cors

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug ChatWeb.Router
end
