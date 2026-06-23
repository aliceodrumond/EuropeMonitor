build_activity_series <- function(project_root) {
  catalog <- read_series_catalog(project_root)
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
      source = "synthetic seed"
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
      source = "synthetic seed"
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
      source = "synthetic seed"
    )
  }))

  flash_path <- file.path(project_root, "data/raw/flash_pmi_euro_area.csv")
  flash_rows <- data.frame()
  if (file.exists(flash_path)) {
    flash <- utils::read.csv(
      flash_path,
      stringsAsFactors = FALSE,
      fileEncoding = "UTF-8",
      check.names = FALSE
    )
    required_columns <- c("date", "composite", "manufacturing", "services")
    missing_columns <- setdiff(required_columns, names(flash))

    if (length(missing_columns)) {
      stop(sprintf(
        "Missing columns in data/raw/flash_pmi_euro_area.csv: %s",
        paste(missing_columns, collapse = ", ")
      ))
    }

    flash$date <- as.Date(flash$date)
    flash_specs <- data.frame(
      chart_id = c("pmi_composite", "pmi_manufacturing", "pmi_services"),
      series_id = c("pmi_flash_ea", "pmi_mfg_flash_ea", "pmi_srv_flash_ea"),
      value_column = c("composite", "manufacturing", "services"),
      stringsAsFactors = FALSE
    )

    flash_frames <- lapply(seq_len(nrow(flash_specs)), function(i) {
      spec <- flash_specs[i, ]
      valid <- !is.na(flash[[spec$value_column]])
      if (!any(valid)) {
        return(NULL)
      }
      make_series_frame(
        flash$date[valid],
        chart_id = spec$chart_id,
        series_id = spec$series_id,
        series_name = "Europe Flash",
        country = "Euro Area",
        values = flash[[spec$value_column]][valid],
        unit = "index",
        source = "HCOB / SP Global Flash PMI"
      )
    })
    flash_frames <- Filter(Negate(is.null), flash_frames)
    if (length(flash_frames)) {
      flash_rows <- do.call(rbind, flash_frames)
    }
  }

  official_pmi <- read_official_pmi_workbook(project_root)
  pmi_rows <- official_pmi$composite
  pmi_manufacturing_rows <- official_pmi$manufacturing
  pmi_services_rows <- official_pmi$services
  flash_rows <- data.frame()

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
      source = "synthetic seed"
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
      source = "synthetic seed"
    )
  )

  pmi_sentix_rows <- pmi_rows[pmi_rows$series_id == "pmi_ea", ]
  pmi_sentix_rows$chart_id <- "sentix_pmi"
  pmi_sentix_rows$series_id <- "pmi_ea_sentix"
  pmi_sentix_rows$series_name <- "PMI Composite"
  official_sentix_rows <- read_official_sentix_rows(project_root)
  if (nrow(official_sentix_rows)) {
    sentix_rows <- official_sentix_rows
  }
  sentix_rows <- rbind(
    pmi_sentix_rows,
    sentix_rows[sentix_rows$series_id == "sentix_ea", ]
  )
  zew_rows <- read_zew_rows(project_root)

  weekly <- read_bundesbank_wai_rows(project_root)
  if (!nrow(weekly)) {
    weekly <- make_series_frame(
      dates,
      "weekly_activity",
      "wai_de",
      "Germany WAI",
      "Germany",
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
      unit = "%",
      source = "synthetic seed"
    )
  }

  toll <- read_destatis_toll_rows(project_root)
  if (!nrow(toll)) {
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
      source = "synthetic seed"
    )
  }

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
    source = "synthetic seed"
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
    source = "synthetic seed"
  )

  activity <- apply_series_catalog(rbind(
    pmi_rows,
    pmi_manufacturing_rows,
    pmi_services_rows,
    flash_rows,
    sentix_rows,
    zew_rows,
    weekly,
    toll,
    financial,
    gdp
  ), catalog)
  write_csv_utf8(activity, file.path(project_root, "data/processed/activity_series.csv"))
  activity
}

read_official_pmi_workbook <- function(project_root) {
  workbook_path <- file.path(project_root, "data/raw/pmi_official_history.xlsx")
  if (!file.exists(workbook_path)) stop("Missing official PMI workbook: data/raw/pmi_official_history.xlsx")
  if (!requireNamespace("openxlsx", quietly = TRUE)) stop("Package 'openxlsx' is required to import official PMI history")
  online_flash <- fetch_spglobal_flash_pmi_values(project_root)

  definitions <- list(
    composite = list(sheet = "Composite", chart_id = "pmi_composite", prefix = "pmi_", value_column = "composite"),
    manufacturing = list(sheet = "Manufacturing", chart_id = "pmi_manufacturing", prefix = "pmi_mfg_", value_column = "manufacturing"),
    services = list(sheet = "Services", chart_id = "pmi_services", prefix = "pmi_srv_", value_column = "services")
  )
  countries <- data.frame(
    column = c("euro_area_final", "germany_final", "france_final", "spain_final", "uk_final", "italy_final"),
    suffix = c("ea", "de", "fr", "es", "uk", "it"),
    series_name = c("Europe", "Germany", "France", "Spain", "UK", "Italy"),
    country = c("Euro Area", "Germany", "France", "Spain", "United Kingdom", "Italy"),
    stringsAsFactors = FALSE
  )

  lapply(definitions, function(definition) {
    values <- openxlsx::read.xlsx(workbook_path, sheet = definition$sheet, detectDates = TRUE)
    missing <- setdiff(c("date", countries$column), names(values))
    if (length(missing)) stop(sprintf("Missing columns in %s: %s", definition$sheet, paste(missing, collapse = ", ")))
    values$date <- as.Date(values$date)
    for (flash_column in sub("_final$", "_flash", countries$column)) {
      if (!flash_column %in% names(values)) {
        values[[flash_column]] <- NA_real_
      }
    }
    values <- merge_online_flash_pmi(values, online_flash, definition$value_column, countries)
    frames <- lapply(seq_len(nrow(countries)), function(i) {
      spec <- countries[i, ]
      series_values <- values[[spec$column]]
      source <- rep("S&P Global PMI official history", nrow(values))
      flash_column <- sub("_final$", "_flash", spec$column)
      flash_valid <- is.na(series_values) & !is.na(values[[flash_column]])
      series_values[flash_valid] <- values[[flash_column]][flash_valid]
      source[flash_valid] <- "HCOB / SP Global Flash PMI"
      valid <- !is.na(series_values)
      make_series_frame(
        values$date[valid], definition$chart_id,
        paste0(definition$prefix, spec$suffix), spec$series_name, spec$country,
        series_values[valid], unit = "index",
        source = source[valid]
      )
    })
    do.call(rbind, frames)
  })
}

merge_online_flash_pmi <- function(values, flash, value_column, countries) {
  if (!nrow(flash)) {
    return(values)
  }
  for (i in seq_len(nrow(flash))) {
    row <- flash[i, ]
    country <- countries[countries$suffix == row$suffix, ]
    if (!nrow(country) || is.na(row[[value_column]])) {
      next
    }
    if (!row$date %in% values$date) {
      values[nrow(values) + 1, ] <- NA
      values$date[nrow(values)] <- row$date
    }
    idx <- which(values$date == row$date)[[1]]
    final_column <- country$column[[1]]
    flash_column <- sub("_final$", "_flash", final_column)
    if (is.na(values[[final_column]][idx])) {
      values[[flash_column]][idx] <- row[[value_column]]
    }
  }
  values[order(values$date), ]
}

fetch_spglobal_flash_pmi_values <- function(project_root) {
  releases_url <- "https://www.pmi.spglobal.com/Public/Release/PressReleases"
  if (!requireNamespace("pdftools", quietly = TRUE)) {
    warning("Package 'pdftools' is required to import S&P Global Flash PMI PDFs")
    return(empty_flash_pmi_values())
  }
  result <- tryCatch({
    html <- read_spglobal_text(releases_url)
    releases <- parse_spglobal_release_cards(html)
    wanted <- releases[
      grepl("Flash (France|Germany|Eurozone) PMI", releases$title, ignore.case = TRUE) &
        !grepl("\\(|Consumer Sentiment|UK|US|Japan|India", releases$title, ignore.case = TRUE),
    ]
    if (!nrow(wanted)) {
      return(empty_flash_pmi_values())
    }
    wanted <- wanted[order(wanted$date, decreasing = TRUE), ]
    wanted <- wanted[!duplicated(wanted$region), ]
    frames <- lapply(seq_len(nrow(wanted)), function(i) {
      release <- wanted[i, ]
      pdf_path <- file.path(project_root, "data/raw", paste0("spglobal_flash_pmi_", release$region, "_", format(release$date, "%Y%m%d"), ".pdf"))
      download_binary(release$url, pdf_path)
      text <- paste(pdftools::pdf_text(pdf_path), collapse = "\n")
      parse_flash_pmi_pdf_text(text, release)
    })
    frames <- Filter(Negate(is.null), frames)
    if (length(frames)) do.call(rbind, frames) else empty_flash_pmi_values()
  }, error = function(error) {
    warning(sprintf("S&P Global Flash PMI fetch failed: %s", error$message))
    empty_flash_pmi_values()
  })
  result
}

empty_flash_pmi_values <- function() {
  data.frame(
    date = as.Date(character()),
    suffix = character(),
    composite = numeric(),
    manufacturing = numeric(),
    services = numeric(),
    source_url = character(),
    stringsAsFactors = FALSE
  )
}

parse_spglobal_release_cards <- function(html) {
  pattern <- "<span class=\"releaseDate\">([A-Z][a-z]+)&nbsp;([0-9]{2})&nbsp;([0-9]{4})&nbsp;[0-9:]+&nbsp;UTC</span>\\s*<span class=\"releaseTitle\">([^<]+)</span>\\s*<span class=\"greenListItem\"><a href=\"([^\"]+)\""
  matches <- regmatches(html, gregexpr(pattern, html, perl = TRUE))[[1]]
  if (!length(matches) || identical(matches, character(0))) {
    return(data.frame())
  }
  rows <- lapply(matches, function(item) {
    values <- regmatches(item, regexec(pattern, item, perl = TRUE))[[1]]
    title <- trimws(gsub("\\s+", " ", values[[5]]))
    region <- if (grepl("France", title, ignore.case = TRUE)) {
      "fr"
    } else if (grepl("Germany", title, ignore.case = TRUE)) {
      "de"
    } else if (grepl("Eurozone", title, ignore.case = TRUE)) {
      "ea"
    } else {
      NA_character_
    }
    data.frame(
      date = as.Date(sprintf("%s %s %s", values[[3]], values[[2]], values[[4]]), format = "%d %B %Y"),
      title = title,
      region = region,
      url = absolute_spglobal_url(values[[6]]),
      stringsAsFactors = FALSE
    )
  })
  rows <- do.call(rbind, rows)
  rows[!is.na(rows$region), ]
}

parse_flash_pmi_pdf_text <- function(text, release) {
  data.frame(
    date = as.Date(format(release$date, "%Y-%m-01")),
    suffix = release$region,
    composite = extract_pmi_value(text, c("Composite PMI Output Index", "Composite PMI Output", "Composite Output Index")),
    manufacturing = extract_manufacturing_pmi_value(text),
    services = extract_pmi_value(text, c("Services PMI Business Activity Index", "Services PMI Business Activity", "Services Business Activity Index")),
    source_url = release$url,
    stringsAsFactors = FALSE
  )
}

extract_manufacturing_pmi_value <- function(text) {
  compact <- gsub("\\s+", " ", text)
  patterns <- c(
    "Manufacturing PMI\\([0-9]+\\)\\s*(?:\\bat\\s+|:\\s*)([0-9]+\\.?[0-9]*)",
    "Manufacturing PMI\\s*(?:\\bat\\s+|:\\s*)([0-9]+\\.?[0-9]*)"
  )
  for (pattern in patterns) {
    match <- regmatches(compact, regexec(pattern, compact, ignore.case = TRUE, perl = TRUE))[[1]]
    if (length(match) >= 2) {
      return(as.numeric(match[[2]]))
    }
  }
  NA_real_
}

extract_pmi_value <- function(text, labels) {
  compact <- gsub("\\s+", " ", text)
  for (label in labels) {
    pattern <- sprintf("%s.{0,220}?(?:\\bat\\s+|:\\s*)([0-9]+\\.?[0-9]*)", label)
    match <- regmatches(compact, regexec(pattern, compact, ignore.case = TRUE, perl = TRUE))[[1]]
    if (length(match) >= 2) {
      return(as.numeric(match[[2]]))
    }
  }
  NA_real_
}

read_spglobal_text <- function(url) {
  tmp <- tempfile(fileext = ".html")
  download_binary(url, tmp)
  paste(readLines(tmp, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

download_binary <- function(url, path) {
  script <- sprintf(
    "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri %s -OutFile %s",
    shQuote(url, type = "sh"),
    shQuote(normalizePath(path, winslash = "\\", mustWork = FALSE), type = "sh")
  )
  status <- system2("powershell", c("-NoProfile", "-Command", script), stdout = FALSE, stderr = FALSE)
  if (!identical(status, 0L) || !file.exists(path) || file.info(path)$size == 0) {
    stop(sprintf("Could not download %s", url))
  }
  invisible(path)
}

absolute_spglobal_url <- function(path) {
  if (grepl("^https?://", path)) {
    return(path)
  }
  paste0("https://www.pmi.spglobal.com", path)
}

read_official_sentix_rows <- function(project_root) {
  workbook_path <- file.path(project_root, "data/raw/sentix_official_history.xlsx")
  root_workbook_path <- file.path(project_root, "Sentix_official_history_template.xlsx")
  if (!file.exists(workbook_path) && file.exists(root_workbook_path)) {
    dir.create(dirname(workbook_path), recursive = TRUE, showWarnings = FALSE)
    file.copy(root_workbook_path, workbook_path, overwrite = TRUE)
  }
  if (!file.exists(workbook_path)) {
    return(data.frame())
  }
  if (!requireNamespace("openxlsx", quietly = TRUE)) stop("Package 'openxlsx' is required to import official Sentix history")

  values <- openxlsx::read.xlsx(workbook_path, sheet = "Sentix_Official", detectDates = TRUE)
  missing <- setdiff(c("date", "sentix_ea"), names(values))
  if (length(missing)) stop(sprintf("Missing columns in Sentix_Official: %s", paste(missing, collapse = ", ")))
  values$date <- as.Date(values$date, origin = "1899-12-30")
  values$sentix_ea <- as.numeric(values$sentix_ea)
  values <- values[!is.na(values$date) & !is.na(values$sentix_ea), c("date", "sentix_ea")]

  latest <- fetch_latest_sentix_from_investing()
  if (nrow(latest)) {
    values <- values[values$date != latest$date[1], ]
    values <- rbind(values, latest[, c("date", "sentix_ea")])
  }

  values <- values[order(values$date), ]
  make_series_frame(
    values$date,
    "sentix_pmi",
    "sentix_ea",
    "Sentix",
    "Euro Area",
    values$sentix_ea,
    axis = "right",
    unit = "balance",
    source = "Sentix / Investing.com",
    source_url = "https://www.investing.com/economic-calendar/sentix-investor-confidence-268"
  )
}

fetch_latest_sentix_from_investing <- function() {
  url <- "https://www.investing.com/economic-calendar/sentix-investor-confidence-268"
  html <- fetch_url_text(url)
  if (!nzchar(html)) {
    return(data.frame())
  }

  pattern <- "([A-Z][a-z]{2})\\s+([0-9]{2}),\\s+([0-9]{4})\\s+\\(([A-Z][a-z]{2})\\)[^0-9+-]*[0-9]{1,2}:[0-9]{2}\\s*([-+]?[0-9]+(?:\\.[0-9]+)?)"
  match <- regexec(pattern, html, perl = TRUE)
  parts <- regmatches(html, match)[[1]]
  if (length(parts) < 6) {
    return(data.frame())
  }

  month <- match(parts[4], month.abb)
  if (is.na(month)) {
    month <- match(parts[2], month.abb)
  }
  if (is.na(month)) {
    return(data.frame())
  }

  data.frame(
    date = as.Date(sprintf("%s-%02d-01", parts[3], month)),
    sentix_ea = as.numeric(parts[5]),
    stringsAsFactors = FALSE
  )
}

read_destatis_toll_rows <- function(project_root) {
  daily_rows <- read_dashboard_daily_toll_rows()
  if (nrow(daily_rows)) {
    return(daily_rows)
  }
  read_destatis_monthly_toll_rows()
}

read_destatis_monthly_toll_rows <- function() {
  url <- "https://www.destatis.de/EN/Themes/Economy/Short-Term-Indicators/Truck-Toll-Mileage/kmau110_bv4a.html"
  html <- fetch_url_text(url)
  if (!nzchar(html)) {
    url <- "https://www.destatis.de/DE/Themen/Wirtschaft/Konjunkturindikatoren/Lkw-Maut-Fahrleistungsindex/kmau110_x13a.html"
    html <- fetch_url_text(url)
  }

  if (!nzchar(html)) {
    return(data.frame())
  }

  rows <- gregexpr("<tr[\\s\\S]*?</tr>", html, perl = TRUE)
  row_html <- regmatches(html, rows)[[1]]
  current_year <- NA_integer_
  out <- data.frame(date = as.Date(character()), value = numeric(), stringsAsFactors = FALSE)
  month_map <- c(
    Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Mai = 5, Jun = 6,
    Jul = 7, Aug = 8, Sep = 9, Oct = 10, Okt = 10, Nov = 11, Dec = 12, Dez = 12
  )

  for (row in row_html) {
    year_match <- regmatches(row, regexpr(">20[0-9]{2}<", row, perl = TRUE))
    if (length(year_match) && nzchar(year_match)) {
      current_year <- as.integer(gsub("[^0-9]", "", year_match))
    }

    month_match <- regmatches(row, regexpr(">(Jan|Feb|Mar|M..r|Apr|May|Mai|Jun|Jul|Aug|Sep|Oct|Okt|Nov|Dec|Dez)<", row, perl = TRUE))
    if (!length(month_match) || !nzchar(month_match) || is.na(current_year)) {
      next
    }
    month_label <- gsub("[<>]", "", month_match)
    month <- if (month_label %in% names(month_map)) unname(month_map[[month_label]]) else 3
    cells <- gregexpr("<td>[^<]+</td>", row, perl = TRUE)
    cell_values <- regmatches(row, cells)[[1]]
    if (length(cell_values) < 3) {
      next
    }
    adjusted_value <- as.numeric(gsub(",", ".", gsub("<[^>]+>", "", cell_values[3])))
    out <- rbind(out, data.frame(
      date = as.Date(sprintf("%04d-%02d-01", current_year, month)),
      value = adjusted_value,
      stringsAsFactors = FALSE
    ))
  }

  if (!nrow(out)) {
    return(data.frame())
  }
  out <- out[order(out$date), ]
  make_series_frame(
    out$date,
    "toll_mileage",
    "toll_de",
    "Germany toll mileage",
    "Germany",
    out$value,
    unit = "index",
    source = "Destatis/BALM Lkw-Maut-Fahrleistungsindex",
    source_url = "https://www.destatis.de/EN/Service/EXSTAT/Datensaetze/truck-toll-mileage.html",
    frequency = "monthly"
  )
}

read_dashboard_daily_toll_rows <- function() {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(data.frame())
  }

  raw <- read_dashboard_highcharts_series("detran0225")
  if (!nrow(raw)) {
    return(data.frame())
  }

  scale_factor <- read_toll_level_scale(raw)
  raw$value <- raw$value * scale_factor
  raw <- raw[order(raw$date), ]
  raw$avg7 <- trailing_mean(raw$value, 7)
  raw <- raw[!is.na(raw$value) & !is.na(raw$avg7), ]
  if (!nrow(raw)) {
    return(data.frame())
  }

  avg_rows <- make_series_frame(
    raw$date,
    "toll_mileage",
    "toll_de",
    "Germany toll mileage, 7-day moving average",
    "Germany",
    raw$avg7,
    unit = "index",
    source = "Dashboard Konjunktur / Destatis",
    source_url = "https://www.dashboard-konjunktur.de/indicator/tile_1667226778807",
    frequency = "daily"
  )
  daily_rows <- make_series_frame(
    raw$date,
    "toll_mileage",
    "toll_de_daily",
    "Germany toll mileage, daily",
    "Germany",
    raw$value,
    unit = "index",
    source = "Dashboard Konjunktur / Destatis",
    source_url = "https://www.dashboard-konjunktur.de/indicator/tile_1667226778807",
    frequency = "daily"
  )
  rbind(avg_rows, daily_rows)
}

read_dashboard_highcharts_series <- function(topic_id) {
  url <- sprintf("https://www.dashboard-konjunktur.de/api/highcharts?topicId=%s&from=1577919600000", topic_id)
  tmp <- tempfile(fileext = ".json")
  command <- sprintf(
    "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri %s -OutFile %s",
    shQuote(url, type = "sh"),
    shQuote(normalizePath(tmp, winslash = "\\", mustWork = FALSE), type = "sh")
  )
  tryCatch(system2("powershell", c("-NoProfile", "-Command", command), stdout = FALSE, stderr = FALSE), error = function(e) NULL)

  if (!file.exists(tmp) || file.info(tmp)$size == 0) {
    return(data.frame())
  }
  parsed <- tryCatch(jsonlite::fromJSON(tmp, simplifyVector = FALSE), error = function(e) NULL)
  points <- parsed$series[[1]]$data
  if (is.null(points) || !length(points)) {
    return(data.frame())
  }
  dates <- as.Date(as.POSIXct(
    vapply(points, function(point) as.numeric(point[[1]]) / 1000, numeric(1)),
    origin = "1970-01-01",
    tz = "UTC"
  ))
  values <- vapply(points, function(point) as.numeric(point[[2]]), numeric(1))
  valid <- !is.na(dates) & !is.na(values)
  data.frame(date = dates[valid], value = values[valid], stringsAsFactors = FALSE)
}

read_toll_level_scale <- function(raw) {
  url <- "https://www.dashboard-deutschland.de/api/tile/indicators?ids=tile_1667226778807"
  tmp <- tempfile(fileext = ".json")
  command <- sprintf(
    "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri %s -OutFile %s",
    shQuote(url, type = "sh"),
    shQuote(normalizePath(tmp, winslash = "\\", mustWork = FALSE), type = "sh")
  )
  tryCatch(system2("powershell", c("-NoProfile", "-Command", command), stdout = FALSE, stderr = FALSE), error = function(e) NULL)

  fallback <- 180
  if (!file.exists(tmp) || file.info(tmp)$size == 0) {
    return(fallback)
  }
  parsed <- tryCatch(jsonlite::fromJSON(tmp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(parsed) || !length(parsed) || is.null(parsed[[1]]$json)) {
    return(fallback)
  }
  tile <- tryCatch(jsonlite::fromJSON(parsed[[1]]$json, simplifyVector = FALSE), error = function(e) NULL)
  series <- tile$components[[1]]$chart$series
  target <- NULL
  for (item in series) {
    if (identical(item$id, "detran0225")) {
      target <- item
      break
    }
  }
  if (is.null(target) || !length(target$data)) {
    return(fallback)
  }
  dates <- as.Date(as.POSIXct(
    vapply(target$data, function(point) as.numeric(point[[1]]) / 1000, numeric(1)),
    origin = "1970-01-01",
    tz = "UTC"
  ))
  values <- vapply(target$data, function(point) as.numeric(point[[2]]), numeric(1))
  valid <- !is.na(dates) & !is.na(values)
  old <- data.frame(date = dates[valid], value = values[valid], stringsAsFactors = FALSE)
  overlap <- merge(old, raw, by = "date", suffixes = c("_level", "_raw"))
  overlap <- overlap[overlap$value_raw > 0 & overlap$value_level > 0, ]
  if (!nrow(overlap)) {
    return(fallback)
  }
  stats::median(overlap$value_level / overlap$value_raw, na.rm = TRUE)
}

trailing_mean <- function(values, window) {
  vapply(seq_along(values), function(i) {
    start <- max(1, i - window + 1)
    mean(values[start:i], na.rm = TRUE)
  }, numeric(1))
}

read_zew_rows <- function(project_root) {
  url <- "https://zew.de/fileadmin/FTP/div/konjunktur.xls"
  workbook_path <- file.path(project_root, "data/raw/zew_konjunktur.xls")
  download_binary_url(url, workbook_path)

  if (!file.exists(workbook_path)) {
    return(data.frame())
  }
  if (!requireNamespace("readxl", quietly = TRUE)) stop("Package 'readxl' is required to import ZEW history")

  values <- readxl::read_excel(workbook_path, sheet = "data", col_names = FALSE)
  names(values) <- as.character(unlist(values[1, ], use.names = FALSE))
  values <- values[-1, ]

  date_col <- names(values)[1]
  indicator_col <- "ZEW Indicator of Economic Sentiment Germany, balances"
  if (!indicator_col %in% names(values)) {
    stop(sprintf("Missing column in ZEW workbook: %s", indicator_col))
  }

  dates <- suppressWarnings(as.Date(as.numeric(values[[date_col]]), origin = "1899-12-30"))
  dates <- as.Date(format(dates, "%Y-%m-01"))
  zew <- suppressWarnings(as.numeric(values[[indicator_col]]))
  valid <- !is.na(dates) & !is.na(zew)

  make_series_frame(
    dates[valid],
    "zew_sentiment",
    "zew_de",
    "Germany ZEW",
    "Germany",
    zew[valid],
    unit = "balance",
    source = "ZEW Financial Market Survey",
    source_url = "https://www.zew.de/en/publications/zew-expertises-research-reports/research-reports/business-cycle/zew-financial-market-survey"
  )
}

read_bundesbank_wai_rows <- function(project_root) {
  url <- "https://api.statistiken.bundesbank.de/rest/data/BBDE1/W.DE.Y.WAI.A2N400000.A.N.R00.A?detail=dataonly&format=csv"
  csv_text <- fetch_url_text(url)
  if (!nzchar(csv_text)) {
    return(data.frame())
  }

  if (grepl("<generic:Obs", csv_text, fixed = TRUE)) {
    return(read_bundesbank_wai_xml(csv_text))
  }

  direct_rows <- read_bundesbank_wai_bbk_csv(csv_text)
  if (nrow(direct_rows)) {
    return(direct_rows)
  }

  values <- tryCatch(
    utils::read.csv2(
      text = csv_text,
      stringsAsFactors = FALSE,
      check.names = FALSE,
      fileEncoding = "UTF-8-BOM"
    ),
    error = function(e) data.frame()
  )
  if (!nrow(values) || !all(c("TIME_PERIOD", "OBS_VALUE") %in% names(values))) {
    return(data.frame())
  }

  values$OBS_VALUE <- suppressWarnings(as.numeric(gsub(",", ".", values$OBS_VALUE)))
  valid <- grepl("^[0-9]{4}-W[0-9]{2}$", values$TIME_PERIOD) & !is.na(values$OBS_VALUE)
  if (!any(valid)) {
    return(data.frame())
  }

  make_series_frame(
    iso_week_end(values$TIME_PERIOD[valid]),
    "weekly_activity",
    "wai_de",
    "Germany WAI",
    "Germany",
    values$OBS_VALUE[valid],
    unit = "%",
    source = "Deutsche Bundesbank",
    source_url = "https://statistiken.bundesbank.de/statistiken-en/timeseries/BBDE1/W.DE.Y.WAI.A2N400000.A.N.R00.A"
  )
}

read_bundesbank_wai_bbk_csv <- function(csv_text) {
  lines <- unlist(strsplit(csv_text, "\n", fixed = TRUE), use.names = FALSE)
  lines <- gsub("\r", "", lines, fixed = TRUE)
  valid <- grepl("^[0-9]{4}-W[0-9]{2};", lines)
  if (!any(valid)) {
    return(data.frame())
  }

  parts <- strsplit(lines[valid], ";", fixed = TRUE)
  periods <- vapply(parts, function(x) x[[1]], character(1))
  values <- suppressWarnings(as.numeric(gsub(",", ".", vapply(parts, function(x) x[[2]], character(1)))))
  ok <- !is.na(values)
  make_series_frame(
    iso_week_end(periods[ok]),
    "weekly_activity",
    "wai_de",
    "Germany WAI",
    "Germany",
    values[ok],
    unit = "%",
    source = "Deutsche Bundesbank",
    source_url = "https://statistiken.bundesbank.de/statistiken-en/timeseries/BBDE1/W.DE.Y.WAI.A2N400000.A.N.R00.A"
  )
}

read_bundesbank_wai_xml <- function(xml_text) {
  pattern <- '<generic:Obs><generic:ObsDimension value="([0-9]{4}-W[0-9]{2})"></generic:ObsDimension><generic:ObsValue value="([-+]?[0-9]+(?:\\.[0-9]+)?)"></generic:ObsValue></generic:Obs>'
  matches <- gregexpr(pattern, xml_text, perl = TRUE)
  rows <- regmatches(xml_text, matches)[[1]]
  if (!length(rows)) {
    return(data.frame())
  }
  periods <- sub(pattern, "\\1", rows, perl = TRUE)
  values <- as.numeric(sub(pattern, "\\2", rows, perl = TRUE))
  make_series_frame(
    iso_week_end(periods),
    "weekly_activity",
    "wai_de",
    "Germany WAI",
    "Germany",
    values,
    unit = "%",
    source = "Deutsche Bundesbank",
    source_url = "https://statistiken.bundesbank.de/statistiken-en/timeseries/BBDE1/W.DE.Y.WAI.A2N400000.A.N.R00.A"
  )
}

iso_week_start <- function(periods) {
  year <- as.integer(sub("-W.*", "", periods))
  week <- as.integer(sub(".*-W", "", periods))
  jan4 <- as.Date(sprintf("%04d-01-04", year))
  jan4_wday <- as.integer(format(jan4, "%u"))
  monday_week1 <- jan4 - (jan4_wday - 1)
  monday_week1 + (week - 1) * 7
}

iso_week_end <- function(periods) {
  iso_week_start(periods) + 6
}

download_binary_url <- function(url, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  ok <- tryCatch({
    utils::download.file(url, path, mode = "wb", quiet = TRUE)
    file.exists(path) && file.info(path)$size > 0
  }, error = function(e) FALSE)
  if (ok) {
    return(TRUE)
  }

  command <- sprintf(
    "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri %s -OutFile %s",
    shQuote(url, type = "sh"),
    shQuote(normalizePath(path, winslash = "\\", mustWork = FALSE), type = "sh")
  )
  tryCatch({
    system2("powershell", c("-NoProfile", "-Command", command), stdout = FALSE, stderr = FALSE)
    file.exists(path) && file.info(path)$size > 0
  }, error = function(e) FALSE)
}

fetch_url_text <- function(url) {
  html <- tryCatch(
    paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )
  if (nzchar(html)) {
    return(html)
  }

  command <- sprintf(
    "$ProgressPreference='SilentlyContinue'; $r=Invoke-WebRequest -UseBasicParsing -Uri %s; if($r.Content -is [byte[]]){[Text.Encoding]::UTF8.GetString($r.Content)} else {$r.Content}",
    shQuote(url, type = "sh")
  )
  tryCatch(
    paste(system2("powershell", c("-NoProfile", "-Command", command), stdout = TRUE, stderr = FALSE), collapse = "\n"),
    error = function(e) ""
  )
}



