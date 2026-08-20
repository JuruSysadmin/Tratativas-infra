ExUnit.start()

Application.ensure_all_started(:chat)

Ecto.Adapters.SQL.Sandbox.mode(Chat.Repo, :manual)
