defmodule Hydromel.OrdersTest do
  use Hydromel.DataCase, async: true

  import Swoosh.TestAssertions

  alias Hydromel.Orders

  describe "cooperative settings" do
    test "get_setting!/0 creates default settings when none exist" do
      setting = Orders.get_setting!()
      assert setting.key == "default"
      assert setting.price_33cl_cents == 450
      assert setting.price_75cl_cents == 900
      assert setting.sales_open == true
      assert setting.price_33cl_euros == "4.50"
      assert setting.price_75cl_euros == "9.00"
    end

    test "update_setting/2 converts euro strings to cents and updates payment instructions" do
      setting = Orders.get_setting!()

      {:ok, updated} =
        Orders.update_setting(setting, %{
          "price_33cl_euros" => "5,20",
          "price_75cl_euros" => "10.50",
          "stock_33cl" => "40",
          "stock_75cl" => "25",
          "paypal_url" => "https://paypal.me/merhzinsa",
          "wero_instructions" => "Wero au 06 12 34 56 78"
        })

      assert updated.price_33cl_cents == 520
      assert updated.price_75cl_cents == 1050
      assert updated.stock_33cl == 40
      assert updated.stock_75cl == 25
      assert updated.paypal_url == "https://paypal.me/merhzinsa"
      assert updated.wero_instructions == "Wero au 06 12 34 56 78"
    end
  end

  describe "orders creation and email notification" do
    test "create_order/1 with valid attributes calculates total, creates order, and sends summary email" do
      setting = Orders.get_setting!()

      {:ok, _} =
        Orders.update_setting(setting, %{
          "price_33cl_euros" => "5.00",
          "price_75cl_euros" => "10.00"
        })

      attrs = %{
        "first_name" => "Camille",
        "last_name" => "Martin",
        "email" => "Camille.Martin@Exemple.fr",
        "qty_33cl" => 2,
        "qty_75cl" => 3,
        "payment_method" => "wero",
        "pickup_comment" => "Récupération samedi au marché"
      }

      assert {:ok, order} = Orders.create_order(attrs)
      assert String.starts_with?(order.reference, "MERH-")
      assert order.email == "camille.martin@exemple.fr"
      assert order.qty_33cl == 2
      assert order.qty_75cl == 3
      assert order.unit_price_33cl_cents == 500
      assert order.unit_price_75cl_cents == 1000
      assert order.total_cents == 4000
      assert order.payment_status == "pending"
      assert order.pickup_status == "pending"

      assert_email_sent(fn email ->
        assert email.subject =~ order.reference
        assert email.text_body =~ "40,00 €"
        assert email.text_body =~ "Récupération samedi au marché"
      end)
    end

    test "create_order/1 rejects orders with 0 bottles" do
      attrs = %{
        "first_name" => "Jean",
        "last_name" => "Dupont",
        "email" => "jean@exemple.fr",
        "qty_33cl" => 0,
        "qty_75cl" => 0,
        "payment_method" => "cash"
      }

      assert {:error, changeset} = Orders.create_order(attrs)

      assert "Veuillez sélectionner au moins une bouteille (33cl ou 75cl)" in errors_on(changeset).qty_33cl
    end

    test "create_order/1 enforces stock limits when configured" do
      setting = Orders.get_setting!()
      {:ok, _} = Orders.update_setting(setting, %{"stock_33cl" => 3, "stock_75cl" => 2})

      assert {:ok, _order1} =
               Orders.create_order(%{
                 "first_name" => "Alice",
                 "last_name" => "Durand",
                 "email" => "alice@exemple.fr",
                 "qty_33cl" => 2,
                 "qty_75cl" => 2,
                 "payment_method" => "paypal"
               })

      assert {:error, changeset} =
               Orders.create_order(%{
                 "first_name" => "Bob",
                 "last_name" => "Moreau",
                 "email" => "bob@exemple.fr",
                 "qty_33cl" => 2,
                 "qty_75cl" => 0,
                 "payment_method" => "cash"
               })

      assert "Stock insuffisant en 33cl (il reste 1 bouteille(s) disponible(s))" in errors_on(
               changeset
             ).qty_33cl
    end
  end

  describe "status toggles, stats and CSV export" do
    test "toggles payment and pickup statuses and computes accurate stats" do
      {:ok, order} =
        Orders.create_order(%{
          "first_name" => "Lucie",
          "last_name" => "Bernard",
          "email" => "lucie@exemple.fr",
          "qty_33cl" => 2,
          "qty_75cl" => 1,
          "payment_method" => "cash"
        })

      stats_initial = Orders.get_stats()
      assert stats_initial.active_orders_count == 1
      assert stats_initial.qty_33cl == 2
      assert stats_initial.qty_75cl == 1
      assert stats_initial.expected_cents == 1800
      assert stats_initial.paid_cents == 0

      {:ok, paid_order} = Orders.toggle_payment_status(order)
      assert paid_order.payment_status == "paid"

      {:ok, picked_order} = Orders.toggle_pickup_status(paid_order)
      assert picked_order.pickup_status == "picked_up"

      stats_after = Orders.get_stats()
      assert stats_after.paid_cents == 1800
      assert stats_after.picked_up_count == 1

      csv = Orders.export_orders_csv()
      assert csv =~ order.reference
      assert csv =~ "Lucie"
      assert csv =~ "Bernard"
    end
  end
end
