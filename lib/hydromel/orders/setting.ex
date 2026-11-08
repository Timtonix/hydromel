defmodule Hydromel.Orders.Setting do
  @moduledoc """
  Schema representing the cooperative's configurable pre-sale parameters:
  prices, available stock limits, payment instructions (Cash, Wero, PayPal),
  and whether the pre-sale is currently open.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "coop_settings" do
    field :key, :string, default: "default"
    field :price_33cl_cents, :integer, default: 450
    field :price_75cl_cents, :integer, default: 900
    field :stock_33cl, :integer
    field :stock_75cl, :integer
    field :sales_open, :boolean, default: true

    field :closed_message, :string,
      default:
        "La prévente est actuellement fermée. Merci pour votre soutien à la coopérative Merhzinsa !"

    field :wero_instructions, :string,
      default:
        "Effectuez votre virement Wero en indiquant impérativement la référence de votre commande en commentaire."

    field :paypal_url, :string, default: ""

    field :paypal_instructions, :string,
      default:
        "Envoyez le règlement via PayPal (option « Entre proches ») en précisant votre référence de commande."

    field :cash_instructions, :string,
      default:
        "Réglez directement en espèces lors du retrait de vos bouteilles (merci de prévoir l'appoint si possible)."

    field :pickup_info, :string,
      default:
        "Précisez en commentaire comment vous souhaitez récupérer votre commande (lieu, créneau ou membre de la coopérative)."

    field :price_33cl_euros, :string, virtual: true
    field :price_75cl_euros, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [
      :price_33cl_cents,
      :price_75cl_cents,
      :price_33cl_euros,
      :price_75cl_euros,
      :stock_33cl,
      :stock_75cl,
      :sales_open,
      :closed_message,
      :wero_instructions,
      :paypal_url,
      :paypal_instructions,
      :cash_instructions,
      :pickup_info
    ])
    |> maybe_convert_euros_to_cents(:price_33cl_euros, :price_33cl_cents)
    |> maybe_convert_euros_to_cents(:price_75cl_euros, :price_75cl_cents)
    |> validate_required([:price_33cl_cents, :price_75cl_cents, :sales_open])
    |> validate_number(:price_33cl_cents, greater_than_or_equal_to: 0)
    |> validate_number(:price_75cl_cents, greater_than_or_equal_to: 0)
    |> validate_number(:stock_33cl, greater_than_or_equal_to: 0)
    |> validate_number(:stock_75cl, greater_than_or_equal_to: 0)
    |> unique_constraint(:key)
  end

  defp maybe_convert_euros_to_cents(changeset, euro_field, cents_field) do
    case get_change(changeset, euro_field) do
      nil ->
        changeset

      val when is_binary(val) ->
        normalized =
          val
          |> String.trim()
          |> String.replace(",", ".")

        case Float.parse(normalized) do
          {float_val, ""} when float_val >= 0 ->
            put_change(changeset, cents_field, round(float_val * 100))

          _ ->
            add_error(changeset, euro_field, "format de prix invalide (ex: 4.50)")
        end
    end
  end

  @doc """
  Formats cents as a French euro string for input fields (e.g. `450` -> `"4.50"`).
  """
  def format_cents_input(cents) when is_integer(cents) do
    :erlang.float_to_binary(cents / 100, decimals: 2)
  end

  def format_cents_input(_), do: "0.00"
end
