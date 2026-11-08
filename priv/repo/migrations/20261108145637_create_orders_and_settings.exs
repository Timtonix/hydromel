defmodule Hydromel.Repo.Migrations.CreateOrdersAndSettings do
  use Ecto.Migration

  def change do
    create table(:coop_settings) do
      add :key, :string, null: false, default: "default"
      add :price_33cl_cents, :integer, null: false, default: 450
      add :price_75cl_cents, :integer, null: false, default: 900
      add :stock_33cl, :integer
      add :stock_75cl, :integer
      add :sales_open, :boolean, null: false, default: true
      add :closed_message, :text
      add :wero_instructions, :text
      add :paypal_url, :string
      add :paypal_instructions, :text
      add :cash_instructions, :text
      add :pickup_info, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:coop_settings, [:key])

    create table(:orders) do
      add :reference, :string, null: false
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :email, :string, null: false
      add :qty_33cl, :integer, null: false, default: 0
      add :qty_75cl, :integer, null: false, default: 0
      add :unit_price_33cl_cents, :integer, null: false, default: 450
      add :unit_price_75cl_cents, :integer, null: false, default: 900
      add :total_cents, :integer, null: false, default: 0
      add :payment_method, :string, null: false, default: "wero"
      add :payment_status, :string, null: false, default: "pending"
      add :pickup_status, :string, null: false, default: "pending"
      add :pickup_comment, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:orders, [:reference])
    create index(:orders, [:email])
    create index(:orders, [:payment_status])
    create index(:orders, [:pickup_status])
  end
end
