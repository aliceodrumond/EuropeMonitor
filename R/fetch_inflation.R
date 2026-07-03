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
  hicp_rates <- read_hicp_rate_chart_rows(hicp)
  hicp_seasonality <- read_hicp_seasonality_rows()
  swiss_cpi <- read_swiss_cpi_rows()
  ces_expectations <- read_ecb_ces_inflation_expectations_rows()

  wage_tracker <- read_ecb_wage_tracker_rows()

  inflation <- apply_series_catalog(
    rbind(expected_chart, wage_tracker, headline_core, components, hicp_rates, hicp_seasonality, swiss_cpi, ces_expectations),
    catalog
  )
  write_csv_utf8(inflation, file.path(project_root, "data/processed/inflation_series.csv"))
  inflation
}

swiss_cpi_definitions <- function() {
  data.frame(
    chart_id = c("swiss_cpi_headline_rates", "swiss_cpi_core_rates", "swiss_cpi_goods_rates", "swiss_cpi_services_rates", "swiss_cpi_energy_fuels_rates"),
    seasonality_chart_id = c("swiss_cpi_headline_seasonality", "swiss_cpi_core_seasonality", "swiss_cpi_goods_seasonality", "swiss_cpi_services_seasonality", "swiss_cpi_energy_fuels_seasonality"),
    base_series_id = c("swiss_cpi_headline", "swiss_cpi_core", "swiss_cpi_goods", "swiss_cpi_services", "swiss_cpi_energy_fuels"),
    value_col = c("headline", "core", "goods", "services", "energy_fuels"),
    yoy_series_id = c("swiss_cpi_headline_yoy_nsa", "swiss_cpi_core_yoy_nsa", "swiss_cpi_goods_yoy_nsa", "swiss_cpi_services_yoy_nsa", "swiss_cpi_energy_fuels_yoy_nsa"),
    hoh_series_id = c("swiss_cpi_headline_hoh_saar", "swiss_cpi_core_hoh_saar", "swiss_cpi_goods_hoh_saar", "swiss_cpi_services_hoh_saar", "swiss_cpi_energy_fuels_hoh_saar"),
    qoq_series_id = c("swiss_cpi_headline_qoq_saar", "swiss_cpi_core_qoq_saar", "swiss_cpi_goods_qoq_saar", "swiss_cpi_services_qoq_saar", "swiss_cpi_energy_fuels_qoq_saar"),
    mom_series_id = c("swiss_cpi_headline_mom_saar", "swiss_cpi_core_mom_saar", "swiss_cpi_goods_mom_saar", "swiss_cpi_services_mom_saar", "swiss_cpi_energy_fuels_mom_saar"),
    title = c("Switzerland CPI Headline", "Switzerland CPI Core", "Switzerland CPI Goods", "Switzerland CPI Services", "Switzerland CPI Energy & Fuels"),
    stringsAsFactors = FALSE
  )
}

read_swiss_cpi_rows <- function() {
  definitions <- swiss_cpi_definitions()
  workbook <- read_swiss_cpi_workbook()
  do.call(rbind, lapply(seq_len(nrow(definitions)), function(i) {
    rbind(
      build_swiss_cpi_rate_rows(definitions[i, ], workbook),
      build_swiss_cpi_seasonality_rows(definitions[i, ], workbook)
    )
  }))
}

read_url_text <- function(url, timeout_seconds = 60) {
  curl <- Sys.which("curl.exe")
  if (nzchar(curl)) {
    output <- tryCatch(
      system2(
        curl,
        c("-L", "-f", "-s", "-S", "--ssl-no-revoke", "-m", as.character(timeout_seconds), url),
        stdout = TRUE,
        stderr = FALSE
      ),
      error = function(e) character()
    )
    if (length(output)) {
      return(paste(output, collapse = "\n"))
    }
  }

  tmp <- tempfile("fso_http_text_", tmpdir = tempdir(), fileext = ".html")
  on.exit(unlink(tmp), add = TRUE)
  ok <- tryCatch({
    utils::download.file(url, tmp, mode = "wb", quiet = TRUE, method = "libcurl")
    TRUE
  }, error = function(e) FALSE)
  if (!ok || !file.exists(tmp) || file.info(tmp)$size == 0) {
    return("")
  }
  paste(readLines(tmp, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

download_binary_file <- function(url, destination, timeout_seconds = 60) {
  curl <- Sys.which("curl.exe")
  if (nzchar(curl)) {
    ok <- tryCatch({
      command <- sprintf(
        '%s -L -f -s -S --ssl-no-revoke -m %s -o %s %s',
        shQuote(curl, type = "cmd"),
        as.character(timeout_seconds),
        shQuote(normalizePath(destination, winslash = "\\", mustWork = FALSE), type = "cmd"),
        shQuote(url, type = "cmd")
      )
      status <- system(command)
      identical(status, 0L)
    }, error = function(e) FALSE)
    if (ok && file.exists(destination) && file.info(destination)$size > 0) {
      return(TRUE)
    }
  }

  tryCatch(
    utils::download.file(url, destination, mode = "wb", quiet = TRUE, method = "libcurl"),
    error = function(e) NULL
  )
  file.exists(destination) && file.info(destination)$size > 0
}

read_swiss_cpi_release_cache <- function(project_root) {
  cache_path <- file.path(project_root, "data/processed/fso_swiss_cpi_release_cache.json")
  if (!file.exists(cache_path) || !requireNamespace("jsonlite", quietly = TRUE)) {
    return(list())
  }
  tryCatch(jsonlite::fromJSON(cache_path, simplifyVector = FALSE), error = function(e) list())
}

write_swiss_cpi_release_cache <- function(project_root, cache) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(invisible(NULL))
  }
  cache_path <- file.path(project_root, "data/processed/fso_swiss_cpi_release_cache.json")
  jsonlite::write_json(cache, cache_path, auto_unbox = TRUE, pretty = TRUE)
  invisible(cache_path)
}

extract_first_match <- function(text, pattern) {
  match <- regexec(pattern, text, perl = TRUE)
  captures <- regmatches(text, match)[[1]]
  if (length(captures) < 2) {
    return(NA_character_)
  }
  captures[[2]]
}

extract_all_matches <- function(text, pattern) {
  matches <- gregexpr(pattern, text, perl = TRUE)
  values <- regmatches(text, matches)[[1]]
  unique(values[nzchar(values)])
}

parse_swiss_cpi_release_page <- function(html, page_url) {
  title_month <- extract_first_match(
    html,
    "<title>\\s*Swiss Consumer Price Index in ([A-Za-z]+\\s+[0-9]{4})\\s*-"
  )
  publication_raw <- extract_first_match(
    html,
    '<Attribute name="publicationdate">([0-9]{8})</Attribute>'
  )
  if (is.na(publication_raw)) {
    publication_raw <- gsub(
      "-",
      "",
      substr(extract_first_match(html, 'article:published_time" content="([0-9-]{10})T'), 1, 10)
    )
  }
  asset_urls <- extract_all_matches(
    html,
    "https://dam-api\\.bfs\\.admin\\.ch/hub/api/dam/assets/[0-9]+/master"
  )
  if (is.na(title_month) || !length(asset_urls)) {
    return(NULL)
  }

  release_month <- tryCatch(as.Date(paste0("01 ", title_month), format = "%d %B %Y"), error = function(e) as.Date(NA))
  publication_date <- tryCatch(as.Date(publication_raw, format = "%Y%m%d"), error = function(e) as.Date(NA))
  if (is.na(release_month) || is.na(publication_date)) {
    return(NULL)
  }

  list(
    page_url = page_url,
    title_month = title_month,
    release_month = release_month,
    publication_date = publication_date,
    asset_urls = asset_urls
  )
}

candidate_swiss_cpi_release_ids <- function(cache, publication_year) {
  cached_year <- suppressWarnings(as.integer(cache$publication_year %||% NA))
  cached_id <- suppressWarnings(as.integer(cache$gnpdetail_id %||% NA))
  if (!is.na(cached_year) && !is.na(cached_id) && cached_year == publication_year) {
    nearby <- cached_id + c(1L, 0L, 2L, -1L, 3L, -2L, 4L)
    return(nearby[nearby > 0L])
  }

  if (!is.na(cached_id) && !is.na(cached_year) && cached_year == (publication_year - 1L)) {
    return(1L:12L)
  }

  unique(c(58L:52L, 12L:1L))
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || is.na(x[1])) y else x
}

discover_swiss_cpi_release <- function(project_root) {
  today <- Sys.Date()
  publication_year <- as.integer(format(today, "%Y"))
  cache <- read_swiss_cpi_release_cache(project_root)
  candidates <- candidate_swiss_cpi_release_ids(cache, publication_year)
  for (candidate_id in candidates) {
    page_url <- sprintf(
      "https://www.bfs.admin.ch/bfs/en/home/statistics/prices/consumer-price-index/detailresultate.gnpdetail.%d-%04d.html",
      publication_year,
      candidate_id
    )
    html <- read_url_text(page_url, timeout_seconds = 25)
    if (!nzchar(html) || !grepl("Swiss Consumer Price Index in ", html, fixed = TRUE)) {
      next
    }

    parsed <- parse_swiss_cpi_release_page(html, page_url)
    if (is.null(parsed)) {
      next
    }
    if (parsed$publication_date > today) {
      next
    }
    parsed$gnpdetail_id <- candidate_id
    parsed$publication_year <- publication_year
    return(parsed)
  }
  NULL
}

download_swiss_cpi_workbook_candidate <- function(url, destination) {
  if (file.exists(destination)) {
    unlink(destination)
  }
  if (!download_binary_file(url, destination, timeout_seconds = 60)) {
    return(FALSE)
  }
  if (!requireNamespace("readxl", quietly = TRUE)) {
    return(FALSE)
  }

  sheets <- tryCatch(readxl::excel_sheets(destination), error = function(e) character())
  required_sheets <- c("INDEX_m", "VAR_m-1", "VAR_m-12")
  all(required_sheets %in% sheets)
}

read_swiss_cpi_workbook <- function() {
  if (!requireNamespace("readxl", quietly = TRUE)) {
    warning("Package 'readxl' is not available; skipping Swiss CPI data")
    return(list(index = data.frame(), mom_nsa = data.frame(), yoy_nsa = data.frame()))
  }

  project_root <- get_project_root()
  release <- discover_swiss_cpi_release(project_root)
  if (is.null(release)) {
    # Manual fallback if BFS changes the release-page structure:
    # start from https://www.bfs.admin.ch/bfs/en/home/statistics/prices/consumer-price-index.html
    # and open the CPI item that appears under "What's new", then follow the attributed
    # "Tables" documents until you reach the LIK25B25 Excel workbook for the latest month.
    warning("Swiss CPI release page discovery failed")
    return(list(index = data.frame(), mom_nsa = data.frame(), yoy_nsa = data.frame()))
  }

  raw_dir <- file.path(project_root, "data/raw")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  tmp <- file.path(raw_dir, "fso_swiss_cpi_lik25b25.xlsx")
  selected_url <- NA_character_
  for (asset_url in release$asset_urls) {
    if (download_swiss_cpi_workbook_candidate(asset_url, tmp)) {
      selected_url <- asset_url
      break
    }
  }

  if (is.na(selected_url) || !file.exists(tmp) || file.info(tmp)$size == 0) {
    # Manual fallback if workbook asset matching fails:
    # start from https://www.bfs.admin.ch/bfs/en/home/statistics/prices/consumer-price-index.html
    # and use the latest CPI release shown under "What's new" to locate the Excel manually.
    warning(sprintf("Swiss CPI workbook discovery failed for release page %s", release$page_url))
    return(list(index = data.frame(), mom_nsa = data.frame(), yoy_nsa = data.frame()))
  }

  asset_id <- extract_first_match(selected_url, "assets/([0-9]+)/master")
  write_swiss_cpi_release_cache(project_root, list(
    publication_year = release$publication_year,
    gnpdetail_id = release$gnpdetail_id,
    release_page_url = release$page_url,
    release_month = format(release$release_month, "%Y-%m-%d"),
    publication_date = format(release$publication_date, "%Y-%m-%d"),
    workbook_asset_url = selected_url,
    workbook_asset_id = asset_id
  ))
  message(sprintf(
    "Swiss CPI workbook discovered automatically: release=%s, asset=%s",
    release$page_url,
    selected_url
  ))

  list(
    index = read_swiss_cpi_sheet(tmp, "INDEX_m"),
    mom_nsa = read_swiss_cpi_sheet(tmp, "VAR_m-1"),
    yoy_nsa = read_swiss_cpi_sheet(tmp, "VAR_m-12")
  )
}

read_swiss_cpi_sheet <- function(path, sheet) {
  raw <- suppressWarnings(readxl::read_excel(path, sheet = sheet, col_names = FALSE, .name_repair = "minimal"))
  if (!nrow(raw) || ncol(raw) < 16) return(data.frame())

  date_serials <- suppressWarnings(as.numeric(as.character(unlist(raw[4, ]))))
  date_cols <- which(!is.na(date_serials) & date_serials > 30000)
  dates <- as.Date(date_serials[date_cols], origin = "1899-12-30")

  extract_row <- function(row_code = NULL, row_match = NULL) {
    if (!is.null(row_code)) {
      row_index <- which(as.character(unlist(raw[, 1])) == row_code)[1]
    } else {
      row_index <- grep(row_match, as.character(unlist(raw[, 12])), fixed = TRUE)[1]
    }
    if (is.na(row_index)) return(rep(NA_real_, length(date_cols)))
    suppressWarnings(as.numeric(as.character(unlist(raw[row_index, date_cols]))))
  }

  data.frame(
    date = dates,
    headline = extract_row(row_code = "100_100"),
    core = extract_row(row_match = "Core inflation 1"),
    goods = extract_row(row_code = "110_101"),
    services = extract_row(row_code = "110_102"),
    energy_fuels = extract_row(row_code = "1170_102"),
    stringsAsFactors = FALSE
  )
}

build_swiss_cpi_rate_rows <- function(definition, workbook) {
  index <- workbook$index
  yoy_nsa <- workbook$yoy_nsa
  if (!nrow(index) || !nrow(yoy_nsa)) return(data.frame())

  value_col <- definition$value_col
  source_url <- "https://www.bfs.admin.ch/bfs/en/home/statistics/prices/consumer-price-index.html"
  source_note <- "FSO CPI detailed results since 1982, CPI December 2025=100. Core is FSO Core inflation 1."

  yoy_values <- yoy_nsa[[value_col]]
  yoy_valid <- !is.na(yoy_values)
  yoy <- make_series_frame(
    yoy_nsa$date[yoy_valid],
    definition$chart_id,
    definition$yoy_series_id,
    "% YoY NSA",
    "Switzerland",
    yoy_values[yoy_valid],
    unit = "%",
    source = "Federal Statistical Office",
    source_url = source_url,
    frequency = "monthly",
    source_note = source_note
  )

  sa <- run_hicp_x12_adjustment(index$date, index[[value_col]])
  if (!nrow(sa)) return(yoy)
  sa <- sa[order(sa$date), ]
  sa$mom_saar <- (sa$index / c(NA, head(sa$index, -1)))^12 * 100 - 100
  sa$qoq_saar <- (sa$index / c(rep(NA, 3), head(sa$index, -3)))^4 * 100 - 100
  sa$hoh_saar <- (sa$index / c(rep(NA, 6), head(sa$index, -6)))^2 * 100 - 100

  make_sa <- function(series_id, series_name, values) {
    valid <- !is.na(values)
    make_series_frame(
      sa$date[valid],
      definition$chart_id,
      series_id,
      series_name,
      "Switzerland",
      values[valid],
      unit = "%",
      source = "Federal Statistical Office / Legacy X-13",
      source_url = source_url,
      frequency = "monthly",
      source_note = "Annualized rates calculated from a seasonally adjusted CPI index derived from FSO NSA CPI using X-13ARIMA-SEATS."
    )
  }

  rbind(
    yoy,
    make_sa(definition$hoh_series_id, "% HoH SAAR", sa$hoh_saar),
    make_sa(definition$qoq_series_id, "% QoQ SAAR", sa$qoq_saar),
    make_sa(definition$mom_series_id, "% MoM SAAR", sa$mom_saar)
  )
}

build_swiss_cpi_seasonality_rows <- function(definition, workbook) {
  mom_nsa <- workbook$mom_nsa
  if (!nrow(mom_nsa)) return(data.frame())
  value_col <- definition$value_col
  values <- mom_nsa[[value_col]]
  panel <- data.frame(
    date = mom_nsa$date,
    mom_nsa = values,
    year = as.integer(format(mom_nsa$date, "%Y")),
    month = as.integer(format(mom_nsa$date, "%m")),
    stringsAsFactors = FALSE
  )
  panel <- panel[!is.na(panel$mom_nsa), ]

  seasonal_panel <- do.call(rbind, lapply(2012:2026, function(target_year) {
    rows <- panel[(panel$year == target_year & panel$month %in% 1:12) | (panel$year == target_year - 1 & panel$month == 12), ]
    if (!nrow(rows)) return(data.frame())
    rows$seasonal_year <- target_year
    rows$seasonal_month <- ifelse(rows$year == target_year - 1 & rows$month == 12, 0, rows$month)
    rows
  }))
  history <- seasonal_panel[seasonal_panel$seasonal_year >= 2012 & seasonal_panel$seasonal_year <= 2025, ]
  if (!nrow(history)) return(data.frame())

  stats <- do.call(rbind, lapply(0:12, function(month_value) {
    month_values <- history$mom_nsa[history$seasonal_month == month_value]
    if (!length(month_values)) return(data.frame())
    data.frame(
      seasonal_month = month_value,
      min = min(month_values, na.rm = TRUE),
      median = stats::median(month_values, na.rm = TRUE),
      max = max(month_values, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))

  source_url <- "https://www.bfs.admin.ch/bfs/en/home/statistics/prices/consumer-price-index.html"
  make_swiss_seasonality_series <- function(months, series_id, series_name, values) {
    dates <- ifelse(as.integer(months) == 0, "1999-12-01", sprintf("2000-%02d-01", as.integer(months)))
    make_series_frame(
      as.Date(dates),
      definition$seasonality_chart_id,
      series_id,
      series_name,
      "Switzerland",
      values,
      unit = "% m/m NSA",
      source = "Federal Statistical Office",
      source_url = source_url,
      frequency = "monthly",
      source_note = "Seasonality chart uses Dec-1, Jan, ..., Dec on the x-axis. FSO CPI detailed results since 1982."
    )
  }

  selected <- seasonal_panel[seasonal_panel$seasonal_year %in% c(2022, 2025, 2026), ]
  selected_rows <- do.call(rbind, lapply(c(2022, 2025, 2026), function(target_year) {
    year_rows <- selected[selected$seasonal_year == target_year, ]
    if (!nrow(year_rows)) return(data.frame())
    make_swiss_seasonality_series(
      year_rows$seasonal_month,
      sprintf("%s_mom_nsa_%s", definition$base_series_id, target_year),
      as.character(target_year),
      year_rows$mom_nsa
    )
  }))

  rbind(
    make_swiss_seasonality_series(stats$seasonal_month, sprintf("%s_mom_nsa_range_min", definition$base_series_id), "2012-2025 min", stats$min),
    make_swiss_seasonality_series(stats$seasonal_month, sprintf("%s_mom_nsa_median", definition$base_series_id), "2012-2025 median", stats$median),
    make_swiss_seasonality_series(stats$seasonal_month, sprintf("%s_mom_nsa_range_max", definition$base_series_id), "2012-2025 max", stats$max),
    selected_rows
  )
}

build_inflation_flash_fast_series <- function(project_root) {
  catalog <- read_series_catalog(project_root)
  previous_path <- file.path(project_root, "data/processed/inflation_series.csv")
  if (!file.exists(previous_path)) {
    stop(sprintf("Missing previous inflation dataset for fast update: %s", previous_path))
  }

  previous <- utils::read.csv(previous_path, stringsAsFactors = FALSE, check.names = FALSE)
  hicp <- read_eurostat_hicp_rows()
  headline_core <- hicp[hicp$series_id %in% c("hicp_headline", "hicp_core"), ]
  components <- hicp[hicp$series_id %in% c("core_goods", "core_services"), ]
  hicp_rates <- read_hicp_rate_chart_rows(hicp, include_ecb_sa = FALSE)
  hicp_seasonality <- read_hicp_seasonality_rows()

  rate_charts <- c(
    "hicp_headline_rates",
    "hicp_core_rates",
    "hicp_goods_rates",
    "hicp_services_rates"
  )
  replacement_charts <- c(
    rate_charts,
    "hicp_headline_seasonality",
    "hicp_core_seasonality",
    "hicp_goods_seasonality",
    "hicp_services_seasonality",
    "hicp_headline_core",
    "hicp_components"
  )
  kept <- previous[!previous$chart_id %in% replacement_charts, , drop = FALSE]
  kept_ecb_sa <- previous[
    previous$chart_id %in% rate_charts &
      !grepl("_legacy$", previous$series_id) &
      !grepl("_yoy_nsa$", previous$series_id),
    ,
    drop = FALSE
  ]
  inflation <- apply_series_catalog(
    rbind(kept, kept_ecb_sa, headline_core, components, hicp_rates, hicp_seasonality),
    catalog
  )
  write_csv_utf8(inflation, file.path(project_root, "data/processed/inflation_series.csv"))
  inflation
}

read_ecb_ces_inflation_expectations_rows <- function() {
  definitions <- data.frame(
    key = c(
      "M.Z18.ALL.T.C1120.NUM_VAR.WM",
      "M.Z18.ALL.T.C1220.NUM_VAR.WM",
      "M.Z18.ALL.T.E2020.NUM_VAR.WM"
    ),
    series_id = c("ecb_ces_infl_exp_1y", "ecb_ces_infl_exp_3y", "ecb_ces_infl_exp_5y"),
    series_name = c("12M inflation expectations", "3Y inflation expectations", "5Y inflation expectations"),
    stringsAsFactors = FALSE
  )

  do.call(rbind, lapply(seq_len(nrow(definitions)), function(i) {
    read_ecb_ces_series_rows(definitions[i, ])
  }))
}

read_ecb_ces_series_rows <- function(definition) {
  url <- sprintf("https://data-api.ecb.europa.eu/service/data/CES/%s?format=csvdata", definition$key)
  raw_dir <- file.path(getwd(), "data/raw")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  tmp <- file.path(raw_dir, sprintf("ecb_ces_%s.csv", definition$series_id))
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
    "ecb_ces_inflation_expectations",
    definition$series_id,
    definition$series_name,
    "Euro Area",
    values[valid],
    unit = "%",
    source = "ECB Consumer Expectations Survey",
    source_url = sprintf("https://data.ecb.europa.eu/data/datasets/CES/CES.%s", definition$key),
    frequency = "monthly",
    source_note = "Weighted median, euro area 11."
  )
}

hicp_rate_definitions <- function() {
  data.frame(
    dataset = c("teicp000", "teicp200", "teicp290", "teicp280"),
    chart_id = c("hicp_headline_rates", "hicp_core_rates", "hicp_goods_rates", "hicp_services_rates"),
    seasonality_chart_id = c("hicp_headline_seasonality", "hicp_core_seasonality", "hicp_goods_seasonality", "hicp_services_seasonality"),
    coicop = c("CP00", "TOT_X_NRG_FOOD", "IGD_NNRG", "SERV"),
    base_series_id = c("hicp_headline", "hicp_core", "core_goods", "core_services"),
    yoy_series_id = c("hicp_headline_yoy_nsa", "hicp_core_yoy_nsa", "hicp_goods_yoy_nsa", "hicp_services_yoy_nsa"),
    hoh_series_id = c("hicp_headline_hoh_saar", "hicp_core_hoh_saar", "hicp_goods_hoh_saar", "hicp_services_hoh_saar"),
    qoq_series_id = c("hicp_headline_qoq_saar", "hicp_core_qoq_saar", "hicp_goods_qoq_saar", "hicp_services_qoq_saar"),
    mom_series_id = c("hicp_headline_mom_saar", "hicp_core_mom_saar", "hicp_goods_mom_saar", "hicp_services_mom_saar"),
    legacy_hoh_series_id = c("hicp_headline_hoh_saar_legacy", "hicp_core_hoh_saar_legacy", "hicp_goods_hoh_saar_legacy", "hicp_services_hoh_saar_legacy"),
    legacy_qoq_series_id = c("hicp_headline_qoq_saar_legacy", "hicp_core_qoq_saar_legacy", "hicp_goods_qoq_saar_legacy", "hicp_services_qoq_saar_legacy"),
    legacy_mom_series_id = c("hicp_headline_mom_saar_legacy", "hicp_core_mom_saar_legacy", "hicp_goods_mom_saar_legacy", "hicp_services_mom_saar_legacy"),
    ecb_key = c(
      "M.U2.Y.000000.4F0.INX",
      "M.U2.Y.XEF000.4F0.INX",
      "M.U2.Y.IGXE00.4F0.INX",
      "M.U2.Y.SERV00.4F0.INX"
    ),
    title = c("HICP Headline", "HICP Core", "HICP Goods", "HICP Services"),
    eurostat_url = c(
      "https://ec.europa.eu/eurostat/databrowser/product/view/teicp000?lang=en",
      "https://ec.europa.eu/eurostat/databrowser/product/view/teicp200?lang=en",
      "https://ec.europa.eu/eurostat/databrowser/product/view/teicp290?lang=en",
      "https://ec.europa.eu/eurostat/databrowser/view/teicp280/default/table?lang=en"
    ),
    stringsAsFactors = FALSE
  )
}

read_hicp_rate_chart_rows <- function(yoy_rows, include_ecb_sa = TRUE) {
  definitions <- hicp_rate_definitions()

  do.call(rbind, lapply(seq_len(nrow(definitions)), function(i) {
    build_hicp_rate_chart_rows(definitions[i, ], yoy_rows, include_ecb_sa = include_ecb_sa)
  }))
}

read_hicp_seasonality_rows <- function() {
  definitions <- hicp_rate_definitions()
  do.call(rbind, lapply(seq_len(nrow(definitions)), function(i) {
    build_hicp_seasonality_rows(definitions[i, ])
  }))
}

build_hicp_seasonality_rows <- function(definition) {
  eurostat_input <- read_eurostat_hicp_input_rows(definition)
  nsa <- read_eurostat_hicp_midx_index(definition$coicop, definition$base_series_id)
  nsa <- extend_hicp_nsa_index_with_flash(nsa, eurostat_input)
  if (nrow(nsa) < 24) return(data.frame())

  nsa <- nsa[order(nsa$date), ]
  nsa$mom_nsa <- nsa$nsa_index / c(NA, head(nsa$nsa_index, -1)) * 100 - 100
  nsa$year <- as.integer(format(nsa$date, "%Y"))
  nsa$month <- as.integer(format(nsa$date, "%m"))
  nsa <- nsa[!is.na(nsa$mom_nsa), ]

  seasonal_panel <- do.call(rbind, lapply(2012:2026, function(target_year) {
    rows <- nsa[(nsa$year == target_year & nsa$month %in% 1:12) | (nsa$year == target_year - 1 & nsa$month == 12), ]
    if (!nrow(rows)) return(data.frame())
    rows$seasonal_year <- target_year
    rows$seasonal_month <- ifelse(rows$year == target_year - 1 & rows$month == 12, 0, rows$month)
    rows
  }))

  history <- seasonal_panel[seasonal_panel$seasonal_year >= 2012 & seasonal_panel$seasonal_year <= 2025, ]
  if (!nrow(history)) return(data.frame())
  stats <- do.call(rbind, lapply(0:12, function(month_value) {
    values <- history$mom_nsa[history$seasonal_month == month_value]
    if (!length(values)) return(data.frame())
    data.frame(
      seasonal_month = month_value,
      min = min(values, na.rm = TRUE),
      median = stats::median(values, na.rm = TRUE),
      max = max(values, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))

  selected <- seasonal_panel[seasonal_panel$seasonal_year %in% c(2022, 2025, 2026), ]
  selected <- selected[selected$seasonal_month %in% 0:12, ]
  selected_rows <- do.call(rbind, lapply(c(2022, 2025, 2026), function(target_year) {
    year_rows <- selected[selected$seasonal_year == target_year, ]
    if (!nrow(year_rows)) return(data.frame())
    make_hicp_seasonality_series(
      year_rows$seasonal_month,
      definition$seasonality_chart_id,
      sprintf("%s_mom_nsa_%s", definition$base_series_id, target_year),
      as.character(target_year),
      year_rows$mom_nsa,
      definition$eurostat_url,
      "Eurostat HICP"
    )
  }))

  rbind(
    make_hicp_seasonality_series(stats$seasonal_month, definition$seasonality_chart_id, sprintf("%s_mom_nsa_range_min", definition$base_series_id), "2012-2025 min", stats$min, definition$eurostat_url, "Eurostat HICP"),
    make_hicp_seasonality_series(stats$seasonal_month, definition$seasonality_chart_id, sprintf("%s_mom_nsa_median", definition$base_series_id), "2012-2025 median", stats$median, definition$eurostat_url, "Eurostat HICP"),
    make_hicp_seasonality_series(stats$seasonal_month, definition$seasonality_chart_id, sprintf("%s_mom_nsa_range_max", definition$base_series_id), "2012-2025 max", stats$max, definition$eurostat_url, "Eurostat HICP"),
    selected_rows
  )
}

make_hicp_seasonality_series <- function(months, chart_id, series_id, series_name, values, source_url, source) {
  dates <- ifelse(
    as.integer(months) == 0,
    "1999-12-01",
    sprintf("2000-%02d-01", as.integer(months))
  )
  make_series_frame(
    as.Date(dates),
    chart_id,
    series_id,
    series_name,
    "Euro Area",
    values,
    unit = "% m/m NSA",
    source = source,
    source_url = source_url,
    frequency = "monthly",
    source_note = "Seasonality chart uses Dec-1, Jan, ..., Dec on the x-axis."
  )
}

build_hicp_rate_chart_rows <- function(definition, yoy_rows, include_ecb_sa = TRUE) {
  eurostat_input <- read_eurostat_hicp_input_rows(definition)
  yoy <- build_hicp_precise_yoy_rows(definition, yoy_rows, eurostat_input)
  if (!nrow(yoy)) {
    return(data.frame())
  }

  legacy <- build_hicp_legacy_x12_rows(definition, eurostat_input)
  if (!include_ecb_sa) {
    return(rbind(yoy, legacy))
  }

  sa_index <- read_ecb_hicp_sa_index_rows(definition)
  if (!nrow(sa_index)) return(rbind(yoy, legacy))
  sa_index <- sa_index[order(sa_index$date), ]
  sa_index$mom_saar <- (sa_index$index / c(NA, head(sa_index$index, -1)))^12 * 100 - 100
  sa_index$qoq_saar <- (sa_index$index / c(rep(NA, 3), head(sa_index$index, -3)))^4 * 100 - 100
  sa_index$hoh_saar <- (sa_index$index / c(rep(NA, 6), head(sa_index$index, -6)))^2 * 100 - 100

  mom_valid <- !is.na(sa_index$mom_saar)
  qoq_valid <- !is.na(sa_index$qoq_saar)
  hoh_valid <- !is.na(sa_index$hoh_saar)
  mom <- make_series_frame(
    sa_index$date[mom_valid],
    definition$chart_id,
    definition$mom_series_id,
    "% MoM SAAR",
    "Euro Area",
    sa_index$mom_saar[mom_valid],
    unit = "%",
    source = sa_index$source[mom_valid],
    source_url = sa_index$source_url[mom_valid],
    frequency = "monthly",
    source_note = sa_index$source_note[mom_valid]
  )
  hoh <- make_series_frame(
    sa_index$date[hoh_valid],
    definition$chart_id,
    definition$hoh_series_id,
    "% HoH SAAR",
    "Euro Area",
    sa_index$hoh_saar[hoh_valid],
    unit = "%",
    source = sa_index$source[hoh_valid],
    source_url = sa_index$source_url[hoh_valid],
    frequency = "monthly",
    source_note = sa_index$source_note[hoh_valid]
  )
  qoq <- make_series_frame(
    sa_index$date[qoq_valid],
    definition$chart_id,
    definition$qoq_series_id,
    "% QoQ SAAR",
    "Euro Area",
    sa_index$qoq_saar[qoq_valid],
    unit = "%",
    source = sa_index$source[qoq_valid],
    source_url = sa_index$source_url[qoq_valid],
    frequency = "monthly",
    source_note = sa_index$source_note[qoq_valid]
  )

  rbind(yoy, hoh, qoq, mom, legacy)
}

build_hicp_precise_yoy_rows <- function(definition, yoy_rows, eurostat_input) {
  fallback <- yoy_rows[yoy_rows$series_id == definition$base_series_id, ]
  if (!nrow(fallback)) {
    return(data.frame())
  }

  nsa <- read_eurostat_hicp_midx_index(definition$coicop, definition$base_series_id)
  if (!nrow(nsa) || !"nsa_index" %in% names(eurostat_input)) {
    yoy <- fallback
    yoy$chart_id <- definition$chart_id
    yoy$series_id <- definition$yoy_series_id
    yoy$series_name <- "% YoY NSA"
    yoy$unit <- "%"
    yoy$source_note <- ifelse(yoy$source_note == "", "Flash estimate is used until final HICP is available.", yoy$source_note)
    return(yoy)
  }

  index <- merge(
    nsa[, c("date", "nsa_index")],
    eurostat_input[, c("date", "nsa_index")],
    by = "date",
    all = TRUE,
    suffixes = c("_history", "_flash")
  )
  index <- index[order(index$date), ]

  common <- index[!is.na(index$nsa_index_history) & !is.na(index$nsa_index_flash) & index$nsa_index_history != 0, ]
  if (nrow(common)) {
    first_scale <- common$nsa_index_flash[1] / common$nsa_index_history[1]
    index$flash_backfill <- index$nsa_index_history * first_scale
  } else {
    index$flash_backfill <- NA_real_
  }
  index$precise_index <- ifelse(!is.na(index$nsa_index_flash), index$nsa_index_flash, index$flash_backfill)
  index$source <- ifelse(!is.na(index$nsa_index_flash), "Eurostat HICP", "Eurostat HICP backfilled flash base")
  index$source_note <- ifelse(
    !is.na(index$nsa_index_flash),
    "YoY calculated from Eurostat NSA HICP index to preserve two-decimal precision. Flash estimate is used until final HICP is available.",
    "YoY calculated from Eurostat NSA HICP index. Missing flash-base history is backfilled from the first common index overlap to preserve two-decimal precision."
  )
  index$yoy <- index$precise_index / c(rep(NA_real_, 12), head(index$precise_index, -12)) * 100 - 100

  valid <- !is.na(index$yoy)
  precise <- make_series_frame(
    index$date[valid],
    definition$chart_id,
    definition$yoy_series_id,
    "% YoY NSA",
    "Euro Area",
    index$yoy[valid],
    unit = "%",
    source = index$source[valid],
    source_url = definition$eurostat_url,
    frequency = "monthly",
    source_note = index$source_note[valid]
  )

  if (!nrow(precise)) {
    yoy <- fallback
    yoy$chart_id <- definition$chart_id
    yoy$series_id <- definition$yoy_series_id
    yoy$series_name <- "% YoY NSA"
    yoy$unit <- "%"
    yoy$source_note <- ifelse(yoy$source_note == "", "Flash estimate is used until final HICP is available.", yoy$source_note)
    return(yoy)
  }

  precise
}

build_hicp_legacy_x12_rows <- function(definition, eurostat_input) {
  if (!requireNamespace("seasonal", quietly = TRUE)) {
    warning("Package 'seasonal' is not available; skipping Legacy X-13/X-11 HICP seasonal adjustment")
    return(data.frame())
  }

  nsa <- read_eurostat_hicp_midx_index(definition$coicop, definition$base_series_id)
  nsa <- extend_hicp_nsa_index_with_flash(nsa, eurostat_input)
  if (nrow(nsa) < 36) return(data.frame())

  local_sa <- run_hicp_x12_adjustment(nsa$date, nsa$nsa_index)
  local_sa <- local_sa[order(local_sa$date), ]
  local_sa$mom_saar <- (local_sa$index / c(NA, head(local_sa$index, -1)))^12 * 100 - 100
  local_sa$qoq_saar <- (local_sa$index / c(rep(NA, 3), head(local_sa$index, -3)))^4 * 100 - 100
  local_sa$hoh_saar <- (local_sa$index / c(rep(NA, 6), head(local_sa$index, -6)))^2 * 100 - 100

  local_source <- ifelse(
    local_sa$is_flash_extension,
    "Eurostat HICP flash / Legacy X-13/X-11",
    "Eurostat HICP / Legacy X-13/X-11"
  )
  local_note <- ifelse(
    local_sa$is_flash_extension,
    "Legacy X-13ARIMA-SEATS seasonal adjustment in X-11 mode from 2012 with flash-extended NSA index.",
    "Legacy X-13ARIMA-SEATS seasonal adjustment in X-11 mode from 2012 using Eurostat NSA HICP index."
  )

  mom_valid <- !is.na(local_sa$mom_saar)
  qoq_valid <- !is.na(local_sa$qoq_saar)
  hoh_valid <- !is.na(local_sa$hoh_saar)
  mom <- make_series_frame(
    local_sa$date[mom_valid], definition$chart_id, definition$legacy_mom_series_id,
    "% MoM SAAR", "Euro Area", local_sa$mom_saar[mom_valid],
    unit = "%", source = local_source[mom_valid],
    source_url = "https://ec.europa.eu/eurostat/databrowser/view/prc_hicp_midx/default/table?lang=en",
    frequency = "monthly", source_note = local_note[mom_valid]
  )
  qoq <- make_series_frame(
    local_sa$date[qoq_valid], definition$chart_id, definition$legacy_qoq_series_id,
    "% QoQ SAAR", "Euro Area", local_sa$qoq_saar[qoq_valid],
    unit = "%", source = local_source[qoq_valid],
    source_url = "https://ec.europa.eu/eurostat/databrowser/view/prc_hicp_midx/default/table?lang=en",
    frequency = "monthly", source_note = local_note[qoq_valid]
  )
  hoh <- make_series_frame(
    local_sa$date[hoh_valid], definition$chart_id, definition$legacy_hoh_series_id,
    "% HoH SAAR", "Euro Area", local_sa$hoh_saar[hoh_valid],
    unit = "%", source = local_source[hoh_valid],
    source_url = "https://ec.europa.eu/eurostat/databrowser/view/prc_hicp_midx/default/table?lang=en",
    frequency = "monthly", source_note = local_note[hoh_valid]
  )
  rbind(hoh, qoq, mom)
}

run_hicp_x12_adjustment <- function(dates, values) {
  valid <- !is.na(dates) & !is.na(values) & values > 0
  dates <- as.Date(dates[valid])
  values <- as.numeric(values[valid])
  order_index <- order(dates)
  dates <- dates[order_index]
  values <- values[order_index]
  segment <- dates >= as.Date("2012-01-01")
  dates <- dates[segment]
  values <- values[segment]

  start_date <- as.POSIXlt(min(dates))
  series_ts <- stats::ts(values, start = c(start_date$year + 1900, start_date$mon + 1), frequency = 12)
  fit <- seasonal::seas(
    series_ts,
    transform.function = "log",
    regression.aictest = "easter",
    outlier = "",
    automdl = "",
    x11 = ""
  )
  adjusted <- as.numeric(seasonal::final(fit))
  data.frame(
    date = dates[seq_along(adjusted)],
    index = adjusted,
    is_flash_extension = FALSE,
    stringsAsFactors = FALSE
  )
}

read_ecb_hicp_sa_index_rows <- function(definition) {
  url <- sprintf("https://data-api.ecb.europa.eu/service/data/HICP/%s?format=csvdata", definition$ecb_key)
  raw_dir <- file.path(getwd(), "data/raw")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  tmp <- file.path(raw_dir, sprintf("ecb_hicp_sa_%s.csv", definition$base_series_id))
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
  data.frame(
    date = dates[valid],
    index = values[valid],
    source = "ECB Data Portal",
    source_url = "https://data.ecb.europa.eu/data/data-categories/macroeconomic-and-sectoral-statistics/inflation-and-consumer-prices/seasonally-adjusted-series?layerType=AL",
    source_note = sprintf("Official seasonally adjusted HICP index, ECB series HICP.%s.", definition$ecb_key),
    stringsAsFactors = FALSE
  )
}

read_eurostat_hicp_input_rows <- function(definition) {
  url <- sprintf("https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/%s?lang=en&geo=EA20", definition$dataset)
  raw_dir <- file.path(getwd(), "data/raw")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  tmp <- file.path(raw_dir, sprintf("eurostat_%s_inputs.json", definition$dataset))
  command <- sprintf(
    "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -TimeoutSec 45 -Uri %s -OutFile %s",
    shQuote(url, type = "sh"),
    shQuote(normalizePath(tmp, winslash = "\\", mustWork = FALSE), type = "sh")
  )
  system2("powershell", c("-NoProfile", "-Command", command), stdout = FALSE, stderr = FALSE)
  json <- jsonlite::fromJSON(tmp, simplifyVector = FALSE)
  nsa <- read_eurostat_teicp_values(json, "I25")
  yoy <- read_eurostat_teicp_values(json, "PCH_M12")
  merged <- merge(nsa, yoy, by = "date", all = TRUE, suffixes = c("_nsa", "_yoy"))
  names(merged)[names(merged) == "value_nsa"] <- "nsa_index"
  names(merged)[names(merged) == "value_yoy"] <- "yoy"
  merged[order(merged$date), ]
}

read_eurostat_hicp_midx_index <- function(coicop_code, base_series_id) {
  url <- sprintf(
    "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/prc_hicp_midx?lang=en&geo=EA20&coicop=%s&unit=I15",
    utils::URLencode(coicop_code, reserved = TRUE)
  )
  raw_dir <- file.path(getwd(), "data/raw")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  tmp <- file.path(raw_dir, sprintf("eurostat_prc_hicp_midx_%s.json", coicop_code))
  command <- sprintf(
    "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -TimeoutSec 45 -Uri %s -OutFile %s",
    shQuote(url, type = "sh"),
    shQuote(normalizePath(tmp, winslash = "\\", mustWork = FALSE), type = "sh")
  )
  system2("powershell", c("-NoProfile", "-Command", command), stdout = FALSE, stderr = FALSE)
  json <- jsonlite::fromJSON(tmp, simplifyVector = FALSE)

  times <- names(sort(unlist(json$dimension$time$category$index)))
  dates <- as.Date(sprintf("%s-01", times))
  values <- rep(NA_real_, length(times))
  value_map <- unlist(json$value)
  if (length(value_map)) {
    positions <- as.integer(names(value_map)) + 1
    values[positions] <- as.numeric(value_map)
  }
  valid <- !is.na(dates) & !is.na(values)
  data.frame(
    date = dates[valid],
    nsa_index = values[valid],
    is_flash_extension = FALSE,
    series_id = base_series_id,
    stringsAsFactors = FALSE
  )
}

extend_hicp_nsa_index_with_flash <- function(nsa, eurostat_input) {
  if (!nrow(nsa) || !nrow(eurostat_input)) return(nsa)
  nsa <- nsa[order(nsa$date), ]
  input <- eurostat_input[order(eurostat_input$date), ]
  latest_nsa <- max(nsa$date, na.rm = TRUE)
  latest_flash <- max(input$date[!is.na(input$yoy) | !is.na(input$nsa_index)], na.rm = TRUE)
  if (is.na(latest_flash) || latest_flash <= latest_nsa) return(nsa)

  common <- merge(nsa[, c("date", "nsa_index")], input[, c("date", "nsa_index")], by = "date", suffixes = c("_i15", "_i25"))
  common <- common[!is.na(common$nsa_index_i15) & !is.na(common$nsa_index_i25) & common$nsa_index_i25 != 0, ]
  if (!nrow(common)) return(nsa)
  scale_factor <- tail(common$nsa_index_i15 / common$nsa_index_i25, 1)

  missing_dates <- input$date[input$date > latest_nsa & input$date <= latest_flash]
  for (target_date in missing_dates) {
    row <- input[input$date == target_date, ]
    i25_index <- row$nsa_index[1]
    if (is.na(i25_index) && !is.na(row$yoy[1])) {
      prior_date <- add_months(target_date, -12)
      prior <- input[input$date == prior_date, ]
      if (nrow(prior) && !is.na(prior$nsa_index[1])) {
        i25_index <- prior$nsa_index[1] * (1 + row$yoy[1] / 100)
      }
    }
    if (is.na(i25_index)) next
    nsa <- rbind(nsa, data.frame(
      date = target_date,
      nsa_index = i25_index * scale_factor,
      is_flash_extension = TRUE,
      series_id = nsa$series_id[1],
      stringsAsFactors = FALSE
    ))
  }
  nsa[order(nsa$date), ]
}

read_eurostat_teicp_values <- function(json, unit_code) {
  times <- names(sort(unlist(json$dimension$time$category$index)))
  dates <- as.Date(sprintf("%s-01", times))
  n_time <- length(times)
  n_geo <- length(unlist(json$dimension$geo$category$index))
  unit_index <- unlist(json$dimension$unit$category$index)
  if (!unit_code %in% names(unit_index)) {
    return(data.frame(date = dates, value = NA_real_))
  }
  unit_pos <- as.integer(unit_index[[unit_code]])
  value_map <- unlist(json$value)
  idx <- unit_pos * n_geo * n_time + seq_len(n_time) - 1
  values <- rep(NA_real_, n_time)
  present <- as.character(idx) %in% names(value_map)
  values[present] <- as.numeric(value_map[as.character(idx[present])])
  data.frame(date = dates, value = values, stringsAsFactors = FALSE)
}

extend_hicp_sa_index_with_flash <- function(ecb_sa, eurostat_input) {
  if (!nrow(ecb_sa) || !nrow(eurostat_input)) {
    return(ecb_sa)
  }

  sa <- ecb_sa[order(ecb_sa$date), ]
  input <- eurostat_input[order(eurostat_input$date), ]
  latest_sa <- max(sa$date, na.rm = TRUE)
  latest_eurostat <- max(input$date[!is.na(input$yoy) | !is.na(input$nsa_index)], na.rm = TRUE)
  if (is.na(latest_eurostat) || latest_eurostat <= latest_sa) {
    return(sa)
  }

  missing_dates <- input$date[input$date > latest_sa & input$date <= latest_eurostat]
  for (target_date in missing_dates) {
    row <- input[input$date == target_date, ]
    nsa_index <- row$nsa_index[1]
    if (is.na(nsa_index) && !is.na(row$yoy[1])) {
      prior_date <- add_months(target_date, -12)
      prior <- input[input$date == prior_date, ]
      if (nrow(prior) && !is.na(prior$nsa_index[1])) {
        nsa_index <- prior$nsa_index[1] * (1 + row$yoy[1] / 100)
      }
    }
    if (is.na(nsa_index)) {
      next
    }

    seasonal_date <- add_months(target_date, -12)
    prior_sa <- sa$index[sa$date == seasonal_date]
    prior_nsa <- input$nsa_index[input$date == seasonal_date]
    if (!length(prior_sa) || !length(prior_nsa) || is.na(prior_sa[1]) || is.na(prior_nsa[1]) || prior_nsa[1] == 0) {
      common <- merge(sa[, c("date", "index")], input[, c("date", "nsa_index")], by = "date")
      common <- common[!is.na(common$index) & !is.na(common$nsa_index) & common$nsa_index != 0, ]
      if (!nrow(common)) next
      seasonal_factor <- tail(common$index / common$nsa_index, 1)
    } else {
      seasonal_factor <- prior_sa[1] / prior_nsa[1]
    }

    sa <- rbind(sa, data.frame(
      date = target_date,
      index = nsa_index * seasonal_factor,
      source = "Eurostat HICP flash / ECB Data Portal",
      source_url = "https://ec.europa.eu/eurostat/databrowser/product/view/teicp000?lang=en",
      source_note = "Flash-implied seasonally adjusted index; replaced when ECB SA final is available.",
      stringsAsFactors = FALSE
    ))
    sa <- sa[order(sa$date), ]
  }

  sa
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

  values_frame <- read_eurostat_teicp_values(json, "PCH_M12")
  dates <- values_frame$date
  values <- values_frame$value
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
