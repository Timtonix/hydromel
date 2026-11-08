defmodule Hydromel.Orders.Order do
  @moduledoc """
  Schema representing a customer reservation of 33cl and/or 75cl mead bottles
  for the Merhzinsa cooperative.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @payment_methods ~w(cash wero paypal)
  @payment_statuses ~w(pending paid)
  @pickup_statuses ~w(pending picked_up cancelled)

  schema "orders" do
    field :reference, :string
    field :first_name, :string
    field :last_name, :string
    field :email, :string
    field :qty_33cl, :integer, default: 0
    field :qty_75cl, :integer, default: 0
    field :unit_price_33cl_cents, :integer, default: 450
    field :unit_price_75cl_cents, :integer, default: 900
    field :total_cents, :integer, default: 0
    field :payment_method, :string, default: "wero"
    field :payment_status, :string, default: "pending"
    field :pickup_status, :string, default: "pending"
    field :pickup_comment, :string

    timestamps(type: :utc_datetime)
  end

  def payment_methods, do: @payment_methods
  def payment_statuses, do: @payment_statuses
  def pickup_statuses, do: @pickup_statuses

  @doc """
  Changeset for public reservation creation/validation.
  Programmatic fields (`reference`, `unit_price_*`, `total_cents`, statuses)
  are computed from `setting` and not cast from user input.
  """
  def changeset(order, attrs, setting) do
    order
    |> cast(attrs, [
      :first_name,
      :last_name,
      :email,
      :qty_33cl,
      :qty_75cl,
      :payment_method,
      :pickup_comment
    ])
    |> normalize_strings()
    |> normalize_quantities()
    |> validate_required([:first_name, :last_name, :email, :payment_method],
      message: "Ce champ est obligatoire"
    )
    |> validate_length(:first_name, min: 1, max: 100)
    |> validate_length(:last_name, min: 1, max: 100)
    |> validate_length(:pickup_comment, max: 1000)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "Format d'adresse e-mail invalide"
    )
    |> validate_inclusion(:payment_method, @payment_methods,
      message: "Moyen de paiement invalide"
    )
    |> validate_number(:qty_33cl, greater_than_or_equal_to: 0, less_than_or_equal_to: 500)
    |> validate_number(:qty_75cl, greater_than_or_equal_to: 0, less_than_or_equal_to: 500)
    |> validate_at_least_one_bottle()
    |> compute_pricing(setting)
    |> maybe_put_reference()
    |> unique_constraint(:reference)
  end

  @doc """
  Changeset for cooperative administration updates (statuses, quantities, comment).
  """
  def admin_changeset(order, attrs) do
    order
    |> cast(attrs, [
      :first_name,
      :last_name,
      :email,
      :qty_33cl,
      :qty_75cl,
      :payment_method,
      :payment_status,
      :pickup_status,
      :pickup_comment
    ])
    |> normalize_strings()
    |> normalize_quantities()
    |> validate_required([
      :first_name,
      :last_name,
      :email,
      :payment_method,
      :payment_status,
      :pickup_status
    ])
    |> validate_inclusion(:payment_method, @payment_methods)
    |> validate_inclusion(:payment_status, @payment_statuses)
    |> validate_inclusion(:pickup_status, @pickup_statuses)
    |> validate_number(:qty_33cl, greater_than_or_equal_to: 0)
    |> validate_number(:qty_75cl, greater_than_or_equal_to: 0)
    |> validate_at_least_one_bottle()
    |> recompute_total_from_existing_unit_prices()
  end

  defp normalize_strings(changeset) do
    changeset
    |> update_change(:first_name, &String.trim/1)
    |> update_change(:last_name, &String.trim/1)
    |> update_change(:email, fn email ->
      email |> String.trim() |> String.downcase()
    end)
  end

  defp normalize_quantities(changeset) do
    qty_33 = get_field(changeset, :qty_33cl) || 0
    qty_75 = get_field(changeset, :qty_75cl) || 0

    changeset
    |> put_change(:qty_33cl, max(qty_33, 0))
    |> put_change(:qty_75cl, max(qty_75, 0))
  end

  defp validate_at_least_one_bottle(changeset) do
    qty_33 = get_field(changeset, :qty_33cl) || 0
    qty_75 = get_field(changeset, :qty_75cl) || 0

    if qty_33 + qty_75 < 1 do
      add_error(
        changeset,
        :qty_33cl,
        "Veuillez sélectionner au moins une bouteille (33cl ou 75cl)"
      )
    else
      changeset
    end
  end

  defp compute_pricing(changeset, setting) do
    price_33 = (setting && setting.price_33cl_cents) || 450
    price_75 = (setting && setting.price_75cl_cents) || 900
    qty_33 = get_field(changeset, :qty_33cl) || 0
    qty_75 = get_field(changeset, :qty_75cl) || 0

    total = qty_33 * price_33 + qty_75 * price_75

    changeset
    |> put_change(:unit_price_33cl_cents, price_33)
    |> put_change(:unit_price_75cl_cents, price_75)
    |> put_change(:total_cents, total)
  end

  defp recompute_total_from_existing_unit_prices(changeset) do
    price_33 = get_field(changeset, :unit_price_33cl_cents) || 450
    price_75 = get_field(changeset, :unit_price_75cl_cents) || 900
    qty_33 = get_field(changeset, :qty_33cl) || 0
    qty_75 = get_field(changeset, :qty_75cl) || 0

    put_change(changeset, :total_cents, qty_33 * price_33 + qty_75 * price_75)
  end

  defp maybe_put_reference(changeset) do
    case get_field(changeset, :reference) do
      nil ->
        put_change(changeset, :reference, generate_reference())

      "" ->
        put_change(changeset, :reference, generate_reference())

      _ ->
        changeset
    end
  end

  @doc """
  Generates a human-friendly reservation reference such as `MERH-8F4K2A`.
  """
  def generate_reference do
    alphabet = ~c"23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

    suffix =
      for _ <- 1..6, into: "" do
        <<Enum.random(alphabet)>>
      end

    "MERH-" <> suffix
  end
end
