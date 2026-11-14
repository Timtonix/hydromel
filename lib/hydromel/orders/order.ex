defmodule Hydromel.Orders.Order do
  @moduledoc """
  Schema representing a customer reservation of 33cl and/or 75cl mead bottles
  for the Merhzinsa cooperative, including optional referral code discount
  (-1€/bottle or 1st 75cl bottle + label free for the cooperative member) and
  custom bottle label (+1€/bottle with uploaded photo & text).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Hydromel.Orders.CoopMember

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
    field :unit_price_33cl_cents, :integer, default: 350
    field :unit_price_75cl_cents, :integer, default: 600
    field :discount_cents, :integer, default: 0
    field :custom_label, :boolean, default: false
    field :custom_label_fee_cents, :integer, default: 0
    field :custom_label_text, :string
    field :custom_label_filename, :string
    field :custom_label_original_name, :string
    field :custom_label_content_type, :string
    field :total_cents, :integer, default: 0
    field :payment_method, :string, default: "wero"
    field :payment_status, :string, default: "pending"
    field :pickup_status, :string, default: "pending"
    field :pickup_comment, :string
    field :referral_code_used, :string
    field :adult_certified, :boolean, virtual: true, default: true

    belongs_to :coop_member, CoopMember

    timestamps(type: :utc_datetime)
  end

  def payment_methods, do: @payment_methods
  def payment_statuses, do: @payment_statuses
  def pickup_statuses, do: @pickup_statuses

  @doc """
  Changeset for public reservation creation/validation.
  When `free_member_bottle?` is `true` (first order using a cooperative member's
  code), 1 bottle of 75cl and its custom label are 100% free (0€).
  Subsequent orders with that code receive the `-1€/bottle` referral discount.
  """
  def changeset(order, attrs, setting, coop_member \\ nil, free_member_bottle? \\ false) do
    order
    |> cast(attrs, [
      :first_name,
      :last_name,
      :email,
      :qty_33cl,
      :qty_75cl,
      :payment_method,
      :pickup_comment,
      :referral_code_used,
      :custom_label,
      :custom_label_text,
      :adult_certified
    ])
    |> normalize_strings()
    |> normalize_quantities()
    |> validate_required([:first_name, :last_name, :email, :payment_method],
      message: "Ce champ est obligatoire"
    )
    |> validate_acceptance(:adult_certified,
      message: "Vous devez certifier être majeur(e) (18 ans et plus)"
    )
    |> validate_length(:first_name, min: 1, max: 100)
    |> validate_length(:last_name, min: 1, max: 100)
    |> validate_length(:pickup_comment, max: 1000)
    |> validate_length(:custom_label_text, max: 300)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "Format d'adresse e-mail invalide"
    )
    |> validate_inclusion(:payment_method, @payment_methods,
      message: "Moyen de paiement invalide"
    )
    |> validate_number(:qty_33cl, greater_than_or_equal_to: 0, less_than_or_equal_to: 500)
    |> validate_number(:qty_75cl, greater_than_or_equal_to: 0, less_than_or_equal_to: 500)
    |> validate_at_least_one_bottle()
    |> apply_referral(coop_member)
    |> compute_pricing(setting, coop_member, free_member_bottle?)
    |> maybe_mark_free_order_paid()
    |> maybe_put_reference()
    |> unique_constraint(:reference)
  end

  @doc """
  Attaches uploaded custom label file metadata to an order changeset.
  """
  def put_label_upload(changeset, nil), do: changeset

  def put_label_upload(changeset, %{
        filename: filename,
        original_name: original_name,
        content_type: content_type
      }) do
    changeset
    |> put_change(:custom_label_filename, filename)
    |> put_change(:custom_label_original_name, original_name)
    |> put_change(:custom_label_content_type, content_type)
  end

  @doc """
  Validates custom label requirements on submission when `custom_label` is enabled.
  """
  def validate_custom_label_submission(changeset) do
    if get_field(changeset, :custom_label) == true do
      text = get_field(changeset, :custom_label_text) || ""
      filename = get_field(changeset, :custom_label_filename)

      changeset =
        if String.trim(text) == "" do
          add_error(
            changeset,
            :custom_label_text,
            "Veuillez saisir le texte à inscrire sur votre étiquette personnalisée"
          )
        else
          changeset
        end

      if is_nil(filename) or filename == "" do
        add_error(
          changeset,
          :custom_label,
          "Veuillez importer une image/photo pour votre étiquette personnalisée"
        )
      else
        changeset
      end
    else
      changeset
    end
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
    |> update_change(:referral_code_used, fn code ->
      if is_binary(code), do: CoopMember.sanitize_code(code), else: code
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

  defp apply_referral(changeset, %CoopMember{} = member) do
    changeset
    |> put_change(:coop_member_id, member.id)
    |> put_change(:referral_code_used, member.referral_code)
  end

  defp apply_referral(changeset, nil) do
    entered_code = get_field(changeset, :referral_code_used)

    if is_binary(entered_code) and String.trim(entered_code) != "" do
      changeset
      |> put_change(:coop_member_id, nil)
      |> add_error(:referral_code_used, "Code de parrainage inconnu")
    else
      changeset
      |> put_change(:coop_member_id, nil)
      |> put_change(:referral_code_used, nil)
    end
  end

  defp compute_pricing(changeset, setting, coop_member, free_member_bottle?) do
    price_33 = (setting && setting.price_33cl_cents) || 350
    price_75 = (setting && setting.price_75cl_cents) || 600
    discount_unit = (setting && setting.referral_discount_cents) || 100
    label_unit = (setting && setting.custom_label_price_cents) || 100

    qty_33 = max(get_field(changeset, :qty_33cl) || 0, 0)
    qty_75 = max(get_field(changeset, :qty_75cl) || 0, 0)
    total_bottles = qty_33 + qty_75
    custom_label? = get_field(changeset, :custom_label) == true

    base_cents = qty_33 * price_33 + qty_75 * price_75

    {discount_cents, label_fee_cents} =
      cond do
        coop_member != nil and free_member_bottle? and qty_75 >= 1 ->
          # Member's 1st order: 1 bottle of 75cl is 100% free, extra bottles get -1€ each,
          # and the custom label for that free 75cl bottle is also free!
          extra_bottles = max(total_bottles - 1, 0)
          member_discount = price_75 + extra_bottles * discount_unit
          fee = if custom_label?, do: extra_bottles * label_unit, else: 0
          {member_discount, fee}

        coop_member != nil ->
          {total_bottles * discount_unit,
           if(custom_label?, do: total_bottles * label_unit, else: 0)}

        true ->
          {0, if(custom_label?, do: total_bottles * label_unit, else: 0)}
      end

    total = max(base_cents - discount_cents + label_fee_cents, 0)

    changeset
    |> put_change(:unit_price_33cl_cents, price_33)
    |> put_change(:unit_price_75cl_cents, price_75)
    |> put_change(:discount_cents, discount_cents)
    |> put_change(:custom_label_fee_cents, label_fee_cents)
    |> put_change(:total_cents, total)
  end

  defp maybe_mark_free_order_paid(changeset) do
    total_bottles =
      (get_field(changeset, :qty_33cl) || 0) + (get_field(changeset, :qty_75cl) || 0)

    total_cents = get_field(changeset, :total_cents)

    if total_bottles > 0 and total_cents == 0 do
      put_change(changeset, :payment_status, "paid")
    else
      changeset
    end
  end

  defp recompute_total_from_existing_unit_prices(changeset) do
    price_33 = get_field(changeset, :unit_price_33cl_cents) || 350
    price_75 = get_field(changeset, :unit_price_75cl_cents) || 600
    qty_33 = get_field(changeset, :qty_33cl) || 0
    qty_75 = get_field(changeset, :qty_75cl) || 0
    discount_cents = get_field(changeset, :discount_cents) || 0
    label_fee_cents = get_field(changeset, :custom_label_fee_cents) || 0

    base = qty_33 * price_33 + qty_75 * price_75
    put_change(changeset, :total_cents, max(base - discount_cents + label_fee_cents, 0))
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
