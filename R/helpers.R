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
  source = "mock"
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
    stringsAsFactors = FALSE
  )
}

clip_values <- function(values, lower, upper) {
  pmax(pmin(values, upper), lower)
}

write_csv_utf8 <- function(data, path) {
  utils::write.csv(data, path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
}
