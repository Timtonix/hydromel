import Config

if System.get_env("PHX_SERVER") do
  config :hydromel, HydromelWeb.Endpoint, server: true
end

non_empty_env = fn key ->
  case System.get_env(key) do
    nil -> nil
    val -> if String.trim(val) == "", do: nil, else: String.trim(val)
  end
end

first_env = fn keys ->
  Enum.find_value(keys, fn key -> non_empty_env.(key) end)
end

resolved_smtp_user =
  first_env.([
    "SMTP_USER",
    "SMTP_USERNAME",
    "SMTP_LOGIN",
    "SMTP_EMAIL",
    "MAIL_USER",
    "MAIL_USERNAME",
    "GMAIL_USER",
    "GMAIL_USERNAME"
  ])

resolved_from_email =
  first_env.([
    "MAILER_FROM_EMAIL",
    "SMTP_FROM_EMAIL",
    "SMTP_FROM",
    "FROM_EMAIL",
    "MAIL_FROM"
  ]) || resolved_smtp_user || "contact@merhzinsa.coop"

resolved_from_name =
  first_env.([
    "MAILER_FROM_NAME",
    "SMTP_FROM_NAME",
    "FROM_NAME",
    "MAIL_FROM_NAME"
  ]) || "Cercle des Druides Merhzinsa"

config :hydromel,
  coop_password: non_empty_env.("COOP_PASSWORD") || "merhzinsa",
  mailer_from_email: resolved_from_email,
  mailer_from_name: resolved_from_name,
  uploads_dir: non_empty_env.("UPLOADS_DIR")

config :hydromel, HydromelWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  config :hydromel, HydromelWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        ~r"priv/gettext/.*\.po$"E,
        ~r"lib/hydromel_web/router\.ex$"E,
        ~r"lib/hydromel_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :hydromel, Hydromel.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"

  config :hydromel, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :hydromel, HydromelWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  cond do
    smtp_host = first_env.(["SMTP_HOST", "SMTP_RELAY", "MAIL_HOST"]) ->
      smtp_port = String.to_integer(first_env.(["SMTP_PORT", "MAIL_PORT"]) || "587")

      smtp_pass =
        first_env.([
          "SMTP_PASS",
          "SMTP_PASSWORD",
          "MAIL_PASS",
          "MAIL_PASSWORD",
          "GMAIL_PASS",
          "GMAIL_PASSWORD",
          "MAILER_PASSWORD"
        ])

      smtp_user = resolved_smtp_user || if(smtp_pass, do: resolved_from_email, else: nil)

      transport_opts =
        if smtp_port == 465 do
          [
            ssl: true,
            tls: :never,
            sockopts: [versions: [:"tlsv1.2", :"tlsv1.3"], verify: :verify_none]
          ]
        else
          [
            ssl: false,
            tls: :always,
            tls_options: [versions: [:"tlsv1.2", :"tlsv1.3"], verify: :verify_none]
          ]
        end

      base_smtp_opts =
        [
          adapter: Swoosh.Adapters.SMTP,
          relay: smtp_host,
          port: smtp_port
        ] ++ transport_opts

      auth_opts =
        if smtp_user && smtp_pass do
          [auth: :always, username: smtp_user, password: String.replace(smtp_pass, " ", "")]
        else
          [auth: :never]
        end

      config :hydromel, Hydromel.Mailer, Keyword.merge(base_smtp_opts, auth_opts)

    resend_key = first_env.(["RESEND_API_KEY"]) ->
      config :hydromel, Hydromel.Mailer,
        adapter: Swoosh.Adapters.Resend,
        api_key: resend_key

    brevo_key = first_env.(["BREVO_API_KEY"]) ->
      config :hydromel, Hydromel.Mailer,
        adapter: Swoosh.Adapters.Brevo,
        api_key: brevo_key

    true ->
      config :hydromel, Hydromel.Mailer, adapter: Swoosh.Adapters.Local
  end
end
