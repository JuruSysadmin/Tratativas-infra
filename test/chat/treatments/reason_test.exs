defmodule Chat.Treatments.ReasonTest do
  use Chat.DataCase, async: true

  alias Chat.Treatments.Reason

  test "stores a supported priority on the reason changeset" do
    changeset =
      Reason.changeset(%Reason{}, %{
        code: "wrong_address",
        label: "Entrega realizada no endereço errado",
        active: true,
        sort_order: 1,
        priority: "critical"
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :priority) == "critical"
  end

  test "rejects unsupported priorities" do
    changeset =
      Reason.changeset(%Reason{}, %{
        code: "wrong_address",
        label: "Entrega realizada no endereço errado",
        active: true,
        sort_order: 1,
        priority: "urgent"
      })

    refute changeset.valid?
    assert %{priority: [_message]} = errors_on(changeset)
  end
end
