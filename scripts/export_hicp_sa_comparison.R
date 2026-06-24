source(file.path(getwd(), "R/helpers.R"))
source(file.path(getwd(), "R/fetch_inflation.R"))

if (!requireNamespace("seasonal", quietly = TRUE)) stop("Package 'seasonal' is required")
if (!requireNamespace("openxlsx", quietly = TRUE)) stop("Package 'openxlsx' is required")
if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Package 'ggplot2' is required")

output_dir <- file.path(getwd(), "reports")
image_dir <- file.path(output_dir, "hicp_sa_comparison_charts")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)

series_definitions <- data.frame(
  label = c(
    "Headline",
    "Core ex-Energy, Food, Alcohol and Tobacco",
    "Non-Energy Industrial Goods",
    "Services"
  ),
  short_name = c("headline", "core", "neig", "services"),
  dataset = c("teicp000", "teicp200", "teicp290", "teicp280"),
  coicop = c("CP00", "TOT_X_NRG_FOOD", "IGD_NNRG", "SERV"),
  base_series_id = c("hicp_headline", "hicp_core", "core_goods", "core_services"),
  ecb_key = c(
    "M.U2.Y.000000.4F0.INX",
    "M.U2.Y.XEF000.4F0.INX",
    "M.U2.Y.IGXE00.4F0.INX",
    "M.U2.Y.SERV00.4F0.INX"
  ),
  stringsAsFactors = FALSE
)

read_eurostat_hicp_midx_index <- function(coicop_code, label) {
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
    series = label,
    source = "Eurostat prc_hicp_midx, unit I15",
    stringsAsFactors = FALSE
  )
}

run_x13_adjustment <- function(dates, values) {
  valid <- !is.na(dates) & !is.na(values) & values > 0
  dates <- as.Date(dates[valid])
  values <- as.numeric(values[valid])
  order_index <- order(dates)
  dates <- dates[order_index]
  values <- values[order_index]

  start_date <- as.POSIXlt(min(dates))
  series_ts <- stats::ts(
    values,
    start = c(start_date$year + 1900, start_date$mon + 1),
    frequency = 12
  )

  fit <- seasonal::seas(
    series_ts,
    transform.function = "log",
    regression.aictest = c("td", "easter"),
    outlier = "",
    automdl = ""
  )
  adjusted <- as.numeric(seasonal::final(fit))
  data.frame(
    date = dates[seq_along(adjusted)],
    local_sa_index = adjusted,
    stringsAsFactors = FALSE
  )
}

rate_columns <- function(index_values) {
  data.frame(
    mom_saar = (index_values / c(NA, head(index_values, -1)))^12 * 100 - 100,
    qoq_saar = (index_values / c(rep(NA, 3), head(index_values, -3)))^4 * 100 - 100,
    hoh_saar = (index_values / c(rep(NA, 6), head(index_values, -6)))^2 * 100 - 100
  )
}

make_definition <- function(i) {
  data.frame(
    dataset = series_definitions$dataset[i],
    base_series_id = series_definitions$base_series_id[i],
    ecb_key = series_definitions$ecb_key[i],
    stringsAsFactors = FALSE
  )
}

plot_index_comparison <- function(data, label, path) {
  plot_data <- rbind(
    data.frame(date = data$date, value = data$local_sa_index, series = "Local X-13 SA"),
    data.frame(date = data$date, value = data$ecb_sa_index, series = "ECB SA")
  )
  plot_data <- plot_data[!is.na(plot_data$value), ]
  p <- ggplot2::ggplot(plot_data, ggplot2::aes(date, value, color = series)) +
    ggplot2::geom_line(linewidth = 0.65) +
    ggplot2::scale_color_manual(values = c("Local X-13 SA" = "#11675f", "ECB SA" = "#111111")) +
    ggplot2::labs(title = paste0(label, ": SA index comparison"), x = NULL, y = "Index") +
    ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(legend.title = ggplot2::element_blank(), plot.title = ggplot2::element_text(face = "bold"))
  ggplot2::ggsave(path, p, width = 9.5, height = 4.8, dpi = 160)
}

plot_rate_comparison <- function(data, label, path) {
  plot_data <- rbind(
    data.frame(date = data$date, value = data$local_mom_saar, metric = "% MoM SAAR", series = "Local X-13 SA"),
    data.frame(date = data$date, value = data$ecb_mom_saar, metric = "% MoM SAAR", series = "ECB SA"),
    data.frame(date = data$date, value = data$local_qoq_saar, metric = "% QoQ SAAR", series = "Local X-13 SA"),
    data.frame(date = data$date, value = data$ecb_qoq_saar, metric = "% QoQ SAAR", series = "ECB SA"),
    data.frame(date = data$date, value = data$local_hoh_saar, metric = "% HoH SAAR", series = "Local X-13 SA"),
    data.frame(date = data$date, value = data$ecb_hoh_saar, metric = "% HoH SAAR", series = "ECB SA")
  )
  plot_data <- plot_data[!is.na(plot_data$value) & plot_data$date >= as.Date("2018-01-01"), ]
  p <- ggplot2::ggplot(plot_data, ggplot2::aes(date, value, color = series, linetype = series)) +
    ggplot2::geom_hline(yintercept = 0, color = "#9a9a9a", linewidth = 0.3) +
    ggplot2::geom_line(linewidth = 0.55) +
    ggplot2::facet_wrap(~ metric, ncol = 1, scales = "free_y") +
    ggplot2::scale_color_manual(values = c("Local X-13 SA" = "#11675f", "ECB SA" = "#111111")) +
    ggplot2::scale_linetype_manual(values = c("Local X-13 SA" = "solid", "ECB SA" = "dashed")) +
    ggplot2::labs(title = paste0(label, ": SAAR rate comparison"), x = NULL, y = "%") +
    ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(legend.title = ggplot2::element_blank(), plot.title = ggplot2::element_text(face = "bold"))
  ggplot2::ggsave(path, p, width = 9.5, height = 7.2, dpi = 160)
}

comparison_tables <- list()
summary_rows <- list()
for (i in seq_len(nrow(series_definitions))) {
  definition <- make_definition(i)
  nsa <- read_eurostat_hicp_midx_index(series_definitions$coicop[i], series_definitions$label[i])
  ecb <- read_ecb_hicp_sa_index_rows(definition)
  local <- run_x13_adjustment(nsa$date, nsa$nsa_index)

  data <- merge(nsa[, c("date", "nsa_index")], local, by = "date", all.x = TRUE)
  data <- merge(data, ecb[, c("date", "index")], by = "date", all.x = TRUE)
  names(data)[names(data) == "index"] <- "ecb_sa_index"
  data <- data[order(data$date), ]
  data$local_sa_index_raw <- data$local_sa_index
  base_window <- data$date >= as.Date("2025-01-01") & data$date <= as.Date("2025-12-01")
  common_base <- base_window & !is.na(data$local_sa_index_raw) & !is.na(data$ecb_sa_index) & data$local_sa_index_raw != 0
  if (!any(common_base)) {
    common_base <- !is.na(data$local_sa_index_raw) & !is.na(data$ecb_sa_index) & data$local_sa_index_raw != 0
  }
  scale_factor <- mean(data$ecb_sa_index[common_base] / data$local_sa_index_raw[common_base], na.rm = TRUE)
  data$local_sa_index <- data$local_sa_index_raw * scale_factor

  local_rates <- rate_columns(data$local_sa_index)
  ecb_rates <- rate_columns(data$ecb_sa_index)
  data$local_mom_saar <- local_rates$mom_saar
  data$local_qoq_saar <- local_rates$qoq_saar
  data$local_hoh_saar <- local_rates$hoh_saar
  data$ecb_mom_saar <- ecb_rates$mom_saar
  data$ecb_qoq_saar <- ecb_rates$qoq_saar
  data$ecb_hoh_saar <- ecb_rates$hoh_saar
  data$index_diff <- data$local_sa_index - data$ecb_sa_index
  data$mom_saar_diff <- data$local_mom_saar - data$ecb_mom_saar
  data$qoq_saar_diff <- data$local_qoq_saar - data$ecb_qoq_saar
  data$hoh_saar_diff <- data$local_hoh_saar - data$ecb_hoh_saar

  comparison_tables[[series_definitions$short_name[i]]] <- data

  recent <- data[data$date >= as.Date("2018-01-01"), ]
  summary_rows[[i]] <- data.frame(
    series = series_definitions$label[i],
    start_date = min(data$date, na.rm = TRUE),
    last_date = max(data$date[!is.na(data$local_sa_index) & !is.na(data$ecb_sa_index)], na.rm = TRUE),
    index_rmse_2018 = sqrt(mean(recent$index_diff^2, na.rm = TRUE)),
    mom_saar_rmse_2018 = sqrt(mean(recent$mom_saar_diff^2, na.rm = TRUE)),
    qoq_saar_rmse_2018 = sqrt(mean(recent$qoq_saar_diff^2, na.rm = TRUE)),
    hoh_saar_rmse_2018 = sqrt(mean(recent$hoh_saar_diff^2, na.rm = TRUE)),
    last_index_diff = tail(stats::na.omit(data$index_diff), 1),
    last_mom_saar_diff = tail(stats::na.omit(data$mom_saar_diff), 1),
    last_qoq_saar_diff = tail(stats::na.omit(data$qoq_saar_diff), 1),
    last_hoh_saar_diff = tail(stats::na.omit(data$hoh_saar_diff), 1),
    index_scale_factor = scale_factor,
    stringsAsFactors = FALSE
  )

  plot_index_comparison(
    data,
    series_definitions$label[i],
    file.path(image_dir, paste0(series_definitions$short_name[i], "_index.png"))
  )
  plot_rate_comparison(
    data,
    series_definitions$label[i],
    file.path(image_dir, paste0(series_definitions$short_name[i], "_rates.png"))
  )
}

summary <- do.call(rbind, summary_rows)
numeric_cols <- names(summary)[vapply(summary, is.numeric, logical(1))]
summary[numeric_cols] <- lapply(summary[numeric_cols], round, 4)

wb <- openxlsx::createWorkbook(creator = "Legacy Europe Monitor")
openxlsx::addWorksheet(wb, "Summary")
openxlsx::writeData(wb, "Summary", data.frame(
  note = c(
    "Local seasonal adjustment uses X-13ARIMA-SEATS via the R seasonal package.",
    "Specification: log transform, automatic ARIMA model, automatic outlier detection, AIC tests for trading day and Easter.",
    "NSA source: Eurostat prc_hicp_midx HICP index, 2015=100. ECB comparison source: ECB HICP working-day and seasonally adjusted index, 2025=100.",
    "Local SA index is rescaled to ECB 2025=100 on the common 2025 window. SAAR rates are invariant to this rescaling.",
    "RMSE metrics are computed from 2018 onward."
  )
), startRow = 1, colNames = FALSE)
openxlsx::writeData(wb, "Summary", summary, startRow = 7)
openxlsx::freezePane(wb, "Summary", firstActiveRow = 8)
openxlsx::setColWidths(wb, "Summary", cols = 1:ncol(summary), widths = "auto")

for (i in seq_len(nrow(series_definitions))) {
  sheet_name <- substr(series_definitions$label[i], 1, 31)
  short_name <- series_definitions$short_name[i]
  openxlsx::addWorksheet(wb, sheet_name)
  openxlsx::writeData(wb, sheet_name, comparison_tables[[short_name]])
  openxlsx::freezePane(wb, sheet_name, firstActiveRow = 2)
  openxlsx::setColWidths(wb, sheet_name, cols = 1:ncol(comparison_tables[[short_name]]), widths = "auto")
  openxlsx::insertImage(
    wb,
    sheet_name,
    file.path(image_dir, paste0(short_name, "_index.png")),
    startRow = 2,
    startCol = ncol(comparison_tables[[short_name]]) + 3,
    width = 9.5,
    height = 4.8
  )
  openxlsx::insertImage(
    wb,
    sheet_name,
    file.path(image_dir, paste0(short_name, "_rates.png")),
    startRow = 27,
    startCol = ncol(comparison_tables[[short_name]]) + 3,
    width = 9.5,
    height = 7.2
  )
}

output_path <- file.path(output_dir, "hicp_sa_comparison_x13_vs_ecb.xlsx")
openxlsx::saveWorkbook(wb, output_path, overwrite = TRUE)
message(output_path)
