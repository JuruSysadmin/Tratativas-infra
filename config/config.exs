# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :chat,
  ecto_repos: [Chat.Repo],
  generators: [timestamp_type: :utc_datetime]

config :chat, Oban,
  repo: Chat.Repo,
  queues: [attachments: 5],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [{"@hourly", Chat.Workers.CleanupMessageAttachments, queue: :attachments}]}
  ]

config :chat, :message_attachment_storage,
  bucket: System.get_env("MESSAGE_ATTACHMENT_S3_BUCKET", "juru-bucket-teste-2026"),
  region:
    System.get_env("MESSAGE_ATTACHMENT_S3_REGION") ||
      System.get_env("AWS_REGION") ||
      System.get_env("AWS_DEFAULT_REGION", "us-east-1"),
  host: System.get_env("MESSAGE_ATTACHMENT_S3_HOST"),
  scheme: System.get_env("MESSAGE_ATTACHMENT_S3_SCHEME"),
  presign_ttl_seconds: 300

# ExAws uses Req as its default HTTP client. Development overrides this for
# MinIO because its strict SigV4 validation rejects headers added by Req.
config :ex_aws, http_client: ExAws.Request.Req

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
config :tzdata, :http_client, Chat.TzdataHTTPClient

# Configure the endpoint
config :chat, ChatWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: ChatWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Chat.PubSub,
  live_view: [signing_salt: "1Fd8A0CB"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :chat, Chat.Mailer, adapter: Swoosh.Adapters.Local

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :room_id, :message_id, :user_id, :message_ids, :error]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure esbuild
config :esbuild,
  version: "0.24.0",
  default: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# JWT/JWKS Authentication
config :chat, :auth,
  server_url: System.get_env("AUTH_SERVER_URL", "https://api.auth.jurunense.com"),
  jwks_uri: System.get_env("JWKS_URI"),
  issuer: System.get_env("JWT_ISSUER"),
  audience: System.get_env("JWT_AUDIENCE")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
