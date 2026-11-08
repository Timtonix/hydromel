defmodule Hydromel.Orders do
  @moduledoc """
  The Orders context manages mead bottle reservations (`Order`), cooperative
  settings (`Setting`), real-time PubSub broadcasts, statistics, and CSV exports.
  """

  import Ecto.Query, warn: false
  alias Hydromel.Repo
  alias Hydromel.Orders.{Order, OrderNotifier, Setting}

  @pubsub_topic "orders"

  @doc """
  Subscribes the caller process to real-time order and setting updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Hydromel.PubSub, @pubsub_topic)
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Hydromel.PubSub, @pubsub_topic, message)
  end

  # ============================================================================
  # Cooperative Settings
  # ============================================================================

  @doc """
  Returns the singleton cooperative settings record, creating it with default
  values if it does not exist yet.
  """
  def get_setting! do
    case Repo.get_by(Setting, key: "default") do
      %Setting{} = setting ->
        populate_virtual_euros(setting)

      nil ->
        %Setting{key: "default"}
        |> Setting.changeset(%{})
        |> Repo.insert!(on_conflict: :nothing, conflict_target: :key)

        Repo.get_by!(Setting, key: "default")
        |> populate_virtual_euros()
    end
  end

  defp populate_virtual_euros(%Setting{} = setting) do
    %{
      setting
      | price_33cl_euros: Setting.format_cents_input(setting.price_33cl_cents),
        price_75cl_euros: Setting.format_cents_input(setting.price_75cl_cents)
    }
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking setting changes.
  """
  def change_setting(%Setting{} = setting, attrs \\ %{}) do
    Setting.changeset(populate_virtual_euros(setting), attrs)
  end

  @doc """
  Updates the cooperative settings and broadcasts `{:setting_updated, setting}`.
  """
  def update_setting(%Setting{} = setting, attrs) do
    case setting |> Setting.changeset(attrs) |> Repo.update() do
      {:ok, updated} ->
        updated = populate_virtual_euros(updated)
        broadcast({:setting_updated, updated})
        {:ok, updated}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  # ============================================================================
  # Orders
  # ============================================================================

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking public order changes.
  """
  def change_order(%Order{} = order, attrs \\ %{}, setting \\ nil) do
    setting = setting || get_setting!()
    Order.changeset(order, attrs, setting)
  end

  @doc """
  Creates a new order after validating sales status and remaining bottle stock,
  delivers the summary email via `OrderNotifier`, and broadcasts the creation.
  """
  def create_order(attrs) do
    setting = get_setting!()

    changeset =
      %Order{}
      |> Order.changeset(attrs, setting)
      |> validate_sales_open(setting)
      |> validate_stock_availability(setting)

    case Repo.insert(changeset) do
      {:ok, order} ->
        _ = OrderNotifier.deliver_order_confirmation(order, setting)
        broadcast({:order_created, order})
        {:ok, order}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  defp validate_sales_open(changeset, %Setting{sales_open: true}), do: changeset

  defp validate_sales_open(changeset, %Setting{sales_open: false, closed_message: msg}) do
    Ecto.Changeset.add_error(
      changeset,
      :qty_33cl,
      msg || "La prévente est actuellement fermée."
    )
  end

  defp validate_stock_availability(changeset, %Setting{} = setting) do
    if changeset.valid? do
      reserved = reserved_quantities()
      req_33 = Ecto.Changeset.get_field(changeset, :qty_33cl) || 0
      req_75 = Ecto.Changeset.get_field(changeset, :qty_75cl) || 0

      changeset
      |> check_format_stock(:qty_33cl, req_33, setting.stock_33cl, reserved.qty_33cl, "33cl")
      |> check_format_stock(:qty_75cl, req_75, setting.stock_75cl, reserved.qty_75cl, "75cl")
    else
      changeset
    end
  end

  defp check_format_stock(changeset, _field, _req, nil, _reserved, _label), do: changeset
  defp check_format_stock(changeset, _field, 0, _max_stock, _reserved, _label), do: changeset

  defp check_format_stock(changeset, field, req, max_stock, reserved, label) do
    remaining = max(max_stock - reserved, 0)

    if req > remaining do
      Ecto.Changeset.add_error(
        changeset,
        field,
        "Stock insuffisant en #{label} (il reste #{remaining} bouteille(s) disponible(s))"
      )
    else
      changeset
    end
  end

  @doc """
  Lists orders ordered by newest first, with optional search and status filters.
  """
  def list_orders(filters \\ %{}) do
    Order
    |> apply_search_filter(Map.get(filters, :search) || Map.get(filters, "search"))
    |> apply_status_filter(Map.get(filters, :filter) || Map.get(filters, "filter"))
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> Repo.all()
  end

  defp apply_search_filter(query, nil), do: query
  defp apply_search_filter(query, ""), do: query

  defp apply_search_filter(query, search) when is_binary(search) do
    term = "%#{String.trim(search)}%"

    from o in query,
      where:
        ilike(o.first_name, ^term) or
          ilike(o.last_name, ^term) or
          ilike(o.email, ^term) or
          ilike(o.reference, ^term) or
          ilike(o.pickup_comment, ^term)
  end

  defp apply_status_filter(query, "unpaid") do
    from o in query, where: o.payment_status == "pending" and o.pickup_status != "cancelled"
  end

  defp apply_status_filter(query, "paid") do
    from o in query, where: o.payment_status == "paid" and o.pickup_status != "cancelled"
  end

  defp apply_status_filter(query, "to_pickup") do
    from o in query, where: o.pickup_status == "pending"
  end

  defp apply_status_filter(query, "picked_up") do
    from o in query, where: o.pickup_status == "picked_up"
  end

  defp apply_status_filter(query, "cancelled") do
    from o in query, where: o.pickup_status == "cancelled"
  end

  defp apply_status_filter(query, _all), do: query

  @doc """
  Gets a single order by ID. Raises `Ecto.NoResultsError` if not found.
  """
  def get_order!(id), do: Repo.get!(Order, id)

  @doc """
  Gets a single order by reference.
  """
  def get_order_by_reference(reference) when is_binary(reference) do
    Repo.get_by(Order, reference: String.trim(reference) |> String.upcase())
  end

  @doc """
  Toggles the payment status of an order between `"pending"` and `"paid"`.
  """
  def toggle_payment_status(%Order{} = order) do
    next_status = if order.payment_status == "paid", do: "pending", else: "paid"
    update_order_admin(order, %{payment_status: next_status})
  end

  @doc """
  Toggles the pickup status of an order between `"pending"` and `"picked_up"`.
  """
  def toggle_pickup_status(%Order{} = order) do
    next_status = if order.pickup_status == "picked_up", do: "pending", else: "picked_up"
    update_order_admin(order, %{pickup_status: next_status})
  end

  @doc """
  Cancels an order so its bottles are released back into available stock.
  """
  def cancel_order(%Order{} = order) do
    update_order_admin(order, %{pickup_status: "cancelled"})
  end

  @doc """
  Restores a cancelled order back to `"pending"` pickup status.
  """
  def restore_order(%Order{} = order) do
    update_order_admin(order, %{pickup_status: "pending"})
  end

  @doc """
  Updates an order with administrative attributes.
  """
  def update_order_admin(%Order{} = order, attrs) do
    case order |> Order.admin_changeset(attrs) |> Repo.update() do
      {:ok, updated} ->
        broadcast({:order_updated, updated})
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # ============================================================================
  # Statistics & Stock Calculation
  # ============================================================================

  @doc """
  Returns total reserved quantities across all non-cancelled orders.
  """
  def reserved_quantities do
    query =
      from o in Order,
        where: o.pickup_status != "cancelled",
        select: %{
          qty_33cl: coalesce(sum(o.qty_33cl), 0),
          qty_75cl: coalesce(sum(o.qty_75cl), 0)
        }

    Repo.one(query) || %{qty_33cl: 0, qty_75cl: 0}
  end

  @doc """
  Computes comprehensive pre-sale statistics for the cooperative dashboard and
  public stock indicators.
  """
  def get_stats(setting \\ nil) do
    setting = setting || get_setting!()

    active_stats =
      Repo.one(
        from o in Order,
          where: o.pickup_status != "cancelled",
          select: %{
            active_orders_count: count(o.id),
            qty_33cl: coalesce(sum(o.qty_33cl), 0),
            qty_75cl: coalesce(sum(o.qty_75cl), 0),
            expected_cents: coalesce(sum(o.total_cents), 0)
          }
      ) || %{active_orders_count: 0, qty_33cl: 0, qty_75cl: 0, expected_cents: 0}

    paid_cents =
      Repo.one(
        from o in Order,
          where: o.pickup_status != "cancelled" and o.payment_status == "paid",
          select: coalesce(sum(o.total_cents), 0)
      ) || 0

    picked_up_count =
      Repo.one(
        from o in Order,
          where: o.pickup_status == "picked_up",
          select: count(o.id)
      ) || 0

    remaining_33cl =
      if is_integer(setting.stock_33cl) do
        max(setting.stock_33cl - active_stats.qty_33cl, 0)
      else
        nil
      end

    remaining_75cl =
      if is_integer(setting.stock_75cl) do
        max(setting.stock_75cl - active_stats.qty_75cl, 0)
      else
        nil
      end

    total_liters =
      Float.round(active_stats.qty_33cl * 0.33 + active_stats.qty_75cl * 0.75, 2)

    %{
      active_orders_count: active_stats.active_orders_count,
      picked_up_count: picked_up_count,
      qty_33cl: active_stats.qty_33cl,
      qty_75cl: active_stats.qty_75cl,
      remaining_33cl: remaining_33cl,
      remaining_75cl: remaining_75cl,
      total_liters: total_liters,
      expected_cents: active_stats.expected_cents,
      paid_cents: paid_cents
    }
  end

  # ============================================================================
  # CSV Export
  # ============================================================================

  @doc """
  Exports all orders as a UTF-8 CSV string (with BOM for Excel/LibreOffice).
  """
  def export_orders_csv do
    orders = list_orders()

    headers = [
      "Référence",
      "Date",
      "Prénom",
      "Nom",
      "Email",
      "Bouteilles 33cl",
      "Bouteilles 75cl",
      "Total (€)",
      "Moyen de paiement",
      "Statut paiement",
      "Statut retrait",
      "Commentaire retrait"
    ]

    rows =
      Enum.map(orders, fn o ->
        [
          o.reference,
          Calendar.strftime(o.inserted_at, "%Y-%m-%d %H:%M"),
          o.first_name,
          o.last_name,
          o.email,
          Integer.to_string(o.qty_33cl),
          Integer.to_string(o.qty_75cl),
          :erlang.float_to_binary(o.total_cents / 100, decimals: 2),
          OrderNotifier.payment_method_label(o.payment_method),
          if(o.payment_status == "paid", do: "Payé", else: "En attente"),
          pickup_status_label(o.pickup_status),
          o.pickup_comment || ""
        ]
      end)

    bom = <<0xEF, 0xBB, 0xBF>>

    csv_content =
      [headers | rows]
      |> Enum.map(&encode_csv_row/1)
      |> Enum.join("\r\n")

    bom <> csv_content <> "\r\n"
  end

  def pickup_status_label("picked_up"), do: "Récupéré"
  def pickup_status_label("cancelled"), do: "Annulé"
  def pickup_status_label(_), do: "À récupérer"

  defp encode_csv_row(fields) do
    fields
    |> Enum.map(fn field ->
      str = to_string(field || "")
      escaped = String.replace(str, "\"", "\"\"")
      "\"#{escaped}\""
    end)
    |> Enum.join(";")
  end
end
