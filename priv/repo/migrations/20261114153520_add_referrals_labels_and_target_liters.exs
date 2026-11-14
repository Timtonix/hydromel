defmodule Hydromel.Repo.Migrations.AddReferralsLabelsAndTargetLiters do
  use Ecto.Migration

  def change do
    create table(:coop_members) do
      add :name, :string, null: false
      add :referral_code, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:coop_members, [:referral_code])

    alter table(:coop_settings) do
      add :target_liters, :float, null: false, default: 35.0
      add :referral_discount_cents, :integer, null: false, default: 100
      add :custom_label_price_cents, :integer, null: false, default: 100
      add :sample_label_filename, :string
    end

    execute(
      "UPDATE coop_settings SET price_75cl_cents = 600, price_33cl_cents = 350 WHERE key = 'default' AND price_75cl_cents = 900",
      "SELECT 1"
    )

    alter table(:orders) do
      add :coop_member_id, references(:coop_members, on_delete: :nilify_all)
      add :referral_code_used, :string
      add :discount_cents, :integer, null: false, default: 0
      add :custom_label, :boolean, null: false, default: false
      add :custom_label_fee_cents, :integer, null: false, default: 0
      add :custom_label_text, :text
      add :custom_label_filename, :string
      add :custom_label_original_name, :string
      add :custom_label_content_type, :string
    end

    create index(:orders, [:coop_member_id])
  end
end
