defmodule Chat.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    base_children = [
      ChatWeb.Telemetry,
      Chat.Repo,
      {Oban, Application.fetch_env!(:chat, Oban)},
      {DNSCluster, query: Application.get_env(:chat, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Chat.PubSub},
      ChatWeb.Presence,
      Chat.Rooms.MembershipCache,
      # Start a worker by calling: Chat.Worker.start_link(arg)
      # {Chat.Worker, []},
      # Start to serve requests, typically the last entry
      ChatWeb.Endpoint
    ]

    # Add JWKS strategy only if JWKS URL is configured
    children =
      if Application.get_env(:chat, :auth)[:jwks_uri] do
        base_children ++ [Chat.Auth.JwksStrategy]
      else
        base_children
      end

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Chat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ChatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
