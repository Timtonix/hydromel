defmodule HydromelWeb.OrderLiveTest do
  use HydromelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders reservation form and submits a valid reservation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#order-form")
    assert has_element?(view, "#card-33cl")
    assert has_element?(view, "#card-75cl")

    # Click + on 33cl bottle
    view
    |> element("#btn-inc-33cl")
    |> render_click()

    # Submit the reservation form
    view
    |> form("#order-form",
      order: %{
        first_name: "Marie",
        last_name: "Curie",
        email: "marie.curie@merhzinsa.fr",
        qty_33cl: "2",
        qty_75cl: "1",
        payment_method: "paypal",
        pickup_comment: "Retrait samedi matin"
      }
    )
    |> render_submit()

    assert has_element?(view, "#order-confirmation")
    assert has_element?(view, "#confirmed-reference")
    assert has_element?(view, "#confirmed-total", "18,00 €")
  end
end
