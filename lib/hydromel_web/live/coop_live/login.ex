defmodule HydromelWeb.CoopLive.Login do
  @moduledoc """
  Login LiveView for the Merhzinsa cooperative space (`/coop/login`).
  """
  use HydromelWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    if session["coop_authenticated"] == true do
      {:ok, push_navigate(socket, to: ~p"/coop")}
    else
      form = to_form(%{"password" => ""}, as: :session)

      {:ok,
       socket
       |> assign(:page_title, "Connexion Espace Coopérative")
       |> assign(:form, form)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-md py-8">
        <div class="rounded-3xl border border-amber-200 bg-white p-8 shadow-lg shadow-amber-950/5 space-y-6">
          <div class="text-center space-y-3">
            <div class="mx-auto w-fit rounded-full bg-white p-1.5 shadow-md ring-2 ring-amber-300">
              <img
                src={~p"/images/logo.png"}
                alt="Logo Cercle des Druides Merhzinsa"
                class="size-28 rounded-full object-contain"
              />
            </div>
            <h1 class="text-2xl font-extrabold text-stone-900">
              Espace Coopérative Merhzinsa
            </h1>
            <p class="text-sm text-stone-600">
              Entrez le mot de passe partagé de la coopérative pour gérer la prévente et les tarifs.
            </p>
          </div>

          <.form
            for={@form}
            id="coop-login-form"
            action={~p"/coop/login"}
            method="post"
            class="space-y-4"
          >
            <.input
              field={@form[:password]}
              type="password"
              label="Mot de passe coopérative"
              placeholder="••••••••"
              required
              class="w-full rounded-xl border border-stone-300 bg-white px-3.5 py-2.5 text-sm text-stone-900 focus:border-amber-600 focus:outline-none"
            />

            <button
              id="coop-login-submit"
              type="submit"
              class="w-full inline-flex items-center justify-center gap-2 rounded-xl bg-amber-700 px-4 py-3 text-sm font-bold text-white shadow-sm transition hover:bg-amber-800 cursor-pointer"
            >
              <.icon name="hero-arrow-right-end-on-rectangle" class="size-5" />
              <span>Accéder au tableau de bord</span>
            </button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
