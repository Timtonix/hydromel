defmodule Hydromel.Orders.CoopMember do
  @moduledoc """
  Schema representing a member of the Merhzinsa cooperative and their unique
  referral code (`referral_code`) used to grant a 1€/bottle discount and track
  referred liters on the cooperative leaderboard.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Hydromel.Orders.Order

  schema "coop_members" do
    field :name, :string
    field :referral_code, :string

    has_many :orders, Order, foreign_key: :coop_member_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(member, attrs) do
    member
    |> cast(attrs, [:name, :referral_code])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name], message: "Le nom du membre est obligatoire")
    |> validate_length(:name, min: 2, max: 80)
    |> normalize_or_generate_referral_code()
    |> validate_required([:referral_code], message: "Le code de parrainage est obligatoire")
    |> validate_length(:referral_code, min: 2, max: 30)
    |> unique_constraint(:referral_code,
      message: "Ce code de parrainage est déjà utilisé par un autre membre"
    )
  end

  defp normalize_or_generate_referral_code(changeset) do
    code = get_field(changeset, :referral_code)
    name = get_field(changeset, :name)

    cleaned_code =
      if is_binary(code) do
        sanitize_code(code)
      else
        ""
      end

    cond do
      cleaned_code != "" ->
        put_change(changeset, :referral_code, cleaned_code)

      is_binary(name) and String.trim(name) != "" ->
        put_change(changeset, :referral_code, generate_code_from_name(name))

      true ->
        changeset
    end
  end

  @doc """
  Normalizes a user-entered referral code (uppercase, ASCII alphanumeric/hyphen).
  """
  def sanitize_code(str) when is_binary(str) do
    str
    |> String.trim()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^A-Za-z0-9_-]/u, "")
    |> String.upcase()
  end

  def sanitize_code(_), do: ""

  defp generate_code_from_name(name) do
    prefix =
      name
      |> sanitize_code()
      |> String.slice(0, 8)

    base = if prefix == "", do: "MERH", else: prefix
    suffix = Enum.random(10..99)
    "#{base}#{suffix}"
  end
end
