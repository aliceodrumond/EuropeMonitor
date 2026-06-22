get_project_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- args[grepl("^--file=", args)]

  if (length(file_arg) > 0) {
    script_path <- normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = TRUE)
    return(normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE))
  }

  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

ensure_project_dirs <- function(project_root) {
  dirs <- c(
    "data/raw",
    "data/processed",
    "public/data"
  )

  for (dir in dirs) {
    dir.create(file.path(project_root, dir), recursive = TRUE, showWarnings = FALSE)
  }
}

month_sequence <- function(start_date, end_date) {
  seq(as.Date(start_date), as.Date(end_date), by = "month")
}

add_months <- function(dates, months) {
  parts <- as.POSIXlt(as.Date(dates))
  parts$mon <- parts$mon + months
  as.Date(parts)
}

current_month_start <- function() {
  as.Date(format(Sys.Date(), "%Y-%m-01"))
}

make_mock_series <- function(
  dates,
  base,
  amplitude,
  cycles,
  trend = 0,
  noise = 0.2,
  seed = 1,
  shocks = list()
) {
  set.seed(seed)
  n <- length(dates)
  phase <- seq(0, cycles * 2 * pi, length.out = n)
  raw_noise <- stats::filter(stats::rnorm(n, 0, noise), rep(1 / 3, 3), sides = 1)
  raw_noise[is.na(raw_noise)] <- 0

  values <- base +
    amplitude * sin(phase) +
    (amplitude * 0.45) * cos(phase / 2) +
    seq(0, trend, length.out = n) +
    as.numeric(raw_noise)

  for (shock in shocks) {
    center <- as.Date(shock$center)
    width <- shock$width
    magnitude <- shock$magnitude
    distance_months <- as.numeric(difftime(dates, center, units = "days")) / 30.44
    values <- values + magnitude * exp(-(distance_months^2) / (2 * width^2))
  }

  values
}

make_series_frame <- function(
  dates,
  chart_id,
  series_id,
  series_name,
  country,
  values,
  axis = "left",
  unit = "",
  source = "mock",
  source_url = "",
  frequency = "",
  source_note = ""
) {
  data.frame(
    date = format(dates, "%Y-%m-%d"),
    chart_id = chart_id,
    series_id = series_id,
    series_name = series_name,
    country = country,
    value = round(values, 3),
    axis = axis,
    unit = unit,
    source = source,
    source_url = source_url,
    frequency = frequency,
    source_note = source_note,
    stringsAsFactors = FALSE
  )
}

read_series_catalog <- function(project_root) {
  catalog_path <- file.path(project_root, "config/series_catalog.csv")
  utils::read.csv(
    catalog_path,
    stringsAsFactors = FALSE,
    fileEncoding = "UTF-8",
    check.names = FALSE,
    fill = TRUE
  )
}

apply_series_catalog <- function(data, catalog) {
  if (!nrow(data)) {
    return(data)
  }

  if (!"source_note" %in% names(catalog)) {
    catalog$source_note <- ""
  }
  if (!"source_note" %in% names(data)) {
    data$source_note <- ""
  }

  catalog_subset <- catalog[, c("series_id", "preferred_source", "source_url", "frequency", "source_note")]
  names(catalog_subset) <- c("series_id", "catalog_source", "catalog_source_url", "catalog_frequency", "catalog_source_note")
  enriched <- merge(data, catalog_subset, by = "series_id", all.x = TRUE, sort = FALSE)

  enriched$source <- ifelse(
    is.na(enriched$catalog_source) | enriched$catalog_source == "",
    enriched$source,
    enriched$catalog_source
  )
  enriched$source_url <- ifelse(
    is.na(enriched$catalog_source_url) | enriched$catalog_source_url == "",
    enriched$source_url,
    enriched$catalog_source_url
  )
  enriched$frequency <- ifelse(
    is.na(enriched$catalog_frequency) | enriched$catalog_frequency == "",
    enriched$frequency,
    enriched$catalog_frequency
  )
  enriched$source_note <- ifelse(
    is.na(enriched$catalog_source_note) | enriched$catalog_source_note == "",
    enriched$source_note,
    enriched$catalog_source_note
  )

  enriched$catalog_source <- NULL
  enriched$catalog_source_url <- NULL
  enriched$catalog_frequency <- NULL
  enriched$catalog_source_note <- NULL
  enriched[, c("date", "chart_id", "series_id", "series_name", "country", "value", "axis", "unit", "source", "source_url", "frequency", "source_note")]
}

clip_values <- function(values, lower, upper) {
  pmax(pmin(values, upper), lower)
}

write_csv_utf8 <- function(data, path) {
  utils::write.csv(data, path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
}
