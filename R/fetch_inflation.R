build_inflation_series <- function(project_root) {
  catalog <- read_series_catalog(project_root)
  dates <- month_sequence("2010-01-01", current_month_start())

  inflation_shock <- list(
    list(center = "2022-10-01", width = 8, magnitude = 6.3),
    list(center = "2023-08-01", width = 7, magnitude = 1.5)
  )

  expected_prices <- make_series_frame(
    dates,
    "expected_selling_prices",
    "esp_industry",
    "Industry",
    "Euro Area",
    make_mock_series(
      dates,
      base = 7,
      amplitude = 9,
      cycles = 3.8,
      trend = -1.5,
      noise = 2.2,
      seed = 50,
      shocks = list(
        list(center = "2021-12-01", width = 9, magnitude = 35),
        list(center = "2023-10-01", width = 6, magnitude = -9)
      )
    ),
    unit = "balance",
    source = "synthetic seed"
  )

  expected_services <- make_series_frame(
    dates,
    "expected_selling_prices",
    "esp_services",
    "Services",
    "Euro Area",
    make_mock_series(
      dates,
      base = 10,
      amplitude = 6,
      cycles = 3.4,
      trend = 0.5,
      noise = 1.8,
      seed = 51,
      shocks = list(
        list(center = "2022-05-01", width = 10, magnitude = 18),
        list(center = "2024-01-01", width = 7, magnitude = -4)
      )
    ),
    unit = "balance",
    source = "synthetic seed"
  )

  wage_tracker <- make_series_frame(
    dates,
    "wage_tracker",
    "wage_tracker_ea",
    "ECB wage tracker",
    "Euro Area",
    make_mock_series(
      dates,
      base = 2.1,
      amplitude = 0.45,
      cycles = 2.4,
      trend = 0.6,
      noise = 0.16,
      seed = 52,
      shocks = list(
        list(center = "2023-03-01", width = 11, magnitude = 1.8),
        list(center = "2025-01-01", width = 8, magnitude = -0.5)
      )
    ),
    unit = "% y/y",
    source = "synthetic seed"
  )

  country_specs <- data.frame(
    series_id = c("hicp_de", "hicp_fr", "hicp_it", "hicp_es"),
    series_name = c("Germany", "France", "Italy", "Spain"),
    country = c("Germany", "France", "Italy", "Spain"),
    base = c(1.9, 1.6, 1.7, 1.8),
    amplitude = c(0.55, 0.45, 0.65, 0.75),
    seed = c(60, 61, 62, 63),
    stringsAsFactors = FALSE
  )

  regional <- do.call(rbind, lapply(seq_len(nrow(country_specs)), function(i) {
    spec <- country_specs[i, ]
    make_series_frame(
      dates,
      "regional_inflation",
      spec$series_id,
      spec$series_name,
      spec$country,
      make_mock_series(
        dates,
        base = spec$base,
        amplitude = spec$amplitude,
        cycles = 3.0,
        trend = 0.1,
        noise = 0.22,
        seed = spec$seed,
        shocks = inflation_shock
      ),
      unit = "% y/y",
      source = "synthetic seed"
    )
  }))

  hicp <- rbind(
    make_series_frame(
      dates,
      "hicp_headline_core",
      "hicp_headline",
      "Headline",
      "Euro Area",
      make_mock_series(
        dates,
        base = 1.8,
        amplitude = 0.6,
        cycles = 3.0,
        trend = 0.1,
        noise = 0.22,
        seed = 70,
        shocks = inflation_shock
      ),
      unit = "% y/y",
      source = "synthetic seed"
    ),
    make_series_frame(
      dates,
      "hicp_headline_core",
      "hicp_core",
      "Core",
      "Euro Area",
      make_mock_series(
        dates,
        base = 1.4,
        amplitude = 0.35,
        cycles = 2.6,
        trend = 0.25,
        noise = 0.15,
        seed = 71,
        shocks = list(
          list(center = "2023-03-01", width = 10, magnitude = 3.5),
          list(center = "2024-10-01", width = 7, magnitude = -0.6)
        )
      ),
      unit = "% y/y",
      source = "synthetic seed"
    )
  )

  components <- rbind(
    make_series_frame(
      dates,
      "hicp_components",
      "core_goods",
      "Core goods",
      "Euro Area",
      make_mock_series(
        dates,
        base = 0.8,
        amplitude = 0.5,
        cycles = 2.8,
        trend = 0.1,
        noise = 0.18,
        seed = 72,
        shocks = list(
          list(center = "2022-12-01", width = 9, magnitude = 4.2),
          list(center = "2024-02-01", width = 8, magnitude = -1.1)
        )
      ),
      unit = "% y/y",
      source = "synthetic seed"
    ),
    make_series_frame(
      dates,
      "hicp_components",
      "core_services",
      "Core services",
      "Euro Area",
      make_mock_series(
        dates,
        base = 1.8,
        amplitude = 0.35,
        cycles = 2.4,
        trend = 0.4,
        noise = 0.12,
        seed = 73,
        shocks = list(
          list(center = "2023-07-01", width = 12, magnitude = 2.0),
          list(center = "2025-01-01", width = 8, magnitude = -0.3)
        )
      ),
      unit = "% y/y",
      source = "synthetic seed"
    )
  )

  inflation <- apply_series_catalog(
    rbind(expected_prices, expected_services, wage_tracker, regional, hicp, components),
    catalog
  )
  write_csv_utf8(inflation, file.path(project_root, "data/processed/inflation_series.csv"))
  inflation
}
