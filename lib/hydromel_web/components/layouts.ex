defmodule HydromelWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use HydromelWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the main application layout for Coopérative Merhzinsa.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current scope"

  attr :wide, :boolean,
    default: false,
    doc: "whether to use a wider container (e.g. for the cooperative dashboard)"

  attr :hide_reserve_link, :boolean,
    default: false,
    doc: "whether to hide the 'Réserver' link in the header (e.g. when already on the home page)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col justify-between bg-gradient-to-b from-amber-50/70 via-stone-50 to-amber-50/30">
      <header class="sticky top-0 z-30 border-b border-amber-200/70 bg-white/85 backdrop-blur-md">
        <div class="mx-auto flex max-w-6xl items-center justify-between px-4 py-3 sm:px-6 lg:px-8">
          <.link navigate={~p"/"} class="group flex items-center gap-3.5">
            <div class="rounded-full bg-white p-1 shadow-md ring-2 ring-amber-300/80 transition-transform duration-200 group-hover:scale-105">
              <img
                src={~p"/images/logo.png"}
                alt="Logo Cercle des Druides Merhzinsa"
                class="size-12 sm:size-14 rounded-full object-contain"
              />
            </div>
            <div>
              <span class="block text-xs font-bold uppercase tracking-widest text-amber-700">
                Cercle des Druides
              </span>
              <span class="block text-xl font-extrabold tracking-tight text-stone-900">
                Merhzinsa
              </span>
            </div>
          </.link>

          <nav class="flex items-center gap-2 sm:gap-3">
            <%= unless @hide_reserve_link do %>
              <.link
                navigate={~p"/"}
                class="inline-flex items-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium text-stone-700 transition-colors hover:bg-amber-100/60 hover:text-amber-900"
              >
                <.icon name="hero-shopping-bag" class="size-4 text-amber-700" />
                <span>Réserver</span>
              </.link>
            <% end %>

            <.link
              navigate={~p"/coop"}
              class="inline-flex items-center gap-1.5 rounded-lg border border-amber-200 bg-amber-50/80 px-3 py-2 text-sm font-medium text-amber-900 transition-all hover:border-amber-300 hover:bg-amber-100"
            >
              <.icon name="hero-chart-bar-square" class="size-4 text-amber-700" />
              <span>Espace Coopérative</span>
            </.link>
          </nav>
        </div>
      </header>

      <main class="flex-1 px-4 py-8 sm:px-6 sm:py-12 lg:px-8">
        <div class={[
          "mx-auto",
          if(@wide, do: "max-w-6xl", else: "max-w-3xl")
        ]}>
          {render_slot(@inner_block)}
        </div>
      </main>

      <footer class="border-t border-amber-200/60 bg-white/70 py-6 text-center text-xs text-stone-500">
        <div class="mx-auto max-w-4xl px-4 space-y-2">
          <img
            src={~p"/images/logo.png"}
            alt="Logo Cercle des Druides Merhzinsa"
            class="mx-auto size-14 rounded-full bg-white p-1 shadow-xs ring-1 ring-amber-200 object-contain"
          />
          <p class="font-medium text-stone-700">
            Coopérative Merhzinsa — Brassin collectif privé d'hydromel (participation aux frais de brassage entre membres et proches)
          </p>
          <p>
            L'abus d'alcool est dangereux pour la santé, à consommer avec modération. Réservé exclusivement aux personnes majeures (18 ans et plus).
          </p>
        </div>
      </footer>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
