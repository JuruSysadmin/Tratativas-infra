defmodule Chat.Treatments.Reason do
  @moduledoc "Catalogued reason used to open a Tratativa."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "treatment_reasons" do
    field :code, :string
    field :label, :string
    field :active, :boolean, default: true
    field :sort_order, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(reason, attrs) do
    reason
    |> cast(attrs, [:code, :label, :active, :sort_order])
    |> validate_required([:code, :label, :active, :sort_order])
    |> unique_constraint(:code)
  end
end
