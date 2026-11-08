defmodule HydromelWeb.CoopLive.Dashboard do
  @moduledoc """
  Real-time dashboard for the Merhzinsa cooperative (`/coop`) to track pre-sale
  statistics, manage order payment/pickup statuses, export CSV, and configure
  prices, stocks, and payment instructions.
  """
  use HydromelWeb, :live_view

  alias Hydromel.Orders
  alias Hydromel.Orders.OrderNotifier

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Orders.subscribe()
    end

    setting = Orders.get_setting!()
    stats = Orders.get_stats(setting)
    orders = Orders.list_orders(%{search: "", filter: "all"})
    setting_changeset = Orders.change_setting(setting)

    {:ok,
     socket
     |> assign(:page_title, "Tableau de bord Coopérative")
     |> assign(:active_tab, "orders")
     |> assign(:setting, setting)
     |> assign(:stats, stats)
     |> assign(:search, "")
     |> assign(:filter, "all")
     |> assign(:orders_count, length(orders))
     |> assign(:filter_form, to_form(%{"search" => "", "filter" => "all"}, as: :filters))
     |> assign(:setting_form, to_form(setting_changeset, as: :setting))
     |> stream(:orders, orders, reset: true)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in ["orders", "settings"] do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("filter_orders", %{"filters" => filter_params}, socket) do
    search = Map.get(filter_params, "search", socket.assigns.search)
    filter = Map.get(filter_params, "filter", socket.assigns.filter)

    {:noreply, reload_orders(socket, search, filter)}
  end

  @impl true
  def handle_event("set_status_filter", %{"filter" => filter}, socket) do
    {:noreply, reload_orders(socket, socket.assigns.search, filter)}
  end

  @impl true
  def handle_event("toggle_payment", %{"id" => id}, socket) do
    order = Orders.get_order!(id)
    {:ok, _updated} = Orders.toggle_payment_status(order)

    {:noreply, refresh_dashboard(socket)}
  end

  @impl true
  def handle_event("toggle_pickup", %{"id" => id}, socket) do
    order = Orders.get_order!(id)
    {:ok, _updated} = Orders.toggle_pickup_status(order)

    {:noreply, refresh_dashboard(socket)}
  end

  @impl true
  def handle_event("cancel_order", %{"id" => id}, socket) do
    order = Orders.get_order!(id)
    {:ok, _updated} = Orders.cancel_order(order)

    {:noreply,
     socket
     |> put_flash(:info, "La commande #{order.reference} a été marquée comme annulée.")
     |> refresh_dashboard()}
  end

  @impl true
  def handle_event("restore_order", %{"id" => id}, socket) do
    order = Orders.get_order!(id)
    {:ok, _updated} = Orders.restore_order(order)

    {:noreply,
     socket
     |> put_flash(:info, "La commande #{order.reference} a été restaurée.")
     |> refresh_dashboard()}
  end

  @impl true
  def handle_event("validate_settings", %{"setting" => setting_params}, socket) do
    changeset =
      socket.assigns.setting
      |> Orders.change_setting(setting_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :setting_form, to_form(changeset, as: :setting))}
  end

  @impl true
  def handle_event("save_settings", %{"setting" => setting_params}, socket) do
    case Orders.update_setting(socket.assigns.setting, setting_params) do
      {:ok, updated_setting} ->
        stats = Orders.get_stats(updated_setting)
        changeset = Orders.change_setting(updated_setting)

        {:noreply,
         socket
         |> assign(:setting, updated_setting)
         |> assign(:stats, stats)
         |> assign(:setting_form, to_form(changeset, as: :setting))
         |> put_flash(:info, "La configuration de la prévente a été enregistrée avec succès.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:setting_form, to_form(changeset, as: :setting))
         |> put_flash(
           :error,
           "Veuillez corriger les erreurs dans le formulaire de configuration."
         )}
    end
  end

  @impl true
  def handle_info({:setting_updated, updated_setting}, socket) do
    stats = Orders.get_stats(updated_setting)
    changeset = Orders.change_setting(updated_setting)

    {:noreply,
     socket
     |> assign(:setting, updated_setting)
     |> assign(:stats, stats)
     |> assign(:setting_form, to_form(changeset, as: :setting))}
  end

  @impl true
  def handle_info({_order_event, _order}, socket) do
    {:noreply, refresh_dashboard(socket)}
  end

  defp refresh_dashboard(socket) do
    stats = Orders.get_stats(socket.assigns.setting)

    socket
    |> assign(:stats, stats)
    |> reload_orders(socket.assigns.search, socket.assigns.filter)
  end

  defp reload_orders(socket, search, filter) do
    orders = Orders.list_orders(%{search: search, filter: filter})

    socket
    |> assign(:search, search)
    |> assign(:filter, filter)
    |> assign(:orders_count, length(orders))
    |> assign(:filter_form, to_form(%{"search" => search, "filter" => filter}, as: :filters))
    |> stream(:orders, orders, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide={true}>
      <div class="space-y-8">
        <%!-- Header & Navigation Tabs --%>
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-amber-200/80 pb-6">
          <div>
            <div class="flex items-center gap-2">
              <span class="inline-flex items-center gap-1.5 rounded-full bg-amber-100 px-3 py-0.5 text-xs font-bold text-amber-900">
                <.icon name="hero-shield-check-solid" class="size-3.5 text-amber-700" />
                <span>Administration Merhzinsa</span>
              </span>
              <%= if @setting.sales_open do %>
                <span class="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2.5 py-0.5 text-xs font-semibold text-emerald-800">
                  <span class="size-1.5 rounded-full bg-emerald-600"></span> Prévente ouverte
                </span>
              <% else %>
                <span class="inline-flex items-center gap-1 rounded-full bg-red-100 px-2.5 py-0.5 text-xs font-semibold text-red-800">
                  <span class="size-1.5 rounded-full bg-red-600"></span> Prévente fermée
                </span>
              <% end %>
            </div>
            <h1 class="mt-2 text-2xl sm:text-3xl font-extrabold text-stone-900">
              Suivi de la prévente d'Hydromel
            </h1>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <div class="inline-flex rounded-xl border border-stone-200 bg-white p-1 shadow-2xs">
              <button
                id="tab-orders-btn"
                type="button"
                phx-click="switch_tab"
                phx-value-tab="orders"
                class={[
                  "inline-flex items-center gap-1.5 rounded-lg px-3.5 py-2 text-sm font-semibold transition cursor-pointer",
                  if(@active_tab == "orders",
                    do: "bg-amber-700 text-white shadow-xs",
                    else: "text-stone-600 hover:text-stone-900"
                  )
                ]}
              >
                <.icon name="hero-clipboard-document-list" class="size-4" />
                <span>Commandes ({@stats.active_orders_count})</span>
              </button>

              <button
                id="tab-settings-btn"
                type="button"
                phx-click="switch_tab"
                phx-value-tab="settings"
                class={[
                  "inline-flex items-center gap-1.5 rounded-lg px-3.5 py-2 text-sm font-semibold transition cursor-pointer",
                  if(@active_tab == "settings",
                    do: "bg-amber-700 text-white shadow-xs",
                    else: "text-stone-600 hover:text-stone-900"
                  )
                ]}
              >
                <.icon name="hero-cog-6-tooth" class="size-4" />
                <span>Configuration (Prix / PayPal / Stocks)</span>
              </button>
            </div>

            <.link
              href={~p"/coop/logout"}
              method="delete"
              class="inline-flex items-center gap-1.5 rounded-xl border border-stone-300 bg-white px-3.5 py-2.5 text-sm font-medium text-stone-700 transition hover:bg-stone-100"
            >
              <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" />
              <span>Déconnexion</span>
            </.link>
          </div>
        </div>

        <%!-- Real-time Summary Cards --%>
        <section class="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
          <div class="rounded-2xl border border-amber-200/70 bg-white p-5 shadow-xs">
            <span class="text-xs font-semibold uppercase tracking-wider text-stone-500">
              Commandes actives
            </span>
            <div id="stat-active-orders" class="mt-2 text-3xl font-extrabold text-stone-900">
              {@stats.active_orders_count}
            </div>
            <p class="mt-1 text-xs text-stone-500">
              Dont <strong>{@stats.picked_up_count}</strong> récupérée(s)
            </p>
          </div>

          <div class="rounded-2xl border border-amber-200/70 bg-white p-5 shadow-xs">
            <span class="text-xs font-semibold uppercase tracking-wider text-stone-500">
              Bouteilles 33cl
            </span>
            <div id="stat-qty-33cl" class="mt-2 text-3xl font-extrabold text-amber-800">
              {@stats.qty_33cl}
            </div>
            <p class="mt-1 text-xs text-stone-500">
              <%= if @stats.remaining_33cl != nil do %>
                Reste <strong>{@stats.remaining_33cl}</strong> sur {@setting.stock_33cl}
              <% else %>
                Prix unit. : {OrderNotifier.format_euros(@setting.price_33cl_cents)}
              <% end %>
            </p>
          </div>

          <div class="rounded-2xl border border-amber-200/70 bg-white p-5 shadow-xs">
            <span class="text-xs font-semibold uppercase tracking-wider text-stone-500">
              Bouteilles 75cl
            </span>
            <div id="stat-qty-75cl" class="mt-2 text-3xl font-extrabold text-amber-800">
              {@stats.qty_75cl}
            </div>
            <p class="mt-1 text-xs text-stone-500">
              <%= if @stats.remaining_75cl != nil do %>
                Reste <strong>{@stats.remaining_75cl}</strong> sur {@setting.stock_75cl}
              <% else %>
                Prix unit. : {OrderNotifier.format_euros(@setting.price_75cl_cents)}
              <% end %>
            </p>
          </div>

          <div class="rounded-2xl border border-amber-200/70 bg-white p-5 shadow-xs">
            <span class="text-xs font-semibold uppercase tracking-wider text-stone-500">
              Volume réservé
            </span>
            <div id="stat-total-liters" class="mt-2 text-3xl font-extrabold text-stone-900">
              {@stats.total_liters} L
            </div>
            <p class="mt-1 text-xs text-stone-500">
              Total cumulé (33cl + 75cl)
            </p>
          </div>

          <div class="rounded-2xl border border-amber-300 bg-amber-50/70 p-5 shadow-xs">
            <span class="text-xs font-semibold uppercase tracking-wider text-amber-900">
              Total encaissé / prévu
            </span>
            <div id="stat-paid-revenue" class="mt-2 text-2xl font-extrabold text-emerald-700">
              {OrderNotifier.format_euros(@stats.paid_cents)}
            </div>
            <p id="stat-expected-revenue" class="mt-1 text-xs font-medium text-amber-950">
              sur {OrderNotifier.format_euros(@stats.expected_cents)} réservés
            </p>
          </div>
        </section>

        <%= if @active_tab == "settings" do %>
          <%!-- Cooperative Configuration Tab --%>
          <section
            id="coop-settings-panel"
            class="rounded-3xl border border-amber-200 bg-white p-6 sm:p-8 shadow-sm space-y-6"
          >
            <div class="border-b border-stone-100 pb-4">
              <h2 class="text-xl font-bold text-stone-900">
                Configuration de la prévente Merhzinsa
              </h2>
              <p class="text-sm text-stone-600">
                Modifiez à tout moment les tarifs des bouteilles, les plafonds de stock et les instructions de règlement (PayPal, Wero, Espèces).
              </p>
            </div>

            <.form
              for={@setting_form}
              id="coop-settings-form"
              phx-change="validate_settings"
              phx-submit="save_settings"
              class="space-y-8"
            >
              <%!-- Prices & Stock --%>
              <div class="grid gap-6 sm:grid-cols-2">
                <div class="rounded-2xl border border-stone-200 bg-stone-50/50 p-5 space-y-4">
                  <h3 class="font-bold text-stone-900">Format 33cl</h3>
                  <.input
                    field={@setting_form[:price_33cl_euros]}
                    type="text"
                    label="Prix unitaire 33cl (€)"
                    placeholder="4.50"
                    required
                    class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2 text-sm text-stone-900"
                  />
                  <.input
                    field={@setting_form[:stock_33cl]}
                    type="number"
                    min="0"
                    label="Stock maximum 33cl (laisser vide si illimité)"
                    placeholder="Illimité"
                    class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2 text-sm text-stone-900"
                  />
                </div>

                <div class="rounded-2xl border border-stone-200 bg-stone-50/50 p-5 space-y-4">
                  <h3 class="font-bold text-stone-900">Format 75cl</h3>
                  <.input
                    field={@setting_form[:price_75cl_euros]}
                    type="text"
                    label="Prix unitaire 75cl (€)"
                    placeholder="9.00"
                    required
                    class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2 text-sm text-stone-900"
                  />
                  <.input
                    field={@setting_form[:stock_75cl]}
                    type="number"
                    min="0"
                    label="Stock maximum 75cl (laisser vide si illimité)"
                    placeholder="Illimité"
                    class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2 text-sm text-stone-900"
                  />
                </div>
              </div>

              <%!-- Payment Instructions --%>
              <div class="space-y-4 rounded-2xl border border-stone-200 bg-stone-50/50 p-5">
                <h3 class="font-bold text-stone-900">
                  Coordonnées & Instructions de paiement hors-site
                </h3>

                <div class="grid gap-4 sm:grid-cols-2">
                  <.input
                    field={@setting_form[:paypal_url]}
                    type="url"
                    label="Lien PayPal (ex: https://paypal.me/merhzinsa)"
                    placeholder="https://paypal.me/..."
                    class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2 text-sm text-stone-900"
                  />

                  <.input
                    field={@setting_form[:paypal_instructions]}
                    type="textarea"
                    rows="2"
                    label="Instructions PayPal"
                    class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2 text-sm text-stone-900"
                  />
                </div>

                <div class="grid gap-4 sm:grid-cols-2">
                  <.input
                    field={@setting_form[:wero_instructions]}
                    type="textarea"
                    rows="2"
                    label="Instructions Wero (numéro de téléphone / consigne)"
                    class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2 text-sm text-stone-900"
                  />

                  <.input
                    field={@setting_form[:cash_instructions]}
                    type="textarea"
                    rows="2"
                    label="Instructions Espèces (Cash)"
                    class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2 text-sm text-stone-900"
                  />
                </div>

                <.input
                  field={@setting_form[:pickup_info]}
                  type="textarea"
                  rows="2"
                  label="Indication affichée au-dessus du champ commentaire de retrait"
                  class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2 text-sm text-stone-900"
                />
              </div>

              <%!-- Open/Close Sales --%>
              <div class="space-y-4 rounded-2xl border border-stone-200 bg-stone-50/50 p-5">
                <h3 class="font-bold text-stone-900">Ouverture de la prévente</h3>
                <.input
                  field={@setting_form[:sales_open]}
                  type="checkbox"
                  label="Autoriser les nouvelles réservations sur le site public"
                />

                <.input
                  field={@setting_form[:closed_message]}
                  type="textarea"
                  rows="2"
                  label="Message affiché lorsque la prévente est fermée"
                  class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2 text-sm text-stone-900"
                />
              </div>

              <div class="flex justify-end">
                <button
                  id="save-settings-btn"
                  type="submit"
                  class="inline-flex items-center gap-2 rounded-xl bg-amber-700 px-6 py-3 text-sm font-bold text-white shadow-sm transition hover:bg-amber-800 cursor-pointer"
                >
                  <.icon name="hero-check" class="size-5" />
                  <span>Enregistrer la configuration</span>
                </button>
              </div>
            </.form>
          </section>
        <% else %>
          <%!-- Orders List & Filters Tab --%>
          <section class="rounded-3xl border border-amber-200 bg-white p-6 shadow-sm space-y-6">
            <div class="flex flex-col lg:flex-row lg:items-center justify-between gap-4">
              <.form
                for={@filter_form}
                id="orders-filter-form"
                phx-change="filter_orders"
                class="flex-1 max-w-md"
              >
                <div class="relative">
                  <.input
                    field={@filter_form[:search]}
                    type="search"
                    placeholder="Rechercher un nom, email, référence, commentaire..."
                    phx-debounce="200"
                    class="w-full rounded-xl border border-stone-300 bg-stone-50 px-3.5 py-2 text-sm text-stone-900 focus:border-amber-600 focus:bg-white focus:outline-none"
                  />
                </div>
              </.form>

              <div class="flex flex-wrap items-center gap-2">
                <%= for {key, label} <- [
                  {"all", "Toutes"},
                  {"unpaid", "À encaisser"},
                  {"paid", "Payées"},
                  {"to_pickup", "À récupérer"},
                  {"picked_up", "Récupérées"},
                  {"cancelled", "Annulées"}
                ] do %>
                  <button
                    id={"filter-btn-#{key}"}
                    type="button"
                    phx-click="set_status_filter"
                    phx-value-filter={key}
                    class={[
                      "rounded-lg px-3 py-1.5 text-xs font-semibold transition cursor-pointer",
                      if(@filter == key,
                        do: "bg-amber-700 text-white",
                        else: "bg-stone-100 text-stone-700 hover:bg-stone-200"
                      )
                    ]}
                  >
                    {label}
                  </button>
                <% end %>

                <.link
                  id="export-csv-btn"
                  href={~p"/coop/export.csv"}
                  class="inline-flex items-center gap-1.5 rounded-xl border border-amber-300 bg-amber-50 px-3.5 py-2 text-xs font-bold text-amber-900 transition hover:bg-amber-100"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4" />
                  <span>Exporter CSV</span>
                </.link>
              </div>
            </div>

            <%= if @orders_count == 0 do %>
              <div
                id="empty-orders-state"
                class="rounded-2xl border border-dashed border-stone-300 py-12 text-center text-stone-500"
              >
                <.icon name="hero-inbox" class="mx-auto size-10 text-stone-400" />
                <p class="mt-2 font-medium text-stone-700">Aucune commande trouvée</p>
                <p class="text-xs">
                  Les nouvelles réservations apparaîtront ici automatiquement en direct.
                </p>
              </div>
            <% end %>

            <div class="overflow-x-auto">
              <table class="w-full text-left text-sm">
                <thead class="border-b border-stone-200 text-xs uppercase tracking-wider text-stone-500">
                  <tr>
                    <th class="pb-3 pr-4">Réf / Date</th>
                    <th class="pb-3 px-4">Acheteur</th>
                    <th class="pb-3 px-4">Bouteilles</th>
                    <th class="pb-3 px-4">Montant & Mode</th>
                    <th class="pb-3 px-4">Commentaire retrait</th>
                    <th class="pb-3 px-4">Statut Paiement</th>
                    <th class="pb-3 pl-4 text-right">Statut Retrait</th>
                  </tr>
                </thead>
                <tbody id="orders-stream" phx-update="stream" class="divide-y divide-stone-100">
                  <tr
                    :for={{dom_id, order} <- @streams.orders}
                    id={dom_id}
                    class={[
                      "transition hover:bg-amber-50/30",
                      order.pickup_status == "cancelled" && "opacity-50 bg-stone-50"
                    ]}
                  >
                    <td class="py-4 pr-4 align-top whitespace-nowrap">
                      <span class="font-mono font-bold text-amber-900">{order.reference}</span>
                      <span class="block text-xs text-stone-400">
                        {Calendar.strftime(order.inserted_at, "%d/%m/%Y %H:%M")}
                      </span>
                    </td>

                    <td class="py-4 px-4 align-top">
                      <div class="font-bold text-stone-900">
                        {order.first_name} {order.last_name}
                      </div>
                      <a
                        href={"mailto:#{order.email}"}
                        class="text-xs text-amber-700 hover:underline"
                      >
                        {order.email}
                      </a>
                    </td>

                    <td class="py-4 px-4 align-top whitespace-nowrap">
                      <div class="flex flex-col gap-1">
                        <%= if order.qty_33cl > 0 do %>
                          <span class="inline-flex items-center gap-1 rounded-md bg-amber-100/80 px-2 py-0.5 text-xs font-bold text-amber-950 w-fit">
                            {order.qty_33cl} × 33cl
                          </span>
                        <% end %>
                        <%= if order.qty_75cl > 0 do %>
                          <span class="inline-flex items-center gap-1 rounded-md bg-amber-200/80 px-2 py-0.5 text-xs font-bold text-amber-950 w-fit">
                            {order.qty_75cl} × 75cl
                          </span>
                        <% end %>
                      </div>
                    </td>

                    <td class="py-4 px-4 align-top whitespace-nowrap">
                      <div class="font-extrabold text-stone-900">
                        {OrderNotifier.format_euros(order.total_cents)}
                      </div>
                      <span class="text-xs font-medium text-stone-500">
                        {OrderNotifier.payment_method_label(order.payment_method)}
                      </span>
                    </td>

                    <td class="py-4 px-4 align-top max-w-xs">
                      <%= if is_binary(order.pickup_comment) and String.trim(order.pickup_comment) != "" do %>
                        <p class="text-xs text-stone-700 whitespace-pre-line">
                          {order.pickup_comment}
                        </p>
                      <% else %>
                        <span class="text-xs italic text-stone-400">—</span>
                      <% end %>
                    </td>

                    <td class="py-4 px-4 align-top whitespace-nowrap">
                      <button
                        id={"toggle-payment-#{order.id}"}
                        type="button"
                        phx-click="toggle_payment"
                        phx-value-id={order.id}
                        disabled={order.pickup_status == "cancelled"}
                        class={[
                          "inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-bold transition cursor-pointer",
                          if(order.payment_status == "paid",
                            do: "bg-emerald-100 text-emerald-800 hover:bg-emerald-200",
                            else: "bg-amber-100 text-amber-900 hover:bg-amber-200"
                          )
                        ]}
                      >
                        <.icon
                          name={
                            if(order.payment_status == "paid",
                              do: "hero-check-circle-solid",
                              else: "hero-clock"
                            )
                          }
                          class="size-3.5"
                        />
                        <span>
                          {if(order.payment_status == "paid", do: "Payé", else: "En attente")}
                        </span>
                      </button>
                    </td>

                    <td class="py-4 pl-4 align-top text-right whitespace-nowrap">
                      <div class="inline-flex items-center gap-2">
                        <%= if order.pickup_status == "cancelled" do %>
                          <span class="rounded-full bg-red-100 px-2.5 py-1 text-xs font-bold text-red-800">
                            Annulée
                          </span>
                          <button
                            id={"restore-order-#{order.id}"}
                            type="button"
                            phx-click="restore_order"
                            phx-value-id={order.id}
                            class="text-xs font-semibold text-stone-600 underline hover:text-stone-900 cursor-pointer"
                          >
                            Restaurer
                          </button>
                        <% else %>
                          <button
                            id={"toggle-pickup-#{order.id}"}
                            type="button"
                            phx-click="toggle_pickup"
                            phx-value-id={order.id}
                            class={[
                              "inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-bold transition cursor-pointer",
                              if(order.pickup_status == "picked_up",
                                do: "bg-emerald-100 text-emerald-800 hover:bg-emerald-200",
                                else: "bg-stone-100 text-stone-700 hover:bg-stone-200"
                              )
                            ]}
                          >
                            <.icon
                              name={
                                if(order.pickup_status == "picked_up",
                                  do: "hero-check-badge-solid",
                                  else: "hero-archive-box"
                                )
                              }
                              class="size-3.5"
                            />
                            <span>
                              {if(order.pickup_status == "picked_up",
                                do: "Récupéré",
                                else: "À récupérer"
                              )}
                            </span>
                          </button>

                          <button
                            id={"cancel-order-#{order.id}"}
                            type="button"
                            phx-click="cancel_order"
                            phx-value-id={order.id}
                            data-confirm="Voulez-vous vraiment annuler cette commande ?"
                            class="rounded-lg p-1.5 text-stone-400 transition hover:bg-red-50 hover:text-red-600 cursor-pointer"
                            title="Annuler la commande"
                          >
                            <.icon name="hero-trash" class="size-4" />
                          </button>
                        <% end %>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
