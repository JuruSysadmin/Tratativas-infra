import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
test_db_socket_dir = System.get_env("CHAT_TEST_DB_SOCKET_DIR")

config :chat, Chat.Repo,
  username: System.get_env("CHAT_TEST_DB_USERNAME", "postgres"),
  password: System.get_env("CHAT_TEST_DB_PASSWORD", "postgres"),
  hostname:
    if(test_db_socket_dir, do: nil, else: System.get_env("CHAT_TEST_DB_HOST", "127.0.0.1")),
  socket_dir: test_db_socket_dir,
  database: "chat_test#{System.get_env("MIX_TEST_PARTITION")}",
  port: String.to_integer(System.get_env("CHAT_TEST_DB_PORT", "5432")),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :chat, Oban, testing: :manual

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :chat, ChatWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  check_origin: false,
  secret_key_base: "TDVDT3BFVUqFLSWMwhC7FRHseCyyxrdZXadpioyDg27IsCxOzrQs1PojAnQRZnU5",
  server: System.get_env("CHAT_E2E") == "true"

config :chat, :cors_origins, ["http://localhost:5173", "https://vm.jurunense.com"]

config :chat, :auth_login_module, Chat.Auth.E2ELogin

# In test we don't send emails
config :chat, Chat.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Excoveralls configuration
config :excoveralls,
  test_task: "ecto.create --quiet && ecto.migrate --quiet && test",
  coveralls: true,
  html: true,
  xml: true
