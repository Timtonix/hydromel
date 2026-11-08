defmodule Hydromel.Orders.OrderNotifier do
  @moduledoc """
  Builds and delivers order confirmation emails for the Merhzinsa cooperative
  using `Swoosh.Email` and `Hydromel.Mailer`.
  """
  import Swoosh.Email

  alias Hydromel.Mailer
  alias Hydromel.Orders.{Order, Setting}

  @doc """
  Delivers the reservation summary email to the customer.
  """
  def deliver_order_confirmation(%Order{} = order, %Setting{} = setting) do
    sender_email =
      Application.get_env(:hydromel, :mailer_from_email, "contact@merhzinsa.coop")

    sender_name =
      Application.get_env(:hydromel, :mailer_from_name, "Coopérative Merhzinsa")

    email =
      new()
      |> to({"#{order.first_name} #{order.last_name}", order.email})
      |> from({sender_name, sender_email})
      |> subject("[Merhzinsa] Récapitulatif de votre réservation d'hydromel (#{order.reference})")
      |> text_body(build_text_body(order, setting))
      |> html_body(build_html_body(order, setting))

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  def format_euros(cents) when is_integer(cents) do
    euros = cents / 100

    :erlang.float_to_binary(euros, decimals: 2)
    |> String.replace(".", ",")
    |> Kernel.<>(" €")
  end

  def format_euros(_), do: "0,00 €"

  def payment_method_label("wero"), do: "Wero"
  def payment_method_label("paypal"), do: "PayPal"
  def payment_method_label("cash"), do: "Espèces (Cash)"
  def payment_method_label(other), do: other

  def payment_instructions("wero", %Setting{} = setting) do
    setting.wero_instructions ||
      "Effectuez votre règlement par Wero en indiquant votre référence de commande."
  end

  def payment_instructions("paypal", %Setting{} = setting) do
    base =
      setting.paypal_instructions ||
        "Effectuez votre règlement via PayPal en indiquant votre référence de commande."

    if is_binary(setting.paypal_url) and String.trim(setting.paypal_url) != "" do
      "#{base}\nLien PayPal : #{String.trim(setting.paypal_url)}"
    else
      base
    end
  end

  def payment_instructions("cash", %Setting{} = setting) do
    setting.cash_instructions ||
      "Réglez en espèces lors de la récupération de votre commande."
  end

  def payment_instructions(_, _), do: ""

  defp build_text_body(%Order{} = order, %Setting{} = setting) do
    lines_33 =
      if order.qty_33cl > 0 do
        subtotal = order.qty_33cl * order.unit_price_33cl_cents

        "- Bouteille(s) 33cl : #{order.qty_33cl} x #{format_euros(order.unit_price_33cl_cents)} = #{format_euros(subtotal)}\n"
      else
        ""
      end

    lines_75 =
      if order.qty_75cl > 0 do
        subtotal = order.qty_75cl * order.unit_price_75cl_cents

        "- Bouteille(s) 75cl : #{order.qty_75cl} x #{format_euros(order.unit_price_75cl_cents)} = #{format_euros(subtotal)}\n"
      else
        ""
      end

    comment_block =
      if is_binary(order.pickup_comment) and String.trim(order.pickup_comment) != "" do
        "\nModalités de récupération indiquées :\n#{order.pickup_comment}\n"
      else
        "\nModalités de récupération : Aucun commentaire particulier précisé.\n"
      end

    """
    Bonjour #{order.first_name} #{order.last_name},

    Merci pour votre réservation d'hydromel auprès de la coopérative Merhzinsa !
    Voici le récapitulatif de votre commande :

    Référence de commande : #{order.reference}
    --------------------------------------------------
    #{lines_33}#{lines_75}--------------------------------------------------
    TOTAL À RÉGLER : #{format_euros(order.total_cents)}

    Moyen de paiement choisi : #{payment_method_label(order.payment_method)}
    Instructions de règlement :
    #{payment_instructions(order.payment_method, setting)}
    (N'oubliez pas d'indiquer la référence #{order.reference} lors de votre paiement)
    #{comment_block}
    À très bientôt,
    L'équipe de la coopérative Merhzinsa
    """
  end

  defp build_html_body(%Order{} = order, %Setting{} = setting) do
    row_33 =
      if order.qty_33cl > 0 do
        subtotal = order.qty_33cl * order.unit_price_33cl_cents

        """
        <tr>
          <td style="padding: 10px 0; border-bottom: 1px solid #fde68a;">Bouteille Hydromel 33cl</td>
          <td style="padding: 10px 0; border-bottom: 1px solid #fde68a; text-align: center;">#{order.qty_33cl}</td>
          <td style="padding: 10px 0; border-bottom: 1px solid #fde68a; text-align: right;">#{format_euros(order.unit_price_33cl_cents)}</td>
          <td style="padding: 10px 0; border-bottom: 1px solid #fde68a; text-align: right; font-weight: 600;">#{format_euros(subtotal)}</td>
        </tr>
        """
      else
        ""
      end

    row_75 =
      if order.qty_75cl > 0 do
        subtotal = order.qty_75cl * order.unit_price_75cl_cents

        """
        <tr>
          <td style="padding: 10px 0; border-bottom: 1px solid #fde68a;">Bouteille Hydromel 75cl</td>
          <td style="padding: 10px 0; border-bottom: 1px solid #fde68a; text-align: center;">#{order.qty_75cl}</td>
          <td style="padding: 10px 0; border-bottom: 1px solid #fde68a; text-align: right;">#{format_euros(order.unit_price_75cl_cents)}</td>
          <td style="padding: 10px 0; border-bottom: 1px solid #fde68a; text-align: right; font-weight: 600;">#{format_euros(subtotal)}</td>
        </tr>
        """
      end

    paypal_button =
      if order.payment_method == "paypal" and is_binary(setting.paypal_url) and
           String.trim(setting.paypal_url) != "" do
        url =
          Phoenix.HTML.html_escape(String.trim(setting.paypal_url))
          |> Phoenix.HTML.safe_to_string()

        """
        <p style="margin-top: 12px;">
          <a href="#{url}" style="display: inline-block; background-color: #d97706; color: #ffffff; text-decoration: none; padding: 10px 18px; border-radius: 8px; font-weight: 600;">
            Régler via PayPal
          </a>
        </p>
        """
      else
        ""
      end

    escaped_comment =
      if is_binary(order.pickup_comment) and String.trim(order.pickup_comment) != "" do
        order.pickup_comment
        |> Phoenix.HTML.html_escape()
        |> Phoenix.HTML.safe_to_string()
      else
        "<em>Aucun commentaire précisé</em>"
      end

    escaped_instructions =
      payment_instructions(order.payment_method, setting)
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()
      |> String.replace("\n", "<br/>")

    """
    <!DOCTYPE html>
    <html lang="fr">
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #fffbeb; color: #1c1917; padding: 24px; margin: 0;">
      <div style="max-width: 600px; margin: 0 auto; background-color: #ffffff; border: 1px solid #fde68a; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 12px rgba(217, 119, 6, 0.08);">
        <div style="background: linear-gradient(135deg, #78350f, #b45309); color: #ffffff; padding: 28px 24px; text-align: center;">
          <p style="margin: 0; font-size: 12px; text-transform: uppercase; letter-spacing: 2px; color: #fde68a;">Coopérative Merhzinsa</p>
          <h1 style="margin: 8px 0 0 0; font-size: 24px;">Réservation confirmée</h1>
        </div>

        <div style="padding: 24px;">
          <p style="font-size: 16px; line-height: 1.5;">
            Bonjour <strong>#{Phoenix.HTML.html_escape(order.first_name) |> Phoenix.HTML.safe_to_string()} #{Phoenix.HTML.html_escape(order.last_name) |> Phoenix.HTML.safe_to_string()}</strong>,
          </p>
          <p style="font-size: 15px; line-height: 1.5; color: #44403c;">
            Merci pour votre commande d'hydromel ! Votre réservation a bien été enregistrée sous la référence :
          </p>

          <div style="background-color: #fef3c7; border: 1px dashed #d97706; border-radius: 10px; padding: 12px 16px; text-align: center; margin: 16px 0;">
            <span style="font-size: 13px; color: #92400e; display: block;">Référence de commande</span>
            <strong style="font-size: 22px; letter-spacing: 1px; color: #78350f;">#{order.reference}</strong>
          </div>

          <table style="width: 100%; border-collapse: collapse; margin-top: 20px; font-size: 14px;">
            <thead>
              <tr style="border-bottom: 2px solid #f59e0b; color: #78350f; text-align: left;">
                <th style="padding-bottom: 8px;">Format</th>
                <th style="padding-bottom: 8px; text-align: center;">Qté</th>
                <th style="padding-bottom: 8px; text-align: right;">Prix unit.</th>
                <th style="padding-bottom: 8px; text-align: right;">Sous-total</th>
              </tr>
            </thead>
            <tbody>
              #{row_33}
              #{row_75}
            </tbody>
            <tfoot>
              <tr>
                <td colspan="3" style="padding-top: 14px; font-weight: 700; font-size: 16px; color: #78350f;">Total à régler</td>
                <td style="padding-top: 14px; text-align: right; font-weight: 800; font-size: 18px; color: #b45309;">#{format_euros(order.total_cents)}</td>
              </tr>
            </tfoot>
          </table>

          <div style="margin-top: 24px; background-color: #fafaf9; border-left: 4px solid #d97706; padding: 16px; border-radius: 8px;">
            <h3 style="margin: 0 0 8px 0; font-size: 15px; color: #78350f;">
              Règlement hors-ligne : #{payment_method_label(order.payment_method)}
            </h3>
            <p style="margin: 0; font-size: 14px; line-height: 1.5; color: #44403c;">
              #{escaped_instructions}
            </p>
            #{paypal_button}
          </div>

          <div style="margin-top: 20px; padding: 14px; background-color: #fffbeb; border-radius: 8px; font-size: 14px;">
            <strong style="color: #78350f; display: block; margin-bottom: 4px;">Récupération de la commande :</strong>
            <span style="color: #44403c;">#{escaped_comment}</span>
          </div>

          <p style="margin-top: 28px; font-size: 14px; color: #57534e; line-height: 1.5;">
            À très bientôt,<br/>
            <strong>La coopérative Merhzinsa</strong>
          </p>
        </div>
      </div>
    </body>
    </html>
    """
  end
end
