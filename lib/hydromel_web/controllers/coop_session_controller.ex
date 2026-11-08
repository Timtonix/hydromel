defmodule HydromelWeb.CoopSessionController do
  @moduledoc """
  Handles cooperative login, logout, and CSV export downloads.
  """
  use HydromelWeb, :controller

  alias Hydromel.Orders
  alias HydromelWeb.CoopAuth

  def create(conn, %{"session" => %{"password" => password}}) do
    if CoopAuth.valid_password?(password) do
      conn
      |> configure_session(renew: true)
      |> put_session(:coop_authenticated, true)
      |> put_flash(:info, "Bienvenue dans l'espace coopérative Merhzinsa.")
      |> redirect(to: ~p"/coop")
    else
      conn
      |> put_flash(:error, "Mot de passe incorrect.")
      |> redirect(to: ~p"/coop/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Vous êtes déconnecté de l'espace coopérative.")
    |> redirect(to: ~p"/")
  end

  def export_csv(conn, _params) do
    csv_data = Orders.export_orders_csv()
    filename = "commandes-hydromel-merhzinsa-#{Date.utc_today()}.csv"

    conn
    |> put_resp_content_type("text/csv; charset=utf-8")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, csv_data)
  end
end
