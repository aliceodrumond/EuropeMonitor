build_activity_series <- function(project_root) {
  dates <- month_sequence("2003-01-01", current_month_start())

  pmi_shocks <- list(
    list(center = "2009-02-01", width = 4, magnitude = -11),
    list(center = "2012-08-01", width = 7, magnitude = -4),
    list(center = "2020-04-01", width = 2, magnitude = -14),
    list(center = "2022-09-01", width = 8, magnitude = -3)
  )

  pmi_specs <- data.frame(
    series_id = c("pmi_ea", "pmi_de", "pmi_fr", "pmi_es", "pmi_uk", "pmi_it"),
    series_name = c("Europe", "Germany", "France", "Spain", "UK", "Italy"),
    country = c("Euro Area", "Germany", "France", "Spain", "United Kingdom", "Italy"),
    base = c(52.3, 51.7, 51.5, 52.0, 52.5, 51.9),
    amplitude = c(3.5, 3.8, 3.4, 4.0, 3.6, 3.7),
    seed = c(10, 11, 12, 13, 14, 15),
    stringsAsFactors = FALSE
  )

  pmi_rows <- do.call(rbind, lapply(seq_len(nrow(pmi_specs)), function(i) {
    spec <- pmi_specs[i, ]
    values <- make_mock_series(
      dates,
      base = spec$base,
      amplitude = spec$amplitude,
      cycles = 4.7,
      trend = -0.4,
      noise = 1.2,
      seed = spec$seed,
      shocks = pmi_shocks
    )
    make_series_frame(
      dates,
      chart_id = "pmi_composite",
      series_id = spec$series_id,
      series_name = spec$series_name,
      country = spec$country,
      values = clip_values(values, 35, 65),
      unit = "index",
      source = "SP Global PMI - placeholder series"
    )
  }))


  pmi_manufacturing_rows <- do.call(rbind, lapply(seq_len(nrow(pmi_specs)), function(i) {
    spec <- pmi_specs[i, ]
    values <- make_mock_series(
      dates,
      base = spec$base - 1.4,
      amplitude = spec$amplitude + 0.8,
      cycles = 5.1,
      trend = -0.7,
      noise = 1.35,
      seed = spec$seed + 100,
      shocks = pmi_shocks
    )
    make_series_frame(
      dates,
      chart_id = "pmi_manufacturing",
      series_id = sub("^pmi_", "pmi_mfg_", spec$series_id),
      series_name = spec$series_name,
      country = spec$country,
      values = clip_values(values, 30, 65),
      unit = "index",
      source = "SP Global PMI - placeholder series"
    )
  }))

  pmi_services_rows <- do.call(rbind, lapply(seq_len(nrow(pmi_specs)), function(i) {
    spec <- pmi_specs[i, ]
    values <- make_mock_series(
      dates,
      base = spec$base + 0.9,
      amplitude = spec$amplitude - 0.3,
      cycles = 4.4,
      trend = -0.1,
      noise = 1.0,
      seed = spec$seed + 200,
      shocks = pmi_shocks
    )
    make_series_frame(
      dates,
      chart_id = "pmi_services",
      series_id = sub("^pmi_", "pmi_srv_", spec$series_id),
      series_name = spec$series_name,
      country = spec$country,
      values = clip_values(values, 32, 66),
      unit = "index",
      source = "SP Global PMI - placeholder series"
    )
  }))

  pmi_sentix <- make_mock_series(
    dates,
    base = 52,
    amplitude = 3.7,
    cycles = 4.8,
    trend = -0.3,
    noise = 1.0,
    seed = 20,
    shocks = pmi_shocks
  )

  sentix <- make_mock_series(
    dates,
    base = -2,
    amplitude = 18,
    cycles = 4.8,
    trend = -2,
    noise = 5.5,
    seed = 21,
    shocks = list(
      list(center = "2009-02-01", width = 4, magnitude = -30),
      list(center = "2020-04-01", width = 2, magnitude = -36),
      list(center = "2022-09-01", width = 7, magnitude = -18)
    )
  )
  sentix[dates == max(dates)] <- -13.372

  sentix_rows <- rbind(
    make_series_frame(
      dates,
      "sentix_pmi",
      "pmi_ea_sentix",
      "PMI Composite",
      "Euro Area",
      clip_values(pmi_sentix, 35, 65),
      unit = "index",
      source = "SP Global PMI - placeholder series"
    ),
    make_series_frame(
      dates,
      "sentix_pmi",
      "sentix_ea",
      "Sentix",
      "Euro Area",
      clip_values(sentix, -55, 50),
      axis = "right",
      unit = "balance",
      source = "Sentix - latest point manually set to -13.372"
    )
  )

  weekly <- make_series_frame(
    dates,
    "weekly_activity",
    "wai_ea",
    "Euro Area WAI",
    "Euro Area",
    make_mock_series(
      dates,
      base = 0,
      amplitude = 0.9,
      cycles = 5.2,
      trend = 0.1,
      noise = 0.35,
      seed = 30,
      shocks = list(
        list(center = "2009-02-01", width = 5, magnitude = -2.2),
        list(center = "2020-04-01", width = 2, magnitude = -4.6),
        list(center = "2022-10-01", width = 8, magnitude = -0.8)
      )
    ),
    unit = "z-score",
    source = "placeholder data, pending source integration"
  )

  toll <- make_series_frame(
    dates,
    "toll_mileage",
    "toll_de",
    "Germany toll mileage",
    "Germany",
    make_mock_series(
      dates,
      base = 101,
      amplitude = 5.2,
      cycles = 3.8,
      trend = 2.4,
      noise = 1.0,
      seed = 31,
      shocks = list(
        list(center = "2020-04-01", width = 2, magnitude = -16),
        list(center = "2022-08-01", width = 7, magnitude = -5)
      )
    ),
    unit = "index",
    source = "placeholder data, pending source integration"
  )

  financial <- make_series_frame(
    dates,
    "financial_conditions",
    "fci_ea",
    "Euro Area FCI",
    "Euro Area",
    make_mock_series(
      dates,
      base = 0,
      amplitude = 0.8,
      cycles = 4.4,
      trend = 0.1,
      noise = 0.28,
      seed = 32,
      shocks = list(
        list(center = "2008-10-01", width = 5, magnitude = 2.3),
        list(center = "2012-07-01", width = 8, magnitude = 1.2),
        list(center = "2020-03-01", width = 2, magnitude = 1.7),
        list(center = "2022-09-01", width = 8, magnitude = 1.2)
      )
    ),
    unit = "z-score",
    source = "placeholder data, pending source integration"
  )

  gdp <- make_series_frame(
    dates,
    "gdp",
    "gdp_ea",
    "Euro Area GDP",
    "Euro Area",
    make_mock_series(
      dates,
      base = 1.5,
      amplitude = 1.2,
      cycles = 3.7,
      trend = -0.2,
      noise = 0.32,
      seed = 33,
      shocks = list(
        list(center = "2009-04-01", width = 4, magnitude = -5.2),
        list(center = "2020-05-01", width = 2, magnitude = -12),
        list(center = "2021-05-01", width = 4, magnitude = 5.0)
      )
    ),
    unit = "% y/y",
    source = "placeholder data, pending source integration"
  )

  activity <- rbind(
    pmi_rows,
    pmi_manufacturing_rows,
    pmi_services_rows,
    sentix_rows,
    weekly,
    toll,
    financial,
    gdp
  )
  write_csv_utf8(activity, file.path(project_root, "data/processed/activity_series.csv"))
  activity
}
