project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)

source(file.path(project_root, "R/helpers.R"), local = TRUE)
source(file.path(project_root, "R/fetch_scenario_market.R"), local = TRUE)

eurusd <- fetch_ecb_csv_series(
  "https://data-api.ecb.europa.eu/service/data/EXR/D.USD.EUR.SP00.A?startPeriod=2018-01-01&format=csvdata",
  file.path(project_root, "data/raw/ecb_eurusd_daily.csv")
)
ea_2y <- fetch_ecb_csv_series(
  "https://data-api.ecb.europa.eu/service/data/YC/B.U2.EUR.4F.G_N_A.SV_C_YM.SR_2Y?startPeriod=2018-01-01&format=csvdata",
  file.path(project_root, "data/raw/ecb_ea_yield_curve_2y_daily.csv")
)
us_2y <- fetch_fred_series("DGS2", file.path(project_root, "data/raw/fred_dgs2.csv"))
us_cpi_yoy <- make_fred_cpi_yoy(fetch_fred_series("CPIAUCSL", file.path(project_root, "data/raw/fred_cpiaucsl.csv")))
ea_hicp_yoy <- read_latest_hicp_yoy(project_root)

dates <- sort(as.Date(Reduce(intersect, list(eurusd$date, ea_2y$date, us_2y$date))))
dates <- dates[dates >= as.Date("2018-01-01")]

out <- data.frame(
  date = dates,
  eurusd = align_daily(eurusd, dates),
  ea_2y_nominal = align_daily(ea_2y, dates),
  us_2y_nominal = align_daily(us_2y, dates),
  ea_hicp_yoy = carry_monthly(ea_hicp_yoy, dates),
  us_cpi_yoy = carry_monthly(us_cpi_yoy, dates)
)
out$ea_2y_real <- out$ea_2y_nominal - out$ea_hicp_yoy
out$us_2y_real <- out$us_2y_nominal - out$us_cpi_yoy
out$ea_us_2y_real_differential <- out$ea_2y_real - out$us_2y_real

dir.create(file.path(project_root, "reports"), showWarnings = FALSE)
output <- file.path(project_root, "reports/scenario_eurusd_2y_real_rate_differential_components.csv")
write.csv(out, output, row.names = FALSE, na = "")

cat(output, "\n")
print(tail(out, 5))
