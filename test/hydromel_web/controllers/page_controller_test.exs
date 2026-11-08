defmodule HydromelWeb.PageControllerTest do
  use HydromelWeb.ConnCase

  test "GET /up returns health check ok", %{conn: conn} do
    conn = get(conn, ~p"/up")
    assert response(conn, 200) == "ok"
  end

  test "GET / renders the public mead reservation page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Merhzinsa"
  end
end
