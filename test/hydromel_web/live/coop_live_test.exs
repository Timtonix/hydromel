defmodule HydromelWeb.CoopLiveTest do
  use HydromelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias Hydromel.Orders

  test "redirects unauthenticated access from /coop to /coop/login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/coop/login"}}} = live(conn, ~p"/coop")
  end

  test "authenticates with cooperative password, manages orders and updates settings", %{
    conn: conn
  } do
    {:ok, order} =
      Orders.create_order(%{
        "first_name" => "Thomas",
        "last_name" => "Roux",
        "email" => "thomas@exemple.fr",
        "qty_33cl" => 3,
        "qty_75cl" => 2,
        "payment_method" => "wero",
        "pickup_comment" => "Via la coop"
      })

    conn =
      post(conn, ~p"/coop/login", %{
        "session" => %{"password" => "merhzinsa"}
      })

    assert redirected_to(conn) == ~p"/coop"

    {:ok, view, _html} = live(conn, ~p"/coop")

    assert has_element?(view, "#stat-active-orders", "1")
    assert has_element?(view, "#stat-qty-33cl", "3")
    assert has_element?(view, "#stat-qty-75cl", "2")

    # Toggle payment status
    view
    |> element("#toggle-payment-#{order.id}")
    |> render_click()

    assert Orders.get_order!(order.id).payment_status == "paid"

    # Toggle pickup status
    view
    |> element("#toggle-pickup-#{order.id}")
    |> render_click()

    assert Orders.get_order!(order.id).pickup_status == "picked_up"

    # Switch to configuration tab and update prices + PayPal link
    view
    |> element("#tab-settings-btn")
    |> render_click()

    assert has_element?(view, "#coop-settings-form")

    view
    |> form("#coop-settings-form",
      setting: %{
        price_33cl_euros: "5.50",
        price_75cl_euros: "11.00",
        paypal_url: "https://paypal.me/coopmerhzinsa"
      }
    )
    |> render_submit()

    updated_setting = Orders.get_setting!()
    assert updated_setting.price_33cl_cents == 550
    assert updated_setting.price_75cl_cents == 1100
    assert updated_setting.paypal_url == "https://paypal.me/coopmerhzinsa"

    # Verify CSV export endpoint works when authenticated
    csv_conn = get(conn, ~p"/coop/export.csv")
    assert response(csv_conn, 200) =~ order.reference
  end
end
