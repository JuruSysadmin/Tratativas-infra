defmodule Chat.Repo.Migrations.AddIntakeFieldsToTreatments do
  use Ecto.Migration

  def up do
    create table(:treatment_reasons, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :label, :string, null: false
      add :active, :boolean, null: false, default: true
      add :sort_order, :integer, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:treatment_reasons, [:code])

    alter table(:treatments) do
      add :treatment_reason_id,
          references(:treatment_reasons, type: :binary_id, on_delete: :restrict)

      add :initial_description, :text
    end

    execute("""
    INSERT INTO treatment_reasons (id, code, label, active, sort_order, inserted_at, updated_at)
    VALUES
      (gen_random_uuid(), 'delivery', 'Entrega', true, 1, NOW(), NOW()),
      (gen_random_uuid(), 'stock', 'Estoque', true, 2, NOW(), NOW()),
      (gen_random_uuid(), 'billing', 'Faturamento', true, 3, NOW(), NOW()),
      (gen_random_uuid(), 'product', 'Produto', true, 4, NOW(), NOW()),
      (gen_random_uuid(), 'cancellation', 'Cancelamento', true, 5, NOW(), NOW()),
      (gen_random_uuid(), 'divergence', 'Divergência', true, 6, NOW(), NOW()),
      (gen_random_uuid(), 'other', 'Outro', true, 7, NOW(), NOW())
    ON CONFLICT (code) DO NOTHING
    """)
  end

  def down do
    alter table(:treatments) do
      remove :initial_description
      remove :treatment_reason_id
    end

    drop table(:treatment_reasons)
  end
end
