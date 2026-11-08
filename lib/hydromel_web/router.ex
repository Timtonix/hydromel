defmodule HydromelWeb.Router do
  use HydromelWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HydromelWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :require_coop_auth do
    plug HydromelWeb.CoopAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", HydromelWeb do
    pipe_through :browser

    get "/up", PageController, :health

    live "/", OrderLive.New, :new
    live "/coop/login", CoopLive.Login, :login
    post "/coop/login", CoopSessionController, :create
    delete "/coop/logout", CoopSessionController, :delete

    live_session :coop_admin, on_mount: [{HydromelWeb.CoopAuth, :require_coop_auth}] do
      live "/coop", CoopLive.Dashboard, :index
    end
  end

  scope "/coop", HydromelWeb do
    pipe_through [:browser, :require_coop_auth]

    get "/export.csv", CoopSessionController, :export_csv
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:hydromel, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HydromelWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
