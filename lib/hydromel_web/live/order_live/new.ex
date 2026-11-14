defmodule HydromelWeb.OrderLive.New do
  @moduledoc """
  Public LiveView page allowing customers to reserve 33cl and 75cl mead bottles
  from the Merhzinsa cooperative, view the 35L pre-order progress bar, apply a
  member referral code (-1€/bottle), and upload a custom bottle label (+1€/bottle).
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
      Orders.change_order(
        %Order{
          qty_33cl: 0,
          qty_75cl: 1,
          payment_method: "wero",
          custom_label: false,
          adult_certified: false
        },
        %{},
        setting
      )

    {:ok,
     socket
     |> assign(:page_title, "Brassin Collectif d'Hydromel")
     |> assign(:setting, setting)
     |> assign(:stats, stats)
     |> assign(:confirmed_order, nil)
     |> assign(:upload_error, nil)
     |> allow_upload(:label_image,
       accept: ~w(.jpg .jpeg .png .webp .gif),
       max_entries: 1,
       max_file_size: 8_000_000
     )
     |> assign_order_form(changeset, setting)}
  end

  defp assign_order_form(socket, changeset, _setting) do
    qty_33 = max(Ecto.Changeset.get_field(changeset, :qty_33cl) || 0, 0)
    qty_75 = max(Ecto.Changeset.get_field(changeset, :qty_75cl) || 0, 0)
    selected_payment = Ecto.Changeset.get_field(changeset, :payment_method) || "wero"
    custom_label? = Ecto.Changeset.get_field(changeset, :custom_label) == true
    referral_code = Ecto.Changeset.get_field(changeset, :referral_code_used)
    matched_member = Orders.get_coop_member_by_code(referral_code)
    free_member_bottle? = Orders.member_free_bottle_available?(matched_member)

    discount_cents = Ecto.Changeset.get_field(changeset, :discount_cents) || 0
    label_fee_cents = Ecto.Changeset.get_field(changeset, :custom_label_fee_cents) || 0
    total_cents = Ecto.Changeset.get_field(changeset, :total_cents) || 0

    socket
    |> assign(:current_qty_33cl, qty_33)
    |> assign(:current_qty_75cl, qty_75)
    |> assign(:selected_payment, selected_payment)
    |> assign(:custom_label_enabled, custom_label?)
    |> assign(:matched_member, matched_member)
    |> assign(:free_member_bottle?, free_member_bottle?)
    |> assign(:referral_code_input, referral_code || "")
    |> assign(:current_discount_cents, discount_cents)
    |> assign(:current_label_fee_cents, label_fee_cents)
    |> assign(:current_total_cents, total_cents)
    |> assign(:form, to_form(changeset, as: :order))
  end

  @impl true
  def handle_event("validate", %{"order" => order_params}, socket) do
    changeset =
      %Order{adult_certified: false}
      |> Orders.change_order(order_params, socket.assigns.setting)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:upload_error, nil)
     |> assign_order_form(changeset, socket.assigns.setting)}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :label_image, ref)}
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

    source = socket.assigns.form.source

    updated_params =
      form_params
      |> Map.put("qty_33cl", Integer.to_string(next_33))
      |> Map.put("qty_75cl", Integer.to_string(next_75))
      |> Map.put_new("first_name", Ecto.Changeset.get_field(source, :first_name) || "")
      |> Map.put_new("last_name", Ecto.Changeset.get_field(source, :last_name) || "")
      |> Map.put_new("email", Ecto.Changeset.get_field(source, :email) || "")
      |> Map.put_new("payment_method", socket.assigns.selected_payment)
      |> Map.put_new("pickup_comment", Ecto.Changeset.get_field(source, :pickup_comment) || "")
      |> Map.put_new(
        "referral_code_used",
        Ecto.Changeset.get_field(source, :referral_code_used) || ""
      )
      |> Map.put_new("custom_label", to_string(socket.assigns.custom_label_enabled))
      |> Map.put_new(
        "custom_label_text",
        Ecto.Changeset.get_field(source, :custom_label_text) || ""
      )
      |> Map.put_new(
        "adult_certified",
        to_string(Ecto.Changeset.get_field(source, :adult_certified) == true)
      )

    changeset =
      %Order{adult_certified: false}
      |> Orders.change_order(updated_params, socket.assigns.setting)

    {:noreply, assign_order_form(socket, changeset, socket.assigns.setting)}
  end

  @impl true
  def handle_event("save", %{"order" => order_params}, socket) do
    order_params = Map.put_new(order_params, "adult_certified", "false")
    custom_label? = Map.get(order_params, "custom_label") == "true"

    label_upload =
      if custom_label? do
        consume_uploaded_entries(socket, :label_image, fn %{path: path}, entry ->
          {:ok, Orders.store_label_file(path, entry.client_name, entry.client_type)}
        end)
        |> List.first()
      else
        nil
      end

    case Orders.create_order(order_params, label_upload) do
      {:ok, order} ->
        setting = Orders.get_setting!()
        stats = Orders.get_stats(setting)

        {:noreply,
         socket
         |> assign(:setting, setting)
         |> assign(:stats, stats)
         |> assign(:confirmed_order, order)
         |> assign(:upload_error, nil)
         |> put_flash(
           :info,
           "Votre réservation #{order.reference} est enregistrée ! Un e-mail récapitulatif vous a été envoyé."
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        upload_err =
          if custom_label? and is_nil(label_upload) do
            "Veuillez importer une image/photo pour votre étiquette personnalisée."
          else
            nil
          end

        {:noreply,
         socket
         |> assign(:upload_error, upload_err)
         |> assign_order_form(Map.put(changeset, :action, :insert), socket.assigns.setting)}
    end
  end

  @impl true
  def handle_event("new_order", _params, socket) do
    setting = Orders.get_setting!()
    stats = Orders.get_stats(setting)

    changeset =
      Orders.change_order(
        %Order{
          qty_33cl: 0,
          qty_75cl: 1,
          payment_method: "wero",
          custom_label: false,
          adult_certified: false
        },
        %{},
        setting
      )

    {:noreply,
     socket
     |> assign(:setting, setting)
     |> assign(:stats, stats)
     |> assign(:confirmed_order, nil)
     |> assign(:upload_error, nil)
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
  def handle_info({_event, _payload}, socket) do
    stats = Orders.get_stats(socket.assigns.setting)
    {:noreply, assign(socket, :stats, stats)}
  end

  defp progress_fun_message(percent) do
    cond do
      percent <= 0 ->
        "🫣 La cuve est pleine !"

      percent < 25 ->
        "🍯 La Hype druidesque à commencée !"

      percent < 50 ->
        "🐝 Une bouteille d'hydromel = 54 ans d'espérance de vie supplémentaire."

      percent < 80 ->
        "🔥 Plus de la moitié de la cuvée est déjà réservée, faites vite avant qu'on boive tout !"

      percent < 100 ->
        "🚨 Les druides sont en colère, ils se font dépouiller..."

      true ->
        "🧙‍♂️ La cuve est vide, il parait que le grand duide lèche les dernieres gouttes..."
    end
  end

  defp upload_error_to_string(:too_large), do: "Le fichier est trop volumineux (max 8 Mo)."

  defp upload_error_to_string(:not_accepted),
    do: "Format d'image non supporté (utilisez JPG, PNG, WebP ou GIF)."

  defp upload_error_to_string(:too_many_files), do: "Veuillez sélectionner une seule image."
  defp upload_error_to_string(_), do: "Erreur lors de l'import du fichier."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-8">
        <%!-- Hero Banner --%>
        <section class="relative overflow-hidden rounded-3xl bg-gradient-to-br from-amber-900 via-amber-800 to-yellow-700 p-6 sm:p-10 text-white shadow-xl shadow-amber-900/15">
          <div class="relative z-10 flex flex-col-reverse sm:flex-row items-center justify-between gap-6 sm:gap-8">
            <div class="max-w-xl space-y-3.5 text-center sm:text-left">
              <div class="flex flex-wrap items-center justify-center sm:justify-start gap-2">
                <div class="inline-flex items-center gap-2 rounded-full bg-amber-400/20 px-3.5 py-1 text-xs font-semibold uppercase tracking-wider text-amber-200 ring-1 ring-amber-300/30">
                  <img
                    src={~p"/images/logo.png"}
                    alt=""
                    class="size-5 rounded-full bg-white p-0.5 object-contain"
                  />
                  <span>Brassin Collectif Merhzinsa</span>
                </div>
                <div class="inline-flex items-center gap-1.5 rounded-full bg-white/95 px-3.5 py-1 text-xs font-extrabold uppercase tracking-wider text-amber-900 shadow-xs">
                  <.icon name="hero-calendar-days-solid" class="size-4 text-amber-700" />
                  <span>Disponibilité : Février</span>
                </div>
              </div>
              <h1 class="text-3xl font-extrabold tracking-tight sm:text-4xl">
                Réservez votre part du brassin d'hydromel
              </h1>
              <p class="text-sm sm:text-base text-amber-100/90 leading-relaxed">
                Cuvée collective privée limitée à <strong>{@stats.target_liters} litres</strong>, brassée par nos
                <strong>Druides</strong>
                ! Utilisez le code d'un Druide pour réduire votre participation aux frais de <strong>-1€ par bouteille</strong>, et personnalisez votre étiquette avec votre propre photo et texte.
              </p>
              <div class="inline-flex items-center gap-2.5 rounded-2xl bg-amber-950/55 px-4 py-2.5 text-xs sm:text-sm font-semibold text-amber-100 ring-1 ring-amber-300/40">
                <.icon name="hero-clock-solid" class="size-5 shrink-0 text-amber-300" />
                <span>
                  L'hydromel est actuellement en cours de fermentation et d'affinage : <strong>vos bouteilles seront prêtes et disponibles en février !</strong>
                </span>
              </div>
            </div>

            <div class="flex shrink-0 items-center justify-center">
              <div class="rounded-full bg-white p-2 shadow-2xl shadow-amber-950/50 ring-4 ring-amber-300/70 transition-transform duration-300 hover:rotate-3 hover:scale-105">
                <img
                  src={~p"/images/logo.png"}
                  alt="Logo Cercle des Druides Merhzinsa"
                  class="size-32 sm:size-40 rounded-full object-contain"
                />
              </div>
            </div>
          </div>
        </section>

        <%!-- Fun 35L Progress Bar Card --%>
        <section
          id="preorder-progress-card"
          class="rounded-3xl border-2 border-amber-300/80 bg-gradient-to-r from-amber-50 via-white to-amber-50/70 p-6 shadow-sm space-y-4"
        >
          <div class="flex flex-col sm:flex-row sm:items-end justify-between gap-2">
            <div>
              <span class="inline-flex items-center gap-1.5 text-xs font-extrabold uppercase tracking-wider text-amber-800">
                <.icon name="hero-fire-solid" class="size-4 text-amber-600" />
                <span>Jauge de la cuvée en direct</span>
              </span>
              <h2 class="text-lg sm:text-xl font-extrabold text-stone-900 mt-0.5">
                {progress_fun_message(@stats.progress_percent)}
              </h2>
            </div>

            <div class="text-left sm:text-right shrink-0">
              <span id="progress-liters-label" class="text-2xl font-black text-amber-800">
                {@stats.total_liters} L
              </span>
              <span class="text-sm font-semibold text-stone-500">
                / {@stats.target_liters} L réservés ({@stats.progress_percent}%)
              </span>
              <span class="block text-xs font-semibold text-emerald-700">
                Il reste {@stats.remaining_liters} L disponibles !
              </span>
            </div>
          </div>

          <%!-- Animated Honey Barrel Progress Bar --%>
          <div class="relative h-7 w-full overflow-hidden rounded-2xl bg-amber-950/10 p-1 shadow-inner ring-1 ring-amber-300/60">
            <div
              id="preorder-progress-fill"
              style={"width: #{max(@stats.progress_percent, 4)}%"}
              class="flex h-full items-center justify-end rounded-xl bg-gradient-to-r from-amber-500 via-yellow-500 to-amber-600 px-2.5 text-[11px] font-black text-white shadow-sm transition-all duration-700"
            >
              <span>{@stats.progress_percent}%</span>
            </div>
          </div>

          <div class="flex justify-between text-[11px] font-semibold text-stone-500 px-1">
            <span>0 L (Départ)</span>
            <span>10 L 🍯</span>
            <span>20 L 🐝</span>
            <span>{@stats.target_liters} L (Tonneau vide !)</span>
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

                  <%= if (@confirmed_order.discount_cents || 0) > 0 do %>
                    <div class="flex items-center justify-between py-2.5 text-emerald-700">
                      <div>
                        <span class="font-semibold">
                          Remise Code Druide ({@confirmed_order.referral_code_used})
                        </span>
                        <%= if @confirmed_order.coop_member do %>
                          <span class="ml-1 text-xs">
                            — Druide {@confirmed_order.coop_member.name}
                          </span>
                        <% end %>
                      </div>
                      <span class="font-bold">
                        -{OrderNotifier.format_euros(@confirmed_order.discount_cents)}
                      </span>
                    </div>
                  <% end %>

                  <%= if @confirmed_order.custom_label do %>
                    <div class="flex items-center justify-between py-2.5">
                      <div>
                        <span class="font-semibold text-stone-900">
                          Étiquette personnalisée
                        </span>
                        <span class="block text-xs text-stone-500">
                          Texte : « {@confirmed_order.custom_label_text} »
                        </span>
                      </div>
                      <span class="font-bold text-stone-900">
                        {if (@confirmed_order.custom_label_fee_cents || 0) > 0,
                          do:
                            "+#{OrderNotifier.format_euros(@confirmed_order.custom_label_fee_cents)}",
                          else: "Offerte (0,00 €)"}
                      </span>
                    </div>
                  <% end %>
                </div>

                <div class="flex items-center justify-between border-t border-stone-300 pt-3 text-base">
                  <span class="font-bold text-stone-900">Participation totale aux frais</span>
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

              <div class="flex items-start gap-3 rounded-2xl border border-amber-300 bg-amber-50/90 p-4 text-sm text-amber-950">
                <.icon name="hero-calendar-days-solid" class="size-5 shrink-0 text-amber-700 mt-0.5" />
                <div>
                  <strong class="font-extrabold">Disponibilité prévue en février :</strong>
                  <span>
                    notre cuvée d'hydromel finit tranquillement de fermenter et de s'affiner. Vous serez prévenu(e) dès que vos bouteilles seront prêtes à être récupérées en février !
                  </span>
                </div>
              </div>

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
              <h2 class="text-xl font-bold text-stone-900">
                Réservations du brassin momentanément fermées
              </h2>
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
              <%!-- Step 1: Bottle Quantities & Referral Code --%>
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
                            Format 75 cl • Populaire
                          </span>
                          <h3 class="mt-1.5 text-lg font-bold text-stone-900">
                            Bouteille 75cl
                          </h3>
                        </div>
                        <div class="text-right">
                          <%= if @matched_member != nil do %>
                            <span class="block text-xs line-through text-stone-400">
                              {OrderNotifier.format_euros(@setting.price_75cl_cents)}
                            </span>
                            <span class="text-xl font-extrabold text-emerald-700">
                              {OrderNotifier.format_euros(
                                max(@setting.price_75cl_cents - @setting.referral_discount_cents, 0)
                              )}
                            </span>
                          <% else %>
                            <span class="text-xl font-extrabold text-amber-800">
                              {OrderNotifier.format_euros(@setting.price_75cl_cents)}
                            </span>
                            <span class="block text-[11px] font-medium text-emerald-700">
                              {OrderNotifier.format_euros(
                                max(@setting.price_75cl_cents - @setting.referral_discount_cents, 0)
                              )} avec code Druide
                            </span>
                          <% end %>
                        </div>
                      </div>
                      <p class="text-xs text-stone-600">
                        Grande bouteille conviviale.
                        <strong>Étiquette Merhzinsa basique collée sur chaque bouteille.</strong>
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
                        <div class="text-right">
                          <%= if @matched_member != nil do %>
                            <span class="block text-xs line-through text-stone-400">
                              {OrderNotifier.format_euros(@setting.price_33cl_cents)}
                            </span>
                            <span class="text-xl font-extrabold text-emerald-700">
                              {OrderNotifier.format_euros(
                                max(@setting.price_33cl_cents - @setting.referral_discount_cents, 0)
                              )}
                            </span>
                          <% else %>
                            <span class="text-xl font-extrabold text-amber-800">
                              {OrderNotifier.format_euros(@setting.price_33cl_cents)}
                            </span>
                            <span class="block text-[11px] font-medium text-emerald-700">
                              {OrderNotifier.format_euros(
                                max(@setting.price_33cl_cents - @setting.referral_discount_cents, 0)
                              )} avec code parrain
                            </span>
                          <% end %>
                        </div>
                      </div>
                      <p class="text-xs text-stone-600">
                        Format individuel idéal.
                        <strong>Étiquette Merhzinsa basique collée sur chaque bouteille.</strong>
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
                </div>

                <%!-- Referral Code Box (Code Druide) --%>
                <div class="rounded-2xl border border-amber-200 bg-amber-50/50 p-4 sm:p-5 space-y-2">
                  <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                    <div class="space-y-0.5">
                      <label
                        for={@form[:referral_code_used].id}
                        class="text-sm font-bold text-stone-900 flex items-center gap-1.5"
                      >
                        <.icon name="hero-sparkles-solid" class="size-4 text-amber-700" />
                        <span>Code d'un Druide Merhzinsa (optionnel)</span>
                      </label>
                      <p class="text-xs text-stone-600">
                        Les <strong>Druides</strong>
                        ont participé au brassage de l'hydromel : entrez le code d'un Druide pour réduire votre participation aux frais de
                        <strong>-1,00 € par bouteille</strong>
                        !
                      </p>
                    </div>

                    <div class="sm:w-56">
                      <.input
                        field={@form[:referral_code_used]}
                        type="text"
                        placeholder="Ex : MERHZINSA"
                        phx-debounce="150"
                        class="w-full rounded-xl border border-amber-300 bg-white px-3.5 py-2 text-sm font-mono font-bold uppercase text-stone-900 placeholder:text-stone-400 focus:border-amber-600 focus:outline-none"
                      />
                    </div>
                  </div>

                  <%= if @matched_member != nil do %>
                    <div
                      id="referral-matched-badge"
                      class="flex items-center gap-2 rounded-xl bg-emerald-100/90 px-3.5 py-2.5 text-xs font-bold text-emerald-900"
                    >
                      <.icon name="hero-check-badge-solid" class="size-4 text-emerald-700 shrink-0" />
                      <%= if @free_member_bottle? do %>
                        <span>
                          🧙‍♂️ Salut Druide <strong>{@matched_member.name}</strong>
                          ! Merci d'avoir participé au brassage : ta 1ère bouteille de 75cl (et son étiquette personnalisée) est offerte (0,00 €) !
                        </span>
                      <% else %>
                        <span>
                          Code valide ! Invité par le Druide <strong>{@matched_member.name}</strong>
                          (-{OrderNotifier.format_euros(@current_discount_cents)} sur ta participation aux frais)
                        </span>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </section>

              <%!-- Step 2: Custom Sticker Label (+1€/bottle) --%>
              <section
                id="custom-label-section"
                class="rounded-3xl border border-amber-200/80 bg-white p-6 sm:p-8 shadow-sm space-y-6"
              >
                <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-stone-100 pb-4">
                  <div>
                    <span class="text-xs font-bold uppercase tracking-wider text-amber-700">
                      Option Créative (+1,00 € / bouteille)
                    </span>
                    <h2 class="text-xl font-bold text-stone-900">
                      Personnalisez l'étiquette de votre bouteille
                    </h2>
                    <p class="text-xs text-stone-600 mt-0.5">
                      <strong>Chaque bouteille possède déjà une étiquette basique Merhzinsa collée par défaut.</strong>
                      Pour +1,00 € / bouteille (offert sur la bouteille des Druides), remplacez-la par votre propre photo et votre texte !
                    </p>
                  </div>
                </div>

                <div class="grid gap-6 md:grid-cols-5 items-center">
                  <%!-- Sample Label Visual Preview --%>
                  <div class="md:col-span-2 rounded-2xl border border-amber-200 bg-amber-50/50 p-3 text-center space-y-2">
                    <span class="block text-[11px] font-bold uppercase tracking-wider text-amber-900">
                      Exemple d'étiquette personnalisée
                    </span>
                    <img
                      src={~p"/sample-label"}
                      alt="Exemple d'étiquette d'hydromel personnalisée"
                      class="mx-auto max-h-44 w-auto rounded-xl shadow-xs border border-amber-200/80 object-contain bg-white"
                    />
                  </div>

                  <%!-- Toggle & Inputs --%>
                  <div class="md:col-span-3 space-y-4">
                    <div class="rounded-2xl border-2 border-amber-300 bg-amber-50/40 p-4">
                      <.input
                        field={@form[:custom_label]}
                        type="checkbox"
                        label="Oui, je veux une étiquette personnalisée collée sur ma bouteille (+1,00 € / bouteille)"
                      />
                    </div>

                    <%= if @custom_label_enabled do %>
                      <div
                        id="custom-label-fields"
                        class="space-y-4 rounded-2xl border border-stone-200 bg-stone-50/70 p-4 sm:p-5"
                      >
                        <.input
                          field={@form[:custom_label_text]}
                          type="textarea"
                          rows="2"
                          label="Texte à inscrire sur l'étiquette *"
                          placeholder="Ex : Cuvée spéciale Anniversaire de Lucas - 2026 !"
                          class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2.5 text-sm text-stone-900 placeholder:text-stone-400 focus:border-amber-600 focus:outline-none"
                        />

                        <div class="space-y-2">
                          <label class="block text-sm font-semibold text-stone-800">
                            Photo / Image pour l'étiquette * (JPG, PNG, WebP)
                          </label>

                          <div
                            class="flex flex-col items-center justify-center rounded-2xl border-2 border-dashed border-amber-400 bg-white p-4 text-center transition hover:bg-amber-50/40"
                            phx-drop-target={@uploads.label_image.ref}
                          >
                            <.icon name="hero-photo" class="size-8 text-amber-600 mb-1" />
                            <p class="text-xs text-stone-600 mb-2">
                              Glissez-déposez votre image ici ou cliquez ci-dessous
                            </p>
                            <.live_file_input
                              upload={@uploads.label_image}
                              class="text-xs text-stone-700 file:mr-3 file:rounded-lg file:border-0 file:bg-amber-100 file:px-3 file:py-1.5 file:text-xs file:font-bold file:text-amber-900 hover:file:bg-amber-200 cursor-pointer"
                            />
                          </div>

                          <%= for err <- upload_errors(@uploads.label_image) do %>
                            <p class="text-xs font-semibold text-red-600">
                              {upload_error_to_string(err)}
                            </p>
                          <% end %>

                          <%= if @upload_error do %>
                            <p class="text-xs font-semibold text-red-600">
                              {@upload_error}
                            </p>
                          <% end %>

                          <%= for entry <- @uploads.label_image.entries do %>
                            <div class="flex items-center justify-between gap-3 rounded-xl border border-amber-200 bg-white p-2.5">
                              <div class="flex items-center gap-3">
                                <.live_img_preview
                                  entry={entry}
                                  class="size-12 rounded-lg object-cover border border-stone-200"
                                />
                                <div class="text-left">
                                  <p class="text-xs font-bold text-stone-800 truncate max-w-[180px]">
                                    {entry.client_name}
                                  </p>
                                  <p class="text-[11px] text-emerald-700 font-semibold">
                                    Prêt à être envoyé ({entry.progress}%)
                                  </p>
                                </div>
                              </div>

                              <button
                                type="button"
                                phx-click="cancel_upload"
                                phx-value-ref={entry.ref}
                                class="rounded-lg p-1.5 text-stone-400 hover:bg-red-50 hover:text-red-600 cursor-pointer"
                                aria-label="Retirer l'image"
                              >
                                <.icon name="hero-x-mark" class="size-4" />
                              </button>
                            </div>

                            <%= for err <- upload_errors(@uploads.label_image, entry) do %>
                              <p class="text-xs font-semibold text-red-600">
                                {upload_error_to_string(err)}
                              </p>
                            <% end %>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>

                <%!-- Real-time Total Banner --%>
                <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2 rounded-2xl bg-amber-950 px-5 py-4 text-white">
                  <div class="text-xs sm:text-sm text-amber-200 space-y-0.5">
                    <div>
                      <span>Bouteilles :</span>
                      <span class="ml-1 font-semibold text-white">
                        {@current_qty_75cl} × 75cl + {@current_qty_33cl} × 33cl
                      </span>
                    </div>
                    <%= if @current_discount_cents > 0 or @current_label_fee_cents > 0 do %>
                      <div class="flex flex-wrap gap-3 text-xs">
                        <%= if @current_discount_cents > 0 do %>
                          <span class="text-emerald-300 font-semibold">
                            Code Druide : -{OrderNotifier.format_euros(@current_discount_cents)}
                          </span>
                        <% end %>
                        <%= if @current_label_fee_cents > 0 do %>
                          <span class="text-amber-300 font-semibold">
                            Étiquette custom : +{OrderNotifier.format_euros(@current_label_fee_cents)}
                          </span>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                  <div id="live-total-price" class="text-2xl font-extrabold text-amber-300">
                    {OrderNotifier.format_euros(@current_total_cents)}
                  </div>
                </div>
              </section>

              <%!-- Step 3: Customer Information --%>
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

              <%!-- Step 4: Offline Payment & Pickup Comment --%>
              <section class="rounded-3xl border border-amber-200/80 bg-white p-6 sm:p-8 shadow-sm space-y-6">
                <div class="border-b border-stone-100 pb-4">
                  <span class="text-xs font-bold uppercase tracking-wider text-amber-700">
                    Étape 3
                  </span>
                  <h2 class="text-xl font-bold text-stone-900">
                    Participation aux frais (hors site) & Récupération
                  </h2>
                </div>

                <div class="space-y-3">
                  <label class="block text-sm font-semibold text-stone-800">
                    Comment souhaitez-vous régler votre participation aux frais ? *
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

                <div class="space-y-3 pt-2">
                  <div class="flex items-start gap-2.5 rounded-2xl border border-amber-300 bg-amber-50/70 p-3.5 text-xs sm:text-sm text-amber-950">
                    <.icon
                      name="hero-calendar-days-solid"
                      class="size-5 shrink-0 text-amber-700 mt-0.5"
                    />
                    <div>
                      <span class="font-extrabold">Disponibilité en février :</span>
                      <span>
                        l'hydromel sera prêt à être récupéré au mois de <strong>février</strong>
                        (une fois la fermentation et la mise en bouteille terminées par les Druides).
                      </span>
                    </div>
                  </div>

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

                <%!-- Mandatory 18+ & Private Batch Certification --%>
                <div
                  id="adult-certification-box"
                  class="rounded-2xl border-2 border-amber-300 bg-amber-50/50 p-4"
                >
                  <.input
                    field={@form[:adult_certified]}
                    type="checkbox"
                    label="Je certifie sur l'honneur être majeur(e) (18 ans et plus) et participer à titre privé aux frais de ce brassin collectif *"
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
