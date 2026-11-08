defmodule Hydromel.Repo do
  use Ecto.Repo,
    otp_app: :hydromel,
    adapter: Ecto.Adapters.Postgres
end
