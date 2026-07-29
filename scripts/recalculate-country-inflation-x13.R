options(stringsAsFactors = FALSE)

if (!requireNamespace("seasonal", quietly = TRUE)) {
  stop("The R package 'seasonal' is required.")
}

input_path <- file.path("data", "processed", "country_inflation_indices.csv")
output_path <- file.path("public", "data", "country_inflation_series.csv")
indices <- utils::read.csv(input_path, check.names = FALSE)
published <- utils::read.csv(output_path, check.names = FALSE, fileEncoding = "UTF-8-BOM")
indices$date <- as.Date(indices$date)

run_x13 <- function(rows) {
  rows <- rows[order(rows$date), ]
  rows <- rows[rows$date >= as.Date("2012-01-01") & !is.na(rows$nsa_index) & rows$nsa_index > 0, ]
  start <- as.POSIXlt(min(rows$date))
  series <- stats::ts(
    rows$nsa_index,
    start = c(start$year + 1900, start$mon + 1),
    frequency = 12
  )
  fit <- seasonal::seas(
    series,
    transform.function = "log",
    regression.aictest = "easter",
    outlier = "",
    automdl = "",
    x11 = ""
  )
  adjusted <- as.numeric(seasonal::final(fit))
  rows <- rows[seq_along(adjusted), ]
  rows$sa_index <- adjusted
  rows$mom_sa <- rows$sa_index / c(NA_real_, head(rows$sa_index, -1)) * 100 - 100
  rows$qoq_saar <- (rows$sa_index / c(rep(NA_real_, 3), head(rows$sa_index, -3)))^4 * 100 - 100
  rows
}

source_url <- "https://ec.europa.eu/eurostat/databrowser/view/prc_hicp_midx/default/table?lang=en"
note <- paste(
  "Annualized QoQ rate calculated from a seasonally adjusted HICP index.",
  "Seasonal adjustment uses X-13ARIMA-SEATS in X-11 mode from 2012,",
  "matching the Legacy methodology in the Inflation Monitor."
)

groups <- split(indices, interaction(indices$geo, indices$component, drop = TRUE))
adjusted <- lapply(groups, function(rows) {
  tryCatch(run_x13(rows), error = function(error) {
    warning(sprintf("X-13 failed for %s/%s: %s", rows$geo[1], rows$component[1], error$message))
    data.frame()
  })
})
adjusted <- do.call(rbind, adjusted)
if (!nrow(adjusted)) stop("No country series were seasonally adjusted.")

make_rows <- function(rows, metric, suffix, series_name, unit) {
  valid <- !is.na(rows[[metric]])
  rows <- rows[valid, ]
  geo <- tolower(rows$geo)
  data.frame(
    date = format(rows$date, "%Y-%m-%d"),
    chart_id = sprintf("country_%s_%s_rates", geo, rows$component),
    series_id = sprintf("%s_%s_%s", geo, rows$component, suffix),
    series_name = series_name,
    country = rows$country,
    value = round(rows[[metric]], 6),
    axis = "left",
    unit = unit,
    source = "Eurostat HICP / Legacy X-13/X-11",
    source_url = source_url,
    frequency = "monthly",
    source_note = note,
    stringsAsFactors = FALSE
  )
}

published <- published[!grepl("_(3m_saar|qoq_saar|mom_sa)$", published$series_id), ]
x13_rows <- rbind(
  make_rows(adjusted, "qoq_saar", "qoq_saar", "% QoQ SAAR", "% QoQ SAAR"),
  make_rows(adjusted, "mom_sa", "mom_sa", "% MoM SA", "% m/m SA")
)
published <- rbind(published, x13_rows)
published <- published[order(published$chart_id, published$series_id, published$date), ]

utils::write.csv(
  published,
  output_path,
  row.names = FALSE,
  na = "",
  fileEncoding = "UTF-8"
)
cat(sprintf("Wrote %s rows with X-13/X-11 country rates.\n", nrow(published)))
