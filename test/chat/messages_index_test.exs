defmodule Chat.MessagesIndexTest do
  use Chat.DataCase, async: true

  alias Chat.Repo

  test "messages has a composite index for room timeline pagination" do
    %{rows: rows} =
      Repo.query!("""
      SELECT indexdef
      FROM pg_indexes
      WHERE schemaname = current_schema()
        AND tablename = 'messages'
      """)

    assert Enum.any?(rows, fn [definition] ->
             String.contains?(definition, "(room_id, inserted_at, id)")
           end)
  end
end
