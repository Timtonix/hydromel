defmodule Hydromel.Orders do
  @moduledoc """
  The Orders context manages mead bottle reservations (`Order`), cooperative
  members & referral codes (`CoopMember`), cooperative settings (`Setting`),
  uploaded custom label images on disk, real-time PubSub broadcasts,
  leaderboard rankings, statistics, and CSV exports.
  """

  import Ecto.Query, warn: false
  alias Hydromel.Repo
  alias Hydromel.Orders.{CoopMember, Order, OrderNotifier, Setting}

  @pubsub_topic "orders"

  @doc """
  Subscribes the caller process to real-time order, member, and setting updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Hydromel.PubSub, @pubsub_topic)
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Hydromel.PubSub, @pubsub_topic, message)
  end

  # ============================================================================
  # Uploads Directory (Dokploy Volume Compatible)
  # ============================================================================

  @doc """
  Returns the base directory where uploaded label images are stored on disk.
  In production on Dokploy, mount a volume at `/app/uploads` (configured via
  `UPLOADS_DIR`).
  """
  def uploads_dir do
    Application.get_env(:hydromel, :uploads_dir) ||
      Path.join(:code.priv_dir(:hydromel), "uploads")
  end

  def labels_dir do
    dir = Path.join(uploads_dir(), "labels")
    File.mkdir_p!(dir)
    dir
  end

  @doc """
  Copies a temporary uploaded file into the persistent `labels/` directory and
  returns metadata map `%{filename, original_name, content_type}`.
  """
  def store_label_file(source_path, original_name, content_type) do
    ext = Path.extname(original_name || ".png") |> String.downcase()
    safe_ext = if ext in [".jpg", ".jpeg", ".png", ".webp", ".gif"], do: ext, else: ".png"
    unique_name = "label-#{System.unique_integer([:positive, :monotonic])}#{safe_ext}"
    dest_path = Path.join(labels_dir(), unique_name)

    File.cp!(source_path, dest_path)

    %{
      filename: unique_name,
      original_name: original_name || unique_name,
      content_type: content_type || "image/png"
    }
  end

  @doc """
  Stores a custom sample label image uploaded by the cooperative admin.
  """
  def store_sample_label_file(source_path, original_name) do
    ext = Path.extname(original_name || ".png") |> String.downcase()
    safe_ext = if ext in [".jpg", ".jpeg", ".png", ".webp", ".svg"], do: ext, else: ".png"
    unique_name = "sample-etiquette-#{System.unique_integer([:positive, :monotonic])}#{safe_ext}"
    dest_path = Path.join(labels_dir(), unique_name)

    File.cp!(source_path, dest_path)
    unique_name
  end

  @doc """
  Returns the absolute path on disk for a stored label filename, ensuring no path
  traversal.
  """
  def label_file_path(filename) when is_binary(filename) do
    safe_base = Path.basename(filename)
    Path.join(labels_dir(), safe_base)
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
  # Cooperative Members & Leaderboard
  # ============================================================================

  @doc """
  Lists all cooperative members ordered alphabetically by name.
  """
  def list_coop_members do
    Repo.all(from m in CoopMember, order_by: [asc: m.name])
  end

  @doc """
  Gets a single cooperative member by ID.
  """
  def get_coop_member!(id), do: Repo.get!(CoopMember, id)

  @doc """
  Finds a cooperative member by their referral code (case-insensitive).
  """
  def get_coop_member_by_code(nil), do: nil
  def get_coop_member_by_code(""), do: nil

  def get_coop_member_by_code(code) when is_binary(code) do
    normalized = CoopMember.sanitize_code(code)

    if normalized == "" do
      nil
    else
      Repo.get_by(CoopMember, referral_code: normalized)
    end
  end

  @doc """
  Returns a changeset for creating/editing a cooperative member.
  """
  def change_coop_member(%CoopMember{} = member, attrs \\ %{}) do
    CoopMember.changeset(member, attrs)
  end

  @doc """
  Creates a new cooperative member with a unique referral code.
  """
  def create_coop_member(attrs) do
    case %CoopMember{} |> CoopMember.changeset(attrs) |> Repo.insert() do
      {:ok, member} ->
        broadcast({:members_updated, member})
        {:ok, member}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Deletes a cooperative member.
  """
  def delete_coop_member(%CoopMember{} = member) do
    {:ok, deleted} = Repo.delete(member)
    broadcast({:members_updated, deleted})
    {:ok, deleted}
  end

  @doc """
  Computes the cooperative referral leaderboard sorted by total liters sold
  descending.
  """
  def list_leaderboard do
    members = list_coop_members()

    active_orders_by_member =
      Repo.all(
        from o in Order,
          where: o.pickup_status != "cancelled" and not is_nil(o.coop_member_id),
          group_by: o.coop_member_id,
          select: {
            o.coop_member_id,
            %{
              orders_count: count(o.id),
              qty_33cl: coalesce(sum(o.qty_33cl), 0),
              qty_75cl: coalesce(sum(o.qty_75cl), 0),
              revenue_cents: coalesce(sum(o.total_cents), 0)
            }
          }
      )
      |> Map.new()

    members
    |> Enum.map(fn member ->
      agg =
        Map.get(active_orders_by_member, member.id, %{
          orders_count: 0,
          qty_33cl: 0,
          qty_75cl: 0,
          revenue_cents: 0
        })

      liters = Float.round(agg.qty_33cl * 0.33 + agg.qty_75cl * 0.75, 2)
      bottles = agg.qty_33cl + agg.qty_75cl

      %{
        member: member,
        member_bottle_claimed?: agg.orders_count > 0,
        orders_count: agg.orders_count,
        qty_33cl: agg.qty_33cl,
        qty_75cl: agg.qty_75cl,
        total_bottles: bottles,
        total_liters: liters,
        revenue_cents: agg.revenue_cents
      }
    end)
    |> Enum.sort_by(fn entry ->
      {-entry.total_liters, -entry.total_bottles, entry.member.name}
    end)
  end

  # ============================================================================
  # Orders
  # ============================================================================

  @doc """
  Returns `true` if no active (non-cancelled) order has yet used this cooperative
  member's referral code, meaning the member's own 1 free 75cl bottle (+ free
  custom label) is still available.
  """
  def member_free_bottle_available?(nil), do: false

  def member_free_bottle_available?(%CoopMember{id: member_id}) do
    not Repo.exists?(
      from o in Order,
        where: o.coop_member_id == ^member_id and o.pickup_status != "cancelled"
    )
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking public order changes, resolving
  any referral code automatically.
  """
  def change_order(%Order{} = order, attrs \\ %{}, setting \\ nil) do
    setting = setting || get_setting!()

    raw_code =
      Map.get(attrs, "referral_code_used") || Map.get(attrs, :referral_code_used) ||
        order.referral_code_used

    coop_member = get_coop_member_by_code(raw_code)
    free_member_bottle? = member_free_bottle_available?(coop_member)

    Order.changeset(order, attrs, setting, coop_member, free_member_bottle?)
  end

  @doc """
  Creates a new order after validating sales status, total liters remaining,
  bottle stock, and custom label fields. Delivers the summary email via
  `OrderNotifier` and broadcasts the creation.
  """
  def create_order(attrs, label_upload \\ nil) do
    setting = get_setting!()
    raw_code = Map.get(attrs, "referral_code_used") || Map.get(attrs, :referral_code_used)
    coop_member = get_coop_member_by_code(raw_code)
    free_member_bottle? = member_free_bottle_available?(coop_member)

    changeset =
      %Order{}
      |> Order.changeset(attrs, setting, coop_member, free_member_bottle?)
      |> Order.put_label_upload(label_upload)
      |> Order.validate_custom_label_submission()
      |> validate_sales_open(setting)
      |> validate_stock_availability(setting)

    case Repo.insert(changeset) do
      {:ok, order} ->
        order = Repo.preload(order, :coop_member)
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
      |> check_total_liters(req_33, req_75, setting.target_liters, reserved)
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

  defp check_total_liters(changeset, _req_33, _req_75, nil, _reserved), do: changeset

  defp check_total_liters(changeset, req_33, req_75, target_liters, reserved) do
    current_liters = reserved.qty_33cl * 0.33 + reserved.qty_75cl * 0.75
    requested_liters = req_33 * 0.33 + req_75 * 0.75
    remaining_liters = Float.round(max(target_liters - current_liters, 0.0), 2)

    if current_liters + requested_liters > target_liters + 0.001 do
      Ecto.Changeset.add_error(
        changeset,
        :qty_75cl,
        "Volume disponible dépassé : il ne reste que #{remaining_liters} L sur la cuvée de #{target_liters} L"
      )
    else
      changeset
    end
  end

  @doc """
  Lists orders ordered by newest first, preloading `:coop_member`, with optional
  search and status filters.
  """
  def list_orders(filters \\ %{}) do
    Order
    |> apply_search_filter(Map.get(filters, :search) || Map.get(filters, "search"))
    |> apply_status_filter(Map.get(filters, :filter) || Map.get(filters, "filter"))
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> preload(:coop_member)
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
          ilike(o.pickup_comment, ^term) or
          ilike(o.referral_code_used, ^term) or
          ilike(o.custom_label_text, ^term)
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

  defp apply_status_filter(query, "custom_label") do
    from o in query, where: o.custom_label == true and o.pickup_status != "cancelled"
  end

  defp apply_status_filter(query, "cancelled") do
    from o in query, where: o.pickup_status == "cancelled"
  end

  defp apply_status_filter(query, _all), do: query

  @doc """
  Gets a single order by ID with `:coop_member` preloaded.
  """
  def get_order!(id) do
    Order
    |> preload(:coop_member)
    |> Repo.get!(id)
  end

  @doc """
  Gets a single order by reference.
  """
  def get_order_by_reference(reference) when is_binary(reference) do
    Order
    |> preload(:coop_member)
    |> Repo.get_by(reference: String.trim(reference) |> String.upcase())
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
        updated = Repo.preload(updated, :coop_member)
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
  the public 35L progress bar.
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

    target_liters = setting.target_liters || 35.0
    remaining_liters = Float.round(max(target_liters - total_liters, 0.0), 2)

    progress_percent =
      if target_liters > 0 do
        min(round(total_liters / target_liters * 100), 100)
      else
        0
      end

    %{
      active_orders_count: active_stats.active_orders_count,
      picked_up_count: picked_up_count,
      qty_33cl: active_stats.qty_33cl,
      qty_75cl: active_stats.qty_75cl,
      remaining_33cl: remaining_33cl,
      remaining_75cl: remaining_75cl,
      total_liters: total_liters,
      target_liters: target_liters,
      remaining_liters: remaining_liters,
      progress_percent: progress_percent,
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
      "Code Parrain",
      "Membre Parrain",
      "Étiquette Custom",
      "Texte Étiquette",
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
          o.referral_code_used || "",
          (o.coop_member && o.coop_member.name) || "",
          if(o.custom_label, do: "Oui", else: "Non"),
          o.custom_label_text || "",
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
