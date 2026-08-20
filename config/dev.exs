import Config

config :ex_aws, http_client: Chat.ExAwsHackneyClient

# Configure your database
config :chat, Chat.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  database: "chat",
  port: 5432,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
config :chat, ChatWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 5000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "plc+JqYunTBMiqhLpgQDnGOPukLByw7ez6vwPXLJheGyeuJdNlUlpI5qy72gn4Dh",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]}
  ]

config :chat, :cors_origins, ["http://localhost:5173", "https://vm.jurunense.com"]

config :chat, :auth,
  server_url: System.get_env("AUTH_SERVER_URL", "https://api.auth.jurunense.com"),
  jwks_uri: System.get_env("JWKS_URI", "https://api.auth.jurunense.com/.well-known/jwks.json"),
  issuer: System.get_env("JWT_ISSUER", "auth-api-jurunense"),
  audience: System.get_env("JWT_AUDIENCE", "jurunense-auth-consumers")

# Enable dev routes for dashboard and mailbox
config :chat, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Set a higher stacktrace during development
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false
