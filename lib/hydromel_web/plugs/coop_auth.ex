defmodule HydromelWeb.CoopAuth do
  @moduledoc """
  Plug and LiveView `on_mount` hook protecting the Merhzinsa cooperative
  administration space (`/coop`) with a shared password.
  """
  use HydromelWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :coop_authenticated) == true do
      conn
    else
      conn
      |> put_flash(
        :error,
        "Veuillez saisir le mot de passe de la coopérative pour accéder à cet espace."
      )
      |> redirect(to: ~p"/coop/login")
      |> halt()
    end
  end

  def on_mount(:require_coop_auth, _params, session, socket) do
    if session["coop_authenticated"] == true do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          "Veuillez saisir le mot de passe de la coopérative pour accéder à cet espace."
        )
        |> Phoenix.LiveView.redirect(to: ~p"/coop/login")

      {:halt, socket}
    end
  end

  @doc """
  Verifies a candidate password against the configured cooperative password
  using constant-time comparison.
  """
  def valid_password?(candidate) when is_binary(candidate) do
    expected = expected_password()
    Plug.Crypto.secure_compare(candidate, expected)
  end

  def valid_password?(_), do: false

  def expected_password do
    Application.get_env(:hydromel, :coop_password, "merhzinsa")
  end
end
