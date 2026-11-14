defmodule Hydromel.OrdersTest do
  use Hydromel.DataCase, async: true

  import Swoosh.TestAssertions

  alias Hydromel.Orders

  describe "cooperative settings" do
    test "get_setting!/0 creates default settings with 6€ for 75cl and 35L target" do
      setting = Orders.get_setting!()
      assert setting.key == "default"
      assert setting.price_33cl_cents == 350
      assert setting.price_75cl_cents == 600
      assert setting.target_liters == 35.0
      assert setting.sales_open == true
      assert setting.price_33cl_euros == "3.50"
      assert setting.price_75cl_euros == "6.00"
    end

    test "update_setting/2 converts euro strings to cents and updates payment instructions" do
      setting = Orders.get_setting!()

      {:ok, updated} =
        Orders.update_setting(setting, %{
          "price_33cl_euros" => "4,00",
          "price_75cl_euros" => "6.00",
          "target_liters" => "40.0",
          "stock_33cl" => "40",
          "stock_75cl" => "25",
          "paypal_url" => "https://paypal.me/merhzinsa",
          "wero_instructions" => "Wero au 06 12 34 56 78"
        })

      assert updated.price_33cl_cents == 400
      assert updated.price_75cl_cents == 600
      assert updated.target_liters == 40.0
      assert updated.stock_33cl == 40
      assert updated.stock_75cl == 25
      assert updated.paypal_url == "https://paypal.me/merhzinsa"
      assert updated.wero_instructions == "Wero au 06 12 34 56 78"
    end
  end

  describe "member free 1st bottle, referral codes, custom labels and leaderboard" do
    test "1st order with member code grants 1 free 75cl bottle + free custom label (0€), subsequent orders apply -1€/bottle" do
      {:ok, thomas} =
        Orders.create_coop_member(%{"name" => "Thomas", "referral_code" => "THOMAS"})

      {:ok, lea} = Orders.create_coop_member(%{"name" => "Léa", "referral_code" => ""})

      assert thomas.referral_code == "THOMAS"
      assert String.starts_with?(lea.referral_code, "LEA")
      assert Orders.member_free_bottle_available?(thomas) == true

      label_upload = %{
        filename: "label-test.png",
        original_name: "mon_sticker.png",
        content_type: "image/png"
      }

      # 1st order with THOMAS: Thomas orders his own 1x 75cl bottle + custom label => 0,00 € (0 cents)
      assert {:ok, member_order} =
               Orders.create_order(
                 %{
                   "first_name" => "Thomas",
                   "last_name" => "Membre",
                   "email" => "thomas@merhzinsa.fr",
                   "qty_33cl" => 0,
                   "qty_75cl" => 1,
                   "referral_code_used" => "thomas",
                   "custom_label" => true,
                   "custom_label_text" => "Cuvée de Thomas",
                   "payment_method" => "cash"
                 },
                 label_upload
               )

      assert member_order.coop_member_id == thomas.id
      assert member_order.discount_cents == 600
      assert member_order.custom_label_fee_cents == 0
      assert member_order.total_cents == 0
      assert member_order.payment_status == "paid"
      assert Orders.member_free_bottle_available?(thomas) == false

      assert_email_sent(fn email ->
        assert email.subject =~ member_order.reference
        assert email.text_body =~ "Cuvée de Thomas"
      end)

      # 2nd order with THOMAS (a friend referred by Thomas): 2x 75cl (12€) with -1€/bottle (-2€) => 10,00 € (1000 cents)
      assert {:ok, referred_order} =
               Orders.create_order(%{
                 "first_name" => "Camille",
                 "last_name" => "Martin",
                 "email" => "camille@exemple.fr",
                 "qty_33cl" => 0,
                 "qty_75cl" => 2,
                 "referral_code_used" => "THOMAS",
                 "payment_method" => "wero"
               })

      assert referred_order.coop_member_id == thomas.id
      assert referred_order.discount_cents == 200
      assert referred_order.custom_label_fee_cents == 0
      assert referred_order.total_cents == 1000

      assert_email_sent(fn email ->
        assert email.subject =~ referred_order.reference
      end)

      # Verify leaderboard ranking by liters sold (excluding Thomas's own free 75cl bottle)
      leaderboard = Orders.list_leaderboard()
      [first, second] = leaderboard
      assert first.member.id == thomas.id
      assert first.member_bottle_claimed? == true
      assert first.total_liters == 1.5
      assert first.total_bottles == 2

      assert second.member.id == lea.id
      assert second.member_bottle_claimed? == false
      assert second.total_liters == 0.0
    end

    test "rejects unknown referral code" do
      assert {:error, changeset} =
               Orders.create_order(%{
                 "first_name" => "Jean",
                 "last_name" => "Dupont",
                 "email" => "jean@exemple.fr",
                 "qty_33cl" => 0,
                 "qty_75cl" => 1,
                 "referral_code_used" => "INCONNU99",
                 "payment_method" => "cash"
               })

      assert "Code de parrainage inconnu" in errors_on(changeset).referral_code_used
    end
  end

  describe "orders validation, stock and 35L volume limit" do
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

    test "create_order/1 enforces total target_liters (35L)" do
      setting = Orders.get_setting!()
      {:ok, _} = Orders.update_setting(setting, %{"target_liters" => 1.5})

      assert {:ok, _} =
               Orders.create_order(%{
                 "first_name" => "Alice",
                 "last_name" => "Durand",
                 "email" => "alice@exemple.fr",
                 "qty_33cl" => 0,
                 "qty_75cl" => 2,
                 "payment_method" => "cash"
               })

      assert {:error, changeset} =
               Orders.create_order(%{
                 "first_name" => "Bob",
                 "last_name" => "Moreau",
                 "email" => "bob@exemple.fr",
                 "qty_33cl" => 0,
                 "qty_75cl" => 1,
                 "payment_method" => "cash"
               })

      assert Enum.any?(errors_on(changeset).qty_75cl, &(&1 =~ "Volume disponible dépassé"))
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

      # 2 * 3.50€ + 1 * 6.00€ = 13.00€ (1300 cents)
      stats_initial = Orders.get_stats()
      assert stats_initial.active_orders_count == 1
      assert stats_initial.qty_33cl == 2
      assert stats_initial.qty_75cl == 1
      assert stats_initial.expected_cents == 1300
      assert stats_initial.paid_cents == 0

      {:ok, paid_order} = Orders.toggle_payment_status(order)
      assert paid_order.payment_status == "paid"

      {:ok, picked_order} = Orders.toggle_pickup_status(paid_order)
      assert picked_order.pickup_status == "picked_up"

      stats_after = Orders.get_stats()
      assert stats_after.paid_cents == 1300
      assert stats_after.picked_up_count == 1

      csv = Orders.export_orders_csv()
      assert csv =~ order.reference
      assert csv =~ "Lucie"
      assert csv =~ "Bernard"
    end
  end
end
