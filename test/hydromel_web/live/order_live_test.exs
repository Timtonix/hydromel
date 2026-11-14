defmodule HydromelWeb.OrderLiveTest do
  use HydromelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias Hydromel.Orders

  test "renders 35L progress bar, grants free 1st bottle to member, and -1€/bottle on subsequent referral orders",
       %{conn: conn} do
    {:ok, _member} = Orders.create_coop_member(%{"name" => "Thomas", "referral_code" => "THOMAS"})

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#preorder-progress-card")
    assert has_element?(view, "#order-form")
    assert has_element?(view, "#card-33cl")
    assert has_element?(view, "#card-75cl")

    # 1st use of THOMAS code: 1x 75cl is offered for free (0,00 €)
    view
    |> form("#order-form",
      order: %{
        qty_33cl: "0",
        qty_75cl: "1",
        referral_code_used: "THOMAS"
      }
    )
    |> render_change()

    assert has_element?(view, "#referral-matched-badge")
    assert has_element?(view, "#live-total-price", "0,00 €")

    # Submitting without 18+ certification fails
    view
    |> form("#order-form",
      order: %{
        first_name: "Thomas",
        last_name: "Membre",
        email: "thomas@merhzinsa.fr",
        qty_33cl: "0",
        qty_75cl: "1",
        referral_code_used: "THOMAS",
        payment_method: "cash",
        adult_certified: "false"
      }
    )
    |> render_submit()

    refute has_element?(view, "#order-confirmation")

    # Submit the Druide's 1st order (1x 75cl => 0,00 €) with 18+ certification checked
    view
    |> form("#order-form",
      order: %{
        first_name: "Thomas",
        last_name: "Membre",
        email: "thomas@merhzinsa.fr",
        qty_33cl: "0",
        qty_75cl: "1",
        referral_code_used: "THOMAS",
        payment_method: "cash",
        adult_certified: "true"
      }
    )
    |> render_submit()

    assert has_element?(view, "#order-confirmation")
    assert has_element?(view, "#confirmed-total", "0,00 €")

    # Start a 2nd order (referred customer using THOMAS code): 2x 75cl => 2 * (6€ - 1€) = 10,00 €
    view
    |> element("#new-order-btn")
    |> render_click()

    view
    |> form("#order-form",
      order: %{
        first_name: "Marie",
        last_name: "Curie",
        email: "marie.curie@merhzinsa.fr",
        qty_33cl: "0",
        qty_75cl: "2",
        referral_code_used: "THOMAS",
        payment_method: "paypal",
        pickup_comment: "Retrait samedi matin",
        adult_certified: "true"
      }
    )
    |> render_submit()

    assert has_element?(view, "#order-confirmation")
    assert has_element?(view, "#confirmed-total", "10,00 €")
  end
end
