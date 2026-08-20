defmodule ChatWeb.RoomModalComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias ChatWeb.RoomModalComponent

  test "renders an actionable empty state when room search has no results" do
    html =
      render_component(&RoomModalComponent.room_modal/1, %{
        dialog: :explore,
        available_rooms: [],
        room_search: "inexistente"
      })

    assert html =~ "Nenhuma sala corresponde a"
    assert html =~ "Limpar busca"
    assert html =~ ~s(phx-click="clear_room_search")
    assert html =~ ~s(aria-live="polite")
  end
end
