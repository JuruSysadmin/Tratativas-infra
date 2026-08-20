import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/chat start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :chat, ChatWeb.Endpoint, server: true
end

config :chat, ChatWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "5000"))]

if config_env() == :dev do
  Dotenvy.source!([
    Path.expand("../.env", __DIR__),
    System.get_env()
  ])

  config :chat, :message_attachment_storage,
    bucket: Dotenvy.env!("MESSAGE_ATTACHMENT_S3_BUCKET", :string!, "juru-bucket-teste-2026"),
    region:
      Dotenvy.env!(
        "MESSAGE_ATTACHMENT_S3_REGION",
        :string,
        Dotenvy.env!(
          "AWS_REGION",
          :string,
          Dotenvy.env!("AWS_DEFAULT_REGION", :string, "us-east-1")
        )
      ),
    host: Dotenvy.env!("MESSAGE_ATTACHMENT_S3_HOST", :string, nil),
    scheme: Dotenvy.env!("MESSAGE_ATTACHMENT_S3_SCHEME", :string, nil),
    presign_ttl_seconds: 300

  ex_aws_config = [
    access_key_id: Dotenvy.env!("AWS_ACCESS_KEY_ID", :string!),
    secret_access_key: Dotenvy.env!("AWS_SECRET_ACCESS_KEY", :string!)
  ]

  ex_aws_config =
    case Dotenvy.env!("AWS_SESSION_TOKEN", :string, nil) do
      nil -> ex_aws_config
      "" -> ex_aws_config
      token -> Keyword.put(ex_aws_config, :security_token, token)
    end

  config :ex_aws, ex_aws_config
end

if config_env() != :dev and System.get_env("AWS_SESSION_TOKEN") not in [nil, ""] do
  config :ex_aws, security_token: System.get_env("AWS_SESSION_TOKEN")
end

if config_env() == :prod do
  cors_origins =
    System.get_env("CORS_ORIGINS", "https://vm.jurunense.com")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)

  config :chat, :cors_origins, cors_origins

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  attachment_bucket =
    System.get_env("MESSAGE_ATTACHMENT_S3_BUCKET") ||
      raise "MESSAGE_ATTACHMENT_S3_BUCKET is missing"

  config :chat, :message_attachment_storage,
    bucket: attachment_bucket,
    region:
      System.get_env("MESSAGE_ATTACHMENT_S3_REGION") ||
        System.get_env("AWS_REGION") ||
        System.get_env("AWS_DEFAULT_REGION", "us-east-1"),
    host: System.get_env("MESSAGE_ATTACHMENT_S3_HOST"),
    scheme: System.get_env("MESSAGE_ATTACHMENT_S3_SCHEME"),
    presign_ttl_seconds: 300

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :chat, Chat.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  jwks_uri = System.get_env("JWKS_URI") || raise "JWKS_URI is missing"
  jwt_issuer = System.get_env("JWT_ISSUER") || raise "JWT_ISSUER is missing"
  jwt_audience = System.get_env("JWT_AUDIENCE") || raise "JWT_AUDIENCE is missing"

  config :chat, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :chat, ChatWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # JWT/JWKS Authentication
  config :chat, :auth,
    server_url: System.get_env("AUTH_SERVER_URL", "https://api.auth.jurunense.com"),
    jwks_uri: jwks_uri,
    issuer: jwt_issuer,
    audience: jwt_audience

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :chat, ChatWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :chat, ChatWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :chat, Chat.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
