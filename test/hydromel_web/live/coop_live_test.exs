defmodule HydromelWeb.CoopLiveTest do
  use HydromelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias Hydromel.Orders

  test "redirects unauthenticated access from /coop to /coop/login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/coop/login"}}} = live(conn, ~p"/coop")
  end

  test "manages orders, members, leaderboard, settings, and downloads custom label image", %{
    conn: conn
  } do
    # Create a real temporary file in labels_dir to test download
    tmp_src = Path.join(System.tmp_dir!(), "test-sticker.png")
    File.write!(tmp_src, "fake-png-content")
    upload_meta = Orders.store_label_file(tmp_src, "client-photo.png", "image/png")

    {:ok, order} =
      Orders.create_order(
        %{
          "first_name" => "Thomas",
          "last_name" => "Roux",
          "email" => "thomas@exemple.fr",
          "qty_33cl" => 0,
          "qty_75cl" => 2,
          "custom_label" => true,
          "custom_label_text" => "Hydromel Royal",
          "payment_method" => "wero",
          "pickup_comment" => "Via la coop"
        },
        upload_meta
      )

    conn =
      post(conn, ~p"/coop/login", %{
        "session" => %{"password" => "merhzinsa"}
      })

    assert redirected_to(conn) == ~p"/coop"

    {:ok, view, _html} = live(conn, ~p"/coop")

    assert has_element?(view, "#stat-active-orders", "1")
    assert has_element?(view, "#stat-qty-75cl", "2")
    assert has_element?(view, "#download-label-#{order.id}")

    # Toggle payment status
    view
    |> element("#toggle-payment-#{order.id}")
    |> render_click()

    assert Orders.get_order!(order.id).payment_status == "paid"

    # Switch to Leaderboard & Referral tab and add a member
    view
    |> element("#tab-leaderboard-btn")
    |> render_click()

    assert has_element?(view, "#coop-member-form")

    view
    |> form("#coop-member-form",
      coop_member: %{
        name: "Arthur",
        referral_code: "ARTHUR"
      }
    )
    |> render_submit()

    assert has_element?(view, "#leaderboard-table", "ARTHUR")

    # Switch to configuration tab and update prices + PayPal link
    view
    |> element("#tab-settings-btn")
    |> render_click()

    assert has_element?(view, "#coop-settings-form")

    view
    |> form("#coop-settings-form",
      setting: %{
        target_liters: "35.0",
        price_33cl_euros: "3.50",
        price_75cl_euros: "6.00",
        paypal_url: "https://paypal.me/coopmerhzinsa"
      }
    )
    |> render_submit()

    updated_setting = Orders.get_setting!()
    assert updated_setting.price_75cl_cents == 600
    assert updated_setting.paypal_url == "https://paypal.me/coopmerhzinsa"

    # Verify custom label image download endpoint works when authenticated
    img_conn = get(conn, ~p"/coop/orders/#{order.id}/label-image")
    assert response(img_conn, 200) == "fake-png-content"

    # Verify CSV export endpoint works when authenticated
    csv_conn = get(conn, ~p"/coop/export.csv")
    assert response(csv_conn, 200) =~ order.reference
  end
end
