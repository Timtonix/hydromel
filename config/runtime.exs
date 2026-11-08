import Config

if System.get_env("PHX_SERVER") do
  config :hydromel, HydromelWeb.Endpoint, server: true
end

config :hydromel,
  coop_password: System.get_env("COOP_PASSWORD") || "merhzinsa",
  mailer_from_email: System.get_env("MAILER_FROM_EMAIL") || "contact@merhzinsa.coop",
  mailer_from_name: System.get_env("MAILER_FROM_NAME") || "Coopérative Merhzinsa"

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
    smtp_host = System.get_env("SMTP_HOST") ->
      smtp_port = String.to_integer(System.get_env("SMTP_PORT", "587"))
      smtp_user = System.get_env("SMTP_USER")
      smtp_pass = System.get_env("SMTP_PASS")

      auth_opts =
        if smtp_user && smtp_pass do
          [auth: :always, username: smtp_user, password: smtp_pass]
        else
          [auth: :never]
        end

      config :hydromel, Hydromel.Mailer,
        adapter: Swoosh.Adapters.SMTP,
        relay: smtp_host,
        port: smtp_port,
        tls: :if_available,
        auth: Keyword.get(auth_opts, :auth),
        username: Keyword.get(auth_opts, :username),
        password: Keyword.get(auth_opts, :password)

    brevo_key = System.get_env("BREVO_API_KEY") ->
      config :hydromel, Hydromel.Mailer,
        adapter: Swoosh.Adapters.Brevo,
        api_key: brevo_key

    true ->
      config :hydromel, Hydromel.Mailer, adapter: Swoosh.Adapters.Local
  end
end
