defmodule Chat.Repo do
  @moduledoc "Repository used by Chat for PostgreSQL persistence."

  use Ecto.Repo,
    otp_app: :chat,
    adapter: Ecto.Adapters.Postgres
end
