defmodule HydromelWeb.OrderLive.New do
  @moduledoc """
  Public LiveView page allowing customers to reserve 33cl and 75cl mead bottles
  from the Merhzinsa cooperative.
  """
  use HydromelWeb, :live_view

  alias Hydromel.Orders
  alias Hydromel.Orders.{Order, OrderNotifier}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Orders.subscribe()
    end

    setting = Orders.get_setting!()
    stats = Orders.get_stats(setting)

    changeset =
      Orders.change_order(%Order{qty_33cl: 0, qty_75cl: 1, payment_method: "wero"}, %{}, setting)

    {:ok,
     socket
     |> assign(:page_title, "Réservation d'Hydromel")
     |> assign(:setting, setting)
     |> assign(:stats, stats)
     |> assign(:confirmed_order, nil)
     |> assign_order_form(changeset, setting)}
  end

  defp assign_order_form(socket, changeset, setting) do
    qty_33 = Ecto.Changeset.get_field(changeset, :qty_33cl) || 0
    qty_75 = Ecto.Changeset.get_field(changeset, :qty_75cl) || 0
    selected_payment = Ecto.Changeset.get_field(changeset, :payment_method) || "wero"

    total_cents =
      max(qty_33, 0) * setting.price_33cl_cents + max(qty_75, 0) * setting.price_75cl_cents

    socket
    |> assign(:current_qty_33cl, max(qty_33, 0))
    |> assign(:current_qty_75cl, max(qty_75, 0))
    |> assign(:selected_payment, selected_payment)
    |> assign(:current_total_cents, total_cents)
    |> assign(:form, to_form(changeset, as: :order))
  end

  @impl true
  def handle_event("validate", %{"order" => order_params}, socket) do
    changeset =
      %Order{}
      |> Orders.change_order(order_params, socket.assigns.setting)
      |> Map.put(:action, :validate)

    {:noreply, assign_order_form(socket, changeset, socket.assigns.setting)}
  end

  @impl true
  def handle_event("adjust_qty", %{"format" => format, "delta" => delta_str}, socket) do
    delta = String.to_integer(delta_str)
    form_params = socket.assigns.form.params || %{}

    current_33 = socket.assigns.current_qty_33cl
    current_75 = socket.assigns.current_qty_75cl

    {next_33, next_75} =
      case format do
        "33cl" -> {max(current_33 + delta, 0), current_75}
        "75cl" -> {current_33, max(current_75 + delta, 0)}
        _ -> {current_33, current_75}
      end

    updated_params =
      form_params
      |> Map.put("qty_33cl", Integer.to_string(next_33))
      |> Map.put("qty_75cl", Integer.to_string(next_75))
      |> Map.put_new(
        "first_name",
        Ecto.Changeset.get_field(socket.assigns.form.source, :first_name) || ""
      )
      |> Map.put_new(
        "last_name",
        Ecto.Changeset.get_field(socket.assigns.form.source, :last_name) || ""
      )
      |> Map.put_new("email", Ecto.Changeset.get_field(socket.assigns.form.source, :email) || "")
      |> Map.put_new("payment_method", socket.assigns.selected_payment)
      |> Map.put_new(
        "pickup_comment",
        Ecto.Changeset.get_field(socket.assigns.form.source, :pickup_comment) || ""
      )

    changeset =
      %Order{}
      |> Orders.change_order(updated_params, socket.assigns.setting)

    {:noreply, assign_order_form(socket, changeset, socket.assigns.setting)}
  end

  @impl true
  def handle_event("save", %{"order" => order_params}, socket) do
    case Orders.create_order(order_params) do
      {:ok, order} ->
        setting = Orders.get_setting!()
        stats = Orders.get_stats(setting)

        {:noreply,
         socket
         |> assign(:setting, setting)
         |> assign(:stats, stats)
         |> assign(:confirmed_order, order)
         |> put_flash(
           :info,
           "Votre réservation #{order.reference} est enregistrée ! Un e-mail récapitulatif vous a été envoyé."
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign_order_form(socket, Map.put(changeset, :action, :insert), socket.assigns.setting)}
    end
  end

  @impl true
  def handle_event("new_order", _params, socket) do
    setting = Orders.get_setting!()
    stats = Orders.get_stats(setting)

    changeset =
      Orders.change_order(%Order{qty_33cl: 0, qty_75cl: 1, payment_method: "wero"}, %{}, setting)

    {:noreply,
     socket
     |> assign(:setting, setting)
     |> assign(:stats, stats)
     |> assign(:confirmed_order, nil)
     |> assign_order_form(changeset, setting)}
  end

  @impl true
  def handle_info({:setting_updated, setting}, socket) do
    stats = Orders.get_stats(setting)

    socket =
      socket
      |> assign(:setting, setting)
      |> assign(:stats, stats)

    socket =
      if socket.assigns.confirmed_order == nil do
        params = socket.assigns.form.params || %{}
        changeset = Orders.change_order(socket.assigns.form.source.data, params, setting)
        assign_order_form(socket, changeset, setting)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({_order_event, _order}, socket) do
    stats = Orders.get_stats(socket.assigns.setting)
    {:noreply, assign(socket, :stats, stats)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-8">
        <%!-- Hero Banner --%>
        <section class="relative overflow-hidden rounded-3xl bg-gradient-to-br from-amber-900 via-amber-800 to-yellow-700 p-6 sm:p-10 text-white shadow-xl shadow-amber-900/15">
          <div class="relative z-10 max-w-2xl space-y-3">
            <div class="inline-flex items-center gap-2 rounded-full bg-amber-400/20 px-3.5 py-1 text-xs font-semibold uppercase tracking-wider text-amber-200 ring-1 ring-amber-300/30">
              <.icon name="hero-sparkles-solid" class="size-3.5 text-amber-300" />
              <span>Prévente Coopérative Merhzinsa</span>
            </div>
            <h1 class="text-3xl font-extrabold tracking-tight sm:text-4xl">
              Réservez vos bouteilles d'hydromel
            </h1>
            <p class="text-sm sm:text-base text-amber-100/90 leading-relaxed">
              Choisissez vos formats (33cl et/ou 75cl), indiquez comment vous souhaitez récupérer votre commande, et recevez immédiatement le récapitulatif par e-mail.
            </p>
          </div>
        </section>

        <%= cond do %>
          <% @confirmed_order != nil -> %>
            <%!-- Confirmation Screen --%>
            <section
              id="order-confirmation"
              class="rounded-3xl border border-amber-200 bg-white p-6 sm:p-8 shadow-lg shadow-amber-950/5 space-y-6"
            >
              <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-stone-100 pb-6">
                <div class="flex items-start gap-4">
                  <div class="flex size-12 shrink-0 items-center justify-center rounded-2xl bg-emerald-100 text-emerald-700">
                    <.icon name="hero-check-badge-solid" class="size-7" />
                  </div>
                  <div>
                    <span class="text-xs font-semibold uppercase tracking-wider text-emerald-700">
                      Réservation enregistrée
                    </span>
                    <h2 class="text-2xl font-bold text-stone-900">
                      Merci {@confirmed_order.first_name} !
                    </h2>
                    <p class="text-sm text-stone-600 mt-0.5">
                      Un e-mail récapitulatif a été envoyé à <strong class="text-stone-900">{@confirmed_order.email}</strong>.
                    </p>
                  </div>
                </div>

                <div class="rounded-2xl border border-amber-300 bg-amber-50/80 px-5 py-3 text-center">
                  <span class="block text-xs font-medium text-amber-800">Référence commande</span>
                  <span
                    id="confirmed-reference"
                    class="font-mono text-xl font-extrabold tracking-wider text-amber-950"
                  >
                    {@confirmed_order.reference}
                  </span>
                </div>
              </div>

              <%!-- Summary Table --%>
              <div class="rounded-2xl bg-stone-50 p-5 space-y-3">
                <h3 class="text-sm font-semibold uppercase tracking-wider text-stone-500">
                  Détail des bouteilles réservées
                </h3>
                <div class="divide-y divide-stone-200/70 text-sm">
                  <%= if @confirmed_order.qty_33cl > 0 do %>
                    <div class="flex items-center justify-between py-2.5">
                      <div>
                        <span class="font-semibold text-stone-900">Bouteille Hydromel 33cl</span>
                        <span class="ml-2 text-stone-500">
                          {@confirmed_order.qty_33cl} × {OrderNotifier.format_euros(
                            @confirmed_order.unit_price_33cl_cents
                          )}
                        </span>
                      </div>
                      <span class="font-bold text-stone-900">
                        {OrderNotifier.format_euros(
                          @confirmed_order.qty_33cl * @confirmed_order.unit_price_33cl_cents
                        )}
                      </span>
                    </div>
                  <% end %>

                  <%= if @confirmed_order.qty_75cl > 0 do %>
                    <div class="flex items-center justify-between py-2.5">
                      <div>
                        <span class="font-semibold text-stone-900">Bouteille Hydromel 75cl</span>
                        <span class="ml-2 text-stone-500">
                          {@confirmed_order.qty_75cl} × {OrderNotifier.format_euros(
                            @confirmed_order.unit_price_75cl_cents
                          )}
                        </span>
                      </div>
                      <span class="font-bold text-stone-900">
                        {OrderNotifier.format_euros(
                          @confirmed_order.qty_75cl * @confirmed_order.unit_price_75cl_cents
                        )}
                      </span>
                    </div>
                  <% end %>
                </div>

                <div class="flex items-center justify-between border-t border-stone-300 pt-3 text-base">
                  <span class="font-bold text-stone-900">Total à régler</span>
                  <span id="confirmed-total" class="text-xl font-extrabold text-amber-700">
                    {OrderNotifier.format_euros(@confirmed_order.total_cents)}
                  </span>
                </div>
              </div>

              <%!-- Offline Payment Instructions --%>
              <div class="rounded-2xl border border-amber-200 bg-amber-50/60 p-5 space-y-3">
                <div class="flex items-center gap-2 text-amber-950 font-bold">
                  <.icon name="hero-banknotes" class="size-5 text-amber-700" />
                  <span>
                    Instructions de paiement — {OrderNotifier.payment_method_label(
                      @confirmed_order.payment_method
                    )}
                  </span>
                </div>
                <p class="text-sm text-stone-700 whitespace-pre-line leading-relaxed">
                  {OrderNotifier.payment_instructions(@confirmed_order.payment_method, @setting)}
                </p>
                <p class="text-xs font-medium text-amber-900">
                  Pensez à indiquer la référence <strong>{@confirmed_order.reference}</strong>
                  lors de votre règlement.
                </p>

                <%= if @confirmed_order.payment_method == "paypal" and is_binary(@setting.paypal_url) and String.trim(@setting.paypal_url) != "" do %>
                  <div class="pt-1">
                    <a
                      href={String.trim(@setting.paypal_url)}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="inline-flex items-center gap-2 rounded-xl bg-amber-700 px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-amber-800"
                    >
                      <span>Ouvrir le lien PayPal</span>
                      <.icon name="hero-arrow-top-right-on-square" class="size-4" />
                    </a>
                  </div>
                <% end %>
              </div>

              <%= if is_binary(@confirmed_order.pickup_comment) and String.trim(@confirmed_order.pickup_comment) != "" do %>
                <div class="rounded-2xl border border-stone-200 bg-white p-4 text-sm">
                  <span class="block font-semibold text-stone-800 mb-1">
                    Votre commentaire pour la récupération :
                  </span>
                  <p class="text-stone-600 whitespace-pre-line">{@confirmed_order.pickup_comment}</p>
                </div>
              <% end %>

              <div class="pt-2 flex justify-end">
                <button
                  id="new-order-btn"
                  type="button"
                  phx-click="new_order"
                  class="inline-flex items-center gap-2 rounded-xl border border-stone-300 bg-white px-4 py-2.5 text-sm font-semibold text-stone-700 transition hover:bg-stone-100 cursor-pointer"
                >
                  <.icon name="hero-plus-circle" class="size-4" />
                  <span>Effectuer une autre réservation</span>
                </button>
              </div>
            </section>
          <% not @setting.sales_open -> %>
            <%!-- Closed Message --%>
            <section
              id="sales-closed-banner"
              class="rounded-3xl border border-amber-200 bg-white p-8 text-center shadow-sm space-y-4"
            >
              <div class="mx-auto flex size-14 items-center justify-center rounded-2xl bg-amber-100 text-amber-800">
                <.icon name="hero-clock" class="size-7" />
              </div>
              <h2 class="text-xl font-bold text-stone-900">Prévente momentanément fermée</h2>
              <p class="mx-auto max-w-lg text-sm text-stone-600 leading-relaxed">
                {@setting.closed_message}
              </p>
            </section>
          <% true -> %>
            <%!-- Reservation Form --%>
            <.form
              for={@form}
              id="order-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-8"
            >
              <%!-- Step 1: Bottle Quantities --%>
              <section class="rounded-3xl border border-amber-200/80 bg-white p-6 sm:p-8 shadow-sm space-y-6">
                <div class="flex items-center justify-between border-b border-stone-100 pb-4">
                  <div>
                    <span class="text-xs font-bold uppercase tracking-wider text-amber-700">
                      Étape 1
                    </span>
                    <h2 class="text-xl font-bold text-stone-900">
                      Choisissez vos formats de bouteilles
                    </h2>
                  </div>
                  <span class="rounded-full bg-amber-100 px-3 py-1 text-xs font-semibold text-amber-900">
                    {@current_qty_33cl + @current_qty_75cl} bouteille(s)
                  </span>
                </div>

                <div class="grid gap-5 sm:grid-cols-2">
                  <%!-- 33cl Card --%>
                  <div
                    id="card-33cl"
                    class={[
                      "flex flex-col justify-between rounded-2xl border-2 p-5 transition-all",
                      if(@current_qty_33cl > 0,
                        do: "border-amber-500 bg-amber-50/40 shadow-sm",
                        else: "border-stone-200 bg-stone-50/50 hover:border-amber-300"
                      )
                    ]}
                  >
                    <div class="space-y-2">
                      <div class="flex items-start justify-between gap-2">
                        <div>
                          <span class="inline-block rounded-md bg-amber-200/70 px-2 py-0.5 text-xs font-bold text-amber-950">
                            Format 33 cl
                          </span>
                          <h3 class="mt-1.5 text-lg font-bold text-stone-900">
                            Bouteille 33cl
                          </h3>
                        </div>
                        <span class="text-xl font-extrabold text-amber-800">
                          {OrderNotifier.format_euros(@setting.price_33cl_cents)}
                        </span>
                      </div>
                      <p class="text-xs text-stone-600">
                        Format individuel idéal pour découvrir et partager notre cuvée.
                      </p>
                      <%= if @stats.remaining_33cl != nil do %>
                        <p class={[
                          "text-xs font-semibold",
                          if(@stats.remaining_33cl > 0, do: "text-emerald-700", else: "text-red-600")
                        ]}>
                          <%= if @stats.remaining_33cl > 0 do %>
                            Stock disponible : {@stats.remaining_33cl} bouteille(s)
                          <% else %>
                            Rupture de stock sur ce format
                          <% end %>
                        </p>
                      <% end %>
                    </div>

                    <div class="mt-5 flex items-center justify-between gap-3 pt-3 border-t border-stone-200/70">
                      <span class="text-xs font-medium text-stone-600">Quantité :</span>
                      <div class="flex items-center gap-2">
                        <button
                          id="btn-dec-33cl"
                          type="button"
                          phx-click="adjust_qty"
                          phx-value-format="33cl"
                          phx-value-delta="-1"
                          class="flex size-9 items-center justify-center rounded-xl border border-stone-300 bg-white text-stone-700 shadow-xs transition hover:bg-amber-100 hover:border-amber-400 cursor-pointer"
                          aria-label="Retirer une bouteille 33cl"
                        >
                          <.icon name="hero-minus" class="size-4" />
                        </button>

                        <div class="w-16">
                          <.input
                            field={@form[:qty_33cl]}
                            type="number"
                            min="0"
                            max="500"
                            class="w-full rounded-xl border border-stone-300 bg-white px-2 py-1.5 text-center text-base font-bold text-stone-900 focus:border-amber-500 focus:outline-none"
                          />
                        </div>

                        <button
                          id="btn-inc-33cl"
                          type="button"
                          phx-click="adjust_qty"
                          phx-value-format="33cl"
                          phx-value-delta="1"
                          class="flex size-9 items-center justify-center rounded-xl bg-amber-600 text-white shadow-xs transition hover:bg-amber-700 cursor-pointer"
                          aria-label="Ajouter une bouteille 33cl"
                        >
                          <.icon name="hero-plus" class="size-4" />
                        </button>
                      </div>
                    </div>
                  </div>

                  <%!-- 75cl Card --%>
                  <div
                    id="card-75cl"
                    class={[
                      "flex flex-col justify-between rounded-2xl border-2 p-5 transition-all",
                      if(@current_qty_75cl > 0,
                        do: "border-amber-500 bg-amber-50/40 shadow-sm",
                        else: "border-stone-200 bg-stone-50/50 hover:border-amber-300"
                      )
                    ]}
                  >
                    <div class="space-y-2">
                      <div class="flex items-start justify-between gap-2">
                        <div>
                          <span class="inline-block rounded-md bg-amber-200/70 px-2 py-0.5 text-xs font-bold text-amber-950">
                            Format 75 cl
                          </span>
                          <h3 class="mt-1.5 text-lg font-bold text-stone-900">
                            Bouteille 75cl
                          </h3>
                        </div>
                        <span class="text-xl font-extrabold text-amber-800">
                          {OrderNotifier.format_euros(@setting.price_75cl_cents)}
                        </span>
                      </div>
                      <p class="text-xs text-stone-600">
                        Grande bouteille conviviale pour les repas et dégustations.
                      </p>
                      <%= if @stats.remaining_75cl != nil do %>
                        <p class={[
                          "text-xs font-semibold",
                          if(@stats.remaining_75cl > 0, do: "text-emerald-700", else: "text-red-600")
                        ]}>
                          <%= if @stats.remaining_75cl > 0 do %>
                            Stock disponible : {@stats.remaining_75cl} bouteille(s)
                          <% else %>
                            Rupture de stock sur ce format
                          <% end %>
                        </p>
                      <% end %>
                    </div>

                    <div class="mt-5 flex items-center justify-between gap-3 pt-3 border-t border-stone-200/70">
                      <span class="text-xs font-medium text-stone-600">Quantité :</span>
                      <div class="flex items-center gap-2">
                        <button
                          id="btn-dec-75cl"
                          type="button"
                          phx-click="adjust_qty"
                          phx-value-format="75cl"
                          phx-value-delta="-1"
                          class="flex size-9 items-center justify-center rounded-xl border border-stone-300 bg-white text-stone-700 shadow-xs transition hover:bg-amber-100 hover:border-amber-400 cursor-pointer"
                          aria-label="Retirer une bouteille 75cl"
                        >
                          <.icon name="hero-minus" class="size-4" />
                        </button>

                        <div class="w-16">
                          <.input
                            field={@form[:qty_75cl]}
                            type="number"
                            min="0"
                            max="500"
                            class="w-full rounded-xl border border-stone-300 bg-white px-2 py-1.5 text-center text-base font-bold text-stone-900 focus:border-amber-500 focus:outline-none"
                          />
                        </div>

                        <button
                          id="btn-inc-75cl"
                          type="button"
                          phx-click="adjust_qty"
                          phx-value-format="75cl"
                          phx-value-delta="1"
                          class="flex size-9 items-center justify-center rounded-xl bg-amber-600 text-white shadow-xs transition hover:bg-amber-700 cursor-pointer"
                          aria-label="Ajouter une bouteille 75cl"
                        >
                          <.icon name="hero-plus" class="size-4" />
                        </button>
                      </div>
                    </div>
                  </div>
                </div>

                <%!-- Real-time Total Banner --%>
                <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2 rounded-2xl bg-amber-950 px-5 py-4 text-white">
                  <div class="text-sm text-amber-200">
                    <span>Montant total estimé :</span>
                    <span class="ml-1 font-medium text-white">
                      {@current_qty_33cl} × 33cl + {@current_qty_75cl} × 75cl
                    </span>
                  </div>
                  <div id="live-total-price" class="text-2xl font-extrabold text-amber-300">
                    {OrderNotifier.format_euros(@current_total_cents)}
                  </div>
                </div>
              </section>

              <%!-- Step 2: Customer Information --%>
              <section class="rounded-3xl border border-amber-200/80 bg-white p-6 sm:p-8 shadow-sm space-y-5">
                <div class="border-b border-stone-100 pb-4">
                  <span class="text-xs font-bold uppercase tracking-wider text-amber-700">
                    Étape 2
                  </span>
                  <h2 class="text-xl font-bold text-stone-900">
                    Vos coordonnées
                  </h2>
                  <p class="text-xs text-stone-500 mt-0.5">
                    Nécessaires pour vous envoyer le récapitulatif et retrouver votre commande lors du retrait.
                  </p>
                </div>

                <div class="grid gap-4 sm:grid-cols-2">
                  <.input
                    field={@form[:first_name]}
                    type="text"
                    label="Prénom *"
                    placeholder="Ex : Camille"
                    required
                    class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2.5 text-sm text-stone-900 placeholder:text-stone-400 focus:border-amber-600 focus:outline-none"
                  />

                  <.input
                    field={@form[:last_name]}
                    type="text"
                    label="Nom *"
                    placeholder="Ex : Martin"
                    required
                    class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2.5 text-sm text-stone-900 placeholder:text-stone-400 focus:border-amber-600 focus:outline-none"
                  />
                </div>

                <.input
                  field={@form[:email]}
                  type="email"
                  label="Adresse e-mail *"
                  placeholder="camille.martin@exemple.fr"
                  required
                  class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2.5 text-sm text-stone-900 placeholder:text-stone-400 focus:border-amber-600 focus:outline-none"
                />
              </section>

              <%!-- Step 3: Offline Payment & Pickup Comment --%>
              <section class="rounded-3xl border border-amber-200/80 bg-white p-6 sm:p-8 shadow-sm space-y-6">
                <div class="border-b border-stone-100 pb-4">
                  <span class="text-xs font-bold uppercase tracking-wider text-amber-700">
                    Étape 3
                  </span>
                  <h2 class="text-xl font-bold text-stone-900">
                    Mode de paiement (hors site) & Récupération
                  </h2>
                </div>

                <div class="space-y-3">
                  <label class="block text-sm font-semibold text-stone-800">
                    Comment souhaitez-vous régler votre commande ? *
                  </label>

                  <div class="grid gap-3 sm:grid-cols-3">
                    <label
                      for="payment-wero"
                      class={[
                        "flex cursor-pointer flex-col justify-between rounded-2xl border-2 p-4 transition",
                        if(@selected_payment == "wero",
                          do: "border-amber-600 bg-amber-50/60",
                          else: "border-stone-200 hover:border-amber-300"
                        )
                      ]}
                    >
                      <div class="flex items-center justify-between">
                        <span class="font-bold text-stone-900">Wero</span>
                        <input
                          type="radio"
                          id="payment-wero"
                          name={@form[:payment_method].name}
                          value="wero"
                          checked={@selected_payment == "wero"}
                          class="size-4 accent-amber-600"
                        />
                      </div>
                      <span class="mt-2 text-xs text-stone-600">
                        Virement mobile instantané sans frais
                      </span>
                    </label>

                    <label
                      for="payment-paypal"
                      class={[
                        "flex cursor-pointer flex-col justify-between rounded-2xl border-2 p-4 transition",
                        if(@selected_payment == "paypal",
                          do: "border-amber-600 bg-amber-50/60",
                          else: "border-stone-200 hover:border-amber-300"
                        )
                      ]}
                    >
                      <div class="flex items-center justify-between">
                        <span class="font-bold text-stone-900">PayPal</span>
                        <input
                          type="radio"
                          id="payment-paypal"
                          name={@form[:payment_method].name}
                          value="paypal"
                          checked={@selected_payment == "paypal"}
                          class="size-4 accent-amber-600"
                        />
                      </div>
                      <span class="mt-2 text-xs text-stone-600">
                        Paiement en ligne hors site (Entre proches)
                      </span>
                    </label>

                    <label
                      for="payment-cash"
                      class={[
                        "flex cursor-pointer flex-col justify-between rounded-2xl border-2 p-4 transition",
                        if(@selected_payment == "cash",
                          do: "border-amber-600 bg-amber-50/60",
                          else: "border-stone-200 hover:border-amber-300"
                        )
                      ]}
                    >
                      <div class="flex items-center justify-between">
                        <span class="font-bold text-stone-900">Espèces (Cash)</span>
                        <input
                          type="radio"
                          id="payment-cash"
                          name={@form[:payment_method].name}
                          value="cash"
                          checked={@selected_payment == "cash"}
                          class="size-4 accent-amber-600"
                        />
                      </div>
                      <span class="mt-2 text-xs text-stone-600">
                        Règlement en main propre lors du retrait
                      </span>
                    </label>
                  </div>

                  <div class="rounded-xl bg-amber-50/80 border border-amber-200/80 p-3.5 text-xs text-amber-950">
                    <span class="font-semibold">Consigne ({OrderNotifier.payment_method_label(
                      @selected_payment
                    )}) :</span>
                    <span class="ml-1">{OrderNotifier.payment_instructions(
                      @selected_payment,
                      @setting
                    )}</span>
                  </div>
                </div>

                <div class="space-y-1.5 pt-2">
                  <%= if is_binary(@setting.pickup_info) and String.trim(@setting.pickup_info) != "" do %>
                    <p class="text-xs text-stone-600">
                      <.icon
                        name="hero-information-circle"
                        class="size-4 inline text-amber-700 mr-1 align-text-bottom"
                      />
                      {@setting.pickup_info}
                    </p>
                  <% end %>

                  <.input
                    field={@form[:pickup_comment]}
                    type="textarea"
                    rows="3"
                    label="Commentaire sur la récupération de votre commande (optionnel)"
                    placeholder="Ex : Je passerai récupérer ma commande samedi après-midi / Remise via un membre de la coopérative..."
                    class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2.5 text-sm text-stone-900 placeholder:text-stone-400 focus:border-amber-600 focus:outline-none"
                  />
                </div>

                <div class="pt-2">
                  <button
                    id="submit-order-btn"
                    type="submit"
                    phx-disable-with="Enregistrement en cours..."
                    class="w-full inline-flex items-center justify-center gap-2 rounded-2xl bg-gradient-to-r from-amber-600 to-amber-700 px-6 py-4 text-base font-bold text-white shadow-md shadow-amber-700/20 transition hover:from-amber-700 hover:to-amber-800 cursor-pointer"
                  >
                    <.icon name="hero-check-circle" class="size-5" />
                    <span>
                      Confirmer ma réservation ({OrderNotifier.format_euros(@current_total_cents)})
                    </span>
                  </button>
                </div>
              </section>
            </.form>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
