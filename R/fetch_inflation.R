build_inflation_series <- function(project_root) {
  catalog <- read_series_catalog(project_root)
  hicp <- read_eurostat_hicp_rows()
  services_survey <- read_ec_services_prices_rows(project_root)

  expected_services <- services_survey
  hicp_services_expected <- hicp[hicp$series_id == "core_services", ]
  hicp_services_expected$chart_id <- "expected_selling_prices"
  hicp_services_expected$series_id <- "core_services_expected"
  hicp_services_expected$series_name <- "HICP - Services, % YoY"
  hicp_services_expected$axis <- "right"

  expected_chart <- rbind(expected_services, hicp_services_expected)
  headline_core <- hicp[hicp$series_id %in% c("hicp_headline", "hicp_core"), ]
  components <- hicp[hicp$series_id %in% c("core_goods", "core_services"), ]

  wage_tracker <- read_ecb_wage_tracker_rows()

  inflation <- apply_series_catalog(
    rbind(expected_chart, wage_tracker, headline_core, components),
    catalog
  )
  write_csv_utf8(inflation, file.path(project_root, "data/processed/inflation_series.csv"))
  inflation
}

read_eurostat_hicp_rows <- function() {
  definitions <- data.frame(
    dataset = c("teicp000", "teicp200", "teicp280", "teicp290"),
    chart_id = c("hicp_headline_core", "hicp_headline_core", "hicp_components", "hicp_components"),
    series_id = c("hicp_headline", "hicp_core", "core_services", "core_goods"),
    series_name = c(
      "HICP inflation rate",
      "Core HICP",
      "HICP - Services",
      "HICP - Non-energy industrial goods"
    ),
    source_url = c(
      "https://ec.europa.eu/eurostat/databrowser/product/view/teicp000?lang=en",
      "https://ec.europa.eu/eurostat/databrowser/product/view/teicp200?lang=en",
      "https://ec.europa.eu/eurostat/databrowser/view/teicp280/default/table?lang=en",
      "https://ec.europa.eu/eurostat/databrowser/product/view/teicp290?lang=en"
    ),
    stringsAsFactors = FALSE
  )

  history <- read_hicp_history_to_2025(getwd(), definitions)
  latest <- do.call(rbind, lapply(seq_len(nrow(definitions)), function(i) {
    read_eurostat_teicp_rows(definitions[i, ])
  }))
  latest$date <- as.Date(latest$date)
  latest <- latest[latest$date >= as.Date("2026-01-01"), ]
  latest$date <- format(latest$date, "%Y-%m-%d")

  combined <- rbind(history, latest)
  combined$date <- as.Date(combined$date)
  combined <- combined[order(combined$series_id, combined$date), ]
  combined <- combined[!duplicated(combined[, c("series_id", "date")], fromLast = TRUE), ]
  combined$date <- format(combined$date, "%Y-%m-%d")
  combined
}

read_hicp_history_to_2025 <- function(project_root, definitions) {
  workbook_path <- file.path(project_root, "data/raw/hicp_history_to_2025.xlsx")
  if (!file.exists(workbook_path)) {
    return(data.frame())
  }
  history <- openxlsx::read.xlsx(workbook_path, sheet = "history_to_2025")
  history$date <- as.Date(history$date, origin = "1899-12-30")
  history <- history[history$series_id %in% definitions$series_id & history$date < as.Date("2026-01-01"), ]
  history$source <- "Eurostat HICP"
  history$source_url <- definitions$source_url[match(history$series_id, definitions$series_id)]
  if (!"source_note" %in% names(history)) {
    history$source_note <- ""
  }
  history[, c("date", "chart_id", "series_id", "series_name", "country", "value", "axis", "unit", "source", "source_url", "frequency", "source_note")]
}

read_eurostat_teicp_rows <- function(definition) {
  url <- sprintf("https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/%s?lang=en&geo=EA20", definition$dataset)
  raw_dir <- file.path(getwd(), "data/raw")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  tmp <- file.path(raw_dir, sprintf("eurostat_%s.json", definition$dataset))
  command <- sprintf(
    "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -TimeoutSec 45 -Uri %s -OutFile %s",
    shQuote(url, type = "sh"),
    shQuote(normalizePath(tmp, winslash = "\\", mustWork = FALSE), type = "sh")
  )
  system2("powershell", c("-NoProfile", "-Command", command), stdout = FALSE, stderr = FALSE)
  json <- jsonlite::fromJSON(tmp, simplifyVector = FALSE)

  times <- names(sort(unlist(json$dimension$time$category$index)))
  dates <- as.Date(sprintf("%s-01", times))
  n_time <- length(times)
  n_geo <- length(unlist(json$dimension$geo$category$index))
  unit_index <- unlist(json$dimension$unit$category$index)
  unit_pos <- as.integer(unit_index[["PCH_M12"]])
  value_map <- unlist(json$value)
  idx <- unit_pos * n_geo * n_time + seq_len(n_time) - 1
  values <- rep(NA_real_, n_time)
  present <- as.character(idx) %in% names(value_map)
  values[present] <- as.numeric(value_map[as.character(idx[present])])
  valid <- !is.na(values)

  make_series_frame(
    dates[valid],
    definition$chart_id,
    definition$series_id,
    definition$series_name,
    "Euro Area",
    values[valid],
    unit = "% y/y",
    source = "Eurostat HICP",
    source_url = definition$source_url,
    frequency = "monthly"
  )
}

read_ec_services_prices_rows <- function(project_root) {
  zip_url <- "https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series/nace2_ecfin_2605/services_total_sa_nace2.zip"
  zip_path <- file.path(project_root, "data/raw/services_total_sa_nace2.zip")
  download_binary_url(zip_url, zip_path)
  extract_dir <- file.path(project_root, "data/raw/services_total_sa_nace2")
  dir.create(extract_dir, recursive = TRUE, showWarnings = FALSE)
  utils::unzip(zip_path, files = "services_total_sa_nace2.xlsx", exdir = extract_dir, overwrite = TRUE)
  workbook_path <- file.path(extract_dir, "services_total_sa_nace2.xlsx")

  values <- openxlsx::read.xlsx(workbook_path, sheet = "SERVICES MONTHLY", colNames = FALSE)
  headers <- as.character(unlist(values[1, ], use.names = FALSE))
  date_values <- as.Date(as.numeric(values[-1, 1]), origin = "1899-12-30")
  date_values <- as.Date(format(date_values, "%Y-%m-01"))
  column <- match("SERV.EA.TOT.6.BS.M", headers)
  if (is.na(column)) stop("Missing EC Services Survey series: SERV.EA.TOT.6.BS.M")
  survey <- suppressWarnings(as.numeric(values[-1, column]))
  valid <- !is.na(date_values) & !is.na(survey)
  lagged_dates <- add_months(date_values[valid], 6)

  make_series_frame(
    lagged_dates,
    "expected_selling_prices",
    "esp_services",
    "EC expected prices, 6m lag",
    "Euro Area",
    survey[valid],
    unit = "balance",
    source = "European Commission Business and Consumer Surveys",
    source_url = "https://economy-finance.ec.europa.eu/economic-forecast-and-surveys/business-and-consumer-surveys/download-business-and-consumer-survey-data/time-series_en"
  )
}

read_ecb_wage_tracker_rows <- function() {
  url <- "https://data-api.ecb.europa.eu/service/data/EWT/M.U2.N.WT.INWS._T.4F0.GY?format=csvdata"
  raw_dir <- file.path(getwd(), "data/raw")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  tmp <- file.path(raw_dir, "ecb_wage_tracker.csv")
  command <- sprintf(
    "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -TimeoutSec 45 -Uri %s -OutFile %s",
    shQuote(url, type = "sh"),
    shQuote(normalizePath(tmp, winslash = "\\", mustWork = FALSE), type = "sh")
  )
  tryCatch(system2("powershell", c("-NoProfile", "-Command", command), stdout = FALSE, stderr = FALSE), error = function(e) NULL)

  if (!file.exists(tmp) || file.info(tmp)$size == 0) {
    return(data.frame())
  }

  raw <- utils::read.csv(tmp, stringsAsFactors = FALSE, check.names = FALSE)
  if (!all(c("TIME_PERIOD", "OBS_VALUE") %in% names(raw))) {
    return(data.frame())
  }

  dates <- as.Date(sprintf("%s-01", raw$TIME_PERIOD))
  values <- suppressWarnings(as.numeric(raw$OBS_VALUE))
  valid <- !is.na(dates) & !is.na(values)

  make_series_frame(
    dates[valid],
    "wage_tracker",
    "wage_tracker_ea",
    "ECB wage tracker",
    "Euro Area",
    values[valid],
    unit = "% y/y",
    source = "ECB Data Portal",
    source_url = "https://data.ecb.europa.eu/data/datasets/EWT/EWT.M.U2.N.WT.INWS._T.4F0.GY",
    frequency = "monthly"
  )
}
