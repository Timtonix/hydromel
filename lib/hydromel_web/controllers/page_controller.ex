defmodule HydromelWeb.PageController do
  use HydromelWeb, :controller

  alias Hydromel.Orders

  def home(conn, _params) do
    render(conn, :home)
  end

  def health(conn, _params) do
    send_resp(conn, 200, "ok")
  end

  def sample_label(conn, _params) do
    setting = Orders.get_setting!()

    with filename when is_binary(filename) and filename != "" <- setting.sample_label_filename,
         path <- Orders.label_file_path(filename),
         true <- File.exists?(path) do
      content_type = MIME.from_path(path)

      conn
      |> put_resp_content_type(content_type)
      |> send_file(200, path)
    else
      _ ->
        redirect(conn, to: ~p"/images/sample-label.svg")
    end
  end
end
