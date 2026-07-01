build_scenario_market_series <- function(project_root) {
  raw_dir <- file.path(project_root, "data/raw")
  processed_path <- file.path(project_root, "data/processed/scenario_market_series.csv")
  public_path <- file.path(project_root, "public/data/scenario_market_series.csv")

  eurusd <- fetch_ecb_csv_series(
    "https://data-api.ecb.europa.eu/service/data/EXR/D.USD.EUR.SP00.A?startPeriod=2018-01-01&format=csvdata",
    file.path(raw_dir, "ecb_eurusd_daily.csv")
  )
  ea_2y <- fetch_ecb_csv_series(
    "https://data-api.ecb.europa.eu/service/data/YC/B.U2.EUR.4F.G_N_A.SV_C_YM.SR_2Y?startPeriod=2018-01-01&format=csvdata",
    file.path(raw_dir, "ecb_ea_yield_curve_2y_daily.csv")
  )
  us_2y <- fetch_fred_series("DGS2", file.path(raw_dir, "fred_dgs2.csv"))
  us_cpi_yoy <- make_fred_cpi_yoy(fetch_fred_series("CPIAUCSL", file.path(raw_dir, "fred_cpiaucsl.csv")))
  ea_hicp_yoy <- read_latest_hicp_yoy(project_root)

  dates <- Reduce(intersect, list(eurusd$date, ea_2y$date, us_2y$date))
  dates <- sort(as.Date(dates))
  dates <- dates[dates >= as.Date("2018-01-01")]
  if (!length(dates)) {
    stop("No overlapping dates for EURUSD, EA 2Y and US 2Y")
  }

  eurusd_values <- align_daily(eurusd, dates)
  ea_2y_values <- align_daily(ea_2y, dates)
  us_2y_values <- align_daily(us_2y, dates)
  ea_inflation <- carry_monthly(ea_hicp_yoy, dates)
  us_inflation <- carry_monthly(us_cpi_yoy, dates)

  real_diff <- (ea_2y_values - ea_inflation) - (us_2y_values - us_inflation)
  rows <- rbind(
    make_series_frame(
      dates,
      "scenario_eurusd_real_rates",
      "eurusd",
      "EURUSD",
      "Euro Area / US",
      eurusd_values,
      axis = "left",
      unit = "",
      source = "ECB Data Portal",
      source_url = "https://data.ecb.europa.eu/data/datasets/EXR/EXR.D.USD.EUR.SP00.A",
      frequency = "daily"
    ),
    make_series_frame(
      dates,
      "scenario_eurusd_real_rates",
      "real_2y_differential_ea_us",
      "EA-US 2Y real rate differential",
      "Euro Area / US",
      real_diff,
      axis = "right",
      unit = "pp",
      source = "ECB Data Portal; FRED",
      source_url = "https://data.ecb.europa.eu/data/datasets/YC/YC.B.U2.EUR.4F.G_N_A.SV_C_YM.SR_2Y",
      frequency = "daily",
      source_note = "Real proxy = 2Y nominal yield less latest available YoY CPI/HICP."
    )
  )

  write_csv_utf8(rows, processed_path)
  write_csv_utf8(rows, public_path)
  rows
}

fetch_ecb_csv_series <- function(url, raw_path) {
  text <- download_text_with_fallback(url)
  writeLines(text, raw_path, useBytes = TRUE)
  values <- utils::read.csv(text = text, stringsAsFactors = FALSE, check.names = FALSE)
  if (!all(c("TIME_PERIOD", "OBS_VALUE") %in% names(values))) {
    stop(sprintf("ECB response missing required columns for %s", url))
  }
  out <- data.frame(
    date = as.Date(values$TIME_PERIOD),
    value = as.numeric(values$OBS_VALUE),
    stringsAsFactors = FALSE
  )
  out <- out[is.finite(out$value) & !is.na(out$date), , drop = FALSE]
  out[order(out$date), , drop = FALSE]
}

fetch_fred_series <- function(series_id, raw_path) {
  url <- sprintf("https://fred.stlouisfed.org/graph/fredgraph.csv?id=%s", series_id)
  text <- download_text_with_fallback(url)
  if (!grepl("observation_date", text, fixed = TRUE)) {
    stop(sprintf("FRED response for %s did not contain CSV data", series_id))
  }
  writeLines(text, raw_path, useBytes = TRUE)
  values <- utils::read.csv(text = text, stringsAsFactors = FALSE, check.names = FALSE)
  value_col <- setdiff(names(values), "observation_date")[[1]]
  out <- data.frame(
    date = as.Date(values$observation_date),
    value = suppressWarnings(as.numeric(values[[value_col]])),
    stringsAsFactors = FALSE
  )
  out <- out[is.finite(out$value) & !is.na(out$date), , drop = FALSE]
  out[order(out$date), , drop = FALSE]
}

download_text_with_fallback <- function(url) {
  tmp <- tempfile(fileext = ".csv")
  curl_status <- tryCatch(
    system2("curl", c("-L", "--ssl-no-revoke", "--max-time", "60", "-o", tmp, url), stdout = FALSE, stderr = FALSE),
    error = function(error) 1
  )
  if (identical(curl_status, 0L) && file.exists(tmp) && file.info(tmp)$size > 0) {
    value <- paste(readLines(tmp, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    if (nzchar(value)) {
      return(value)
    }
  }

  value <- tryCatch(
    paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(error) ""
  )
  if (nzchar(value)) {
    return(value)
  }
  stop(sprintf("Could not download %s", url))
}

make_fred_cpi_yoy <- function(cpi) {
  cpi <- cpi[order(cpi$date), , drop = FALSE]
  lagged <- cpi
  lagged$date <- add_months(lagged$date, 12)
  merged <- merge(cpi, lagged, by = "date", suffixes = c("", "_lag"), sort = TRUE)
  data.frame(
    date = merged$date,
    value = (merged$value / merged$value_lag - 1) * 100,
    stringsAsFactors = FALSE
  )
}

read_latest_hicp_yoy <- function(project_root) {
  path <- file.path(project_root, "data/processed/inflation_series.csv")
  if (!file.exists(path)) {
    stop("Inflation series is required to compute the EA real-rate proxy")
  }
  values <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  values <- values[values$series_id == "hicp_headline_yoy_nsa", c("date", "value"), drop = FALSE]
  values$date <- as.Date(values$date)
  values$value <- as.numeric(values$value)
  values <- values[is.finite(values$value) & !is.na(values$date), , drop = FALSE]
  values[order(values$date), , drop = FALSE]
}

align_daily <- function(series, dates) {
  values <- series$value[match(dates, series$date)]
  if (anyNA(values)) {
    stop("Daily series has gaps on required overlapping dates")
  }
  values
}

carry_monthly <- function(series, dates) {
  series <- series[order(series$date), , drop = FALSE]
  idx <- findInterval(dates, series$date)
  out <- rep(NA_real_, length(dates))
  ok <- idx > 0
  out[ok] <- series$value[idx[ok]]
  if (any(!is.finite(out))) {
    first_ok <- which(is.finite(out))[1]
    if (is.na(first_ok)) stop("Monthly inflation series could not be carried forward")
    out[seq_len(first_ok - 1)] <- out[first_ok]
  }
  out
}
