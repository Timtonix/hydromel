defmodule HydromelWeb.CoopSessionController do
  @moduledoc """
  Handles cooperative login, logout, CSV export downloads, and custom label
  image downloads for sticker creation.
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

  def download_label_image(conn, %{"id" => id}) do
    order = Orders.get_order!(id)

    with filename when is_binary(filename) and filename != "" <- order.custom_label_filename,
         path <- Orders.label_file_path(filename),
         true <- File.exists?(path) do
      ext = Path.extname(filename)
      safe_last_name = String.replace(order.last_name || "client", ~r/[^A-Za-z0-9_-]/u, "_")
      download_name = "etiquette-#{order.reference}-#{safe_last_name}#{ext}"
      content_type = order.custom_label_content_type || MIME.from_path(path)

      conn
      |> put_resp_content_type(content_type)
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{download_name}"))
      |> send_file(200, path)
    else
      _ ->
        conn
        |> put_flash(:error, "Image d'étiquette introuvable pour cette commande.")
        |> redirect(to: ~p"/coop")
    end
  end
end
