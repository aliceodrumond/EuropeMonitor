if (!requireNamespace("openxlsx", quietly = TRUE)) {
  stop("Package 'openxlsx' is required")
}

project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
input_path <- file.path(project_root, "public/data/inflation_series.csv")
output_dir <- file.path(project_root, "reports")
image_dir <- file.path(output_dir, "hicp_qoq_saar_3mma_charts")
output_path <- file.path(output_dir, "hicp_qoq_saar_3mma_legacy_vs_ecb.xlsx")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)

inflation <- utils::read.csv(input_path, stringsAsFactors = FALSE, check.names = FALSE)
inflation$date <- as.Date(inflation$date)
inflation$value <- as.numeric(inflation$value)

definitions <- data.frame(
  label = c("Headline", "Core", "Goods", "Services"),
  sheet = c("Headline", "Core", "Goods", "Services"),
  ecb = c(
    "hicp_headline_qoq_saar",
    "hicp_core_qoq_saar",
    "hicp_goods_qoq_saar",
    "hicp_services_qoq_saar"
  ),
  legacy = c(
    "hicp_headline_qoq_saar_legacy",
    "hicp_core_qoq_saar_legacy",
    "hicp_goods_qoq_saar_legacy",
    "hicp_services_qoq_saar_legacy"
  ),
  stringsAsFactors = FALSE
)

roll3 <- function(values) {
  stats::filter(values, rep(1 / 3, 3), sides = 1)
}

series_frame <- function(series_id, value_name) {
  rows <- inflation[inflation$series_id == series_id, c("date", "value")]
  rows <- rows[order(rows$date), ]
  names(rows)[names(rows) == "value"] <- value_name
  rows
}

make_comparison <- function(definition) {
  ecb <- series_frame(definition$ecb, "ecb_qoq_saar")
  legacy <- series_frame(definition$legacy, "legacy_qoq_saar")
  data <- merge(ecb, legacy, by = "date", all = TRUE)
  data <- data[order(data$date), ]
  data$ecb_qoq_saar_3mma <- as.numeric(roll3(data$ecb_qoq_saar))
  data$legacy_qoq_saar_3mma <- as.numeric(roll3(data$legacy_qoq_saar))
  data$legacy_minus_ecb_3mma <- data$legacy_qoq_saar_3mma - data$ecb_qoq_saar_3mma
  data
}

comparison_tables <- lapply(seq_len(nrow(definitions)), function(i) make_comparison(definitions[i, ]))
names(comparison_tables) <- definitions$label

plot_comparison <- function(data, label, path) {
  plot_data <- data[!is.na(data$ecb_qoq_saar_3mma) | !is.na(data$legacy_qoq_saar_3mma), ]
  grDevices::png(path, width = 1400, height = 760, res = 160)
  on.exit(grDevices::dev.off(), add = TRUE)
  y_values <- c(plot_data$ecb_qoq_saar_3mma, plot_data$legacy_qoq_saar_3mma)
  y_range <- range(y_values, na.rm = TRUE)
  pad <- diff(y_range) * 0.12
  if (!is.finite(pad) || pad == 0) pad <- 1
  plot(
    plot_data$date,
    plot_data$ecb_qoq_saar_3mma,
    type = "l",
    col = "#111111",
    lwd = 2,
    ylim = c(y_range[1] - pad, y_range[2] + pad),
    xlab = "",
    ylab = "%",
    main = paste0(label, " - %QoQ SAAR 3MMA")
  )
  lines(plot_data$date, plot_data$legacy_qoq_saar_3mma, col = "#11675f", lwd = 2)
  abline(h = 0, col = "#999999", lty = 2)
  legend(
    "topleft",
    legend = c("SA - ECB", "SA - Legacy"),
    col = c("#111111", "#11675f"),
    lwd = 2,
    bty = "n"
  )
}

summary_rows <- do.call(rbind, lapply(seq_len(nrow(definitions)), function(i) {
  data <- comparison_tables[[definitions$label[i]]]
  common <- data[!is.na(data$ecb_qoq_saar_3mma) & !is.na(data$legacy_qoq_saar_3mma), ]
  recent <- common[common$date >= as.Date("2018-01-01"), ]
  last <- tail(common, 1)
  data.frame(
    series = definitions$label[i],
    first_common_date = if (nrow(common)) min(common$date) else as.Date(NA),
    last_common_date = if (nrow(common)) max(common$date) else as.Date(NA),
    latest_ecb_qoq_saar_3mma = if (nrow(last)) last$ecb_qoq_saar_3mma else NA_real_,
    latest_legacy_qoq_saar_3mma = if (nrow(last)) last$legacy_qoq_saar_3mma else NA_real_,
    latest_legacy_minus_ecb = if (nrow(last)) last$legacy_minus_ecb_3mma else NA_real_,
    rmse_2018_onward = sqrt(mean(recent$legacy_minus_ecb_3mma^2, na.rm = TRUE)),
    mean_abs_diff_2018_onward = mean(abs(recent$legacy_minus_ecb_3mma), na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}))

numeric_cols <- names(summary_rows)[vapply(summary_rows, is.numeric, logical(1))]
summary_rows[numeric_cols] <- lapply(summary_rows[numeric_cols], round, 3)

wb <- openxlsx::createWorkbook(creator = "Legacy Europe Monitor")
header_style <- openxlsx::createStyle(textDecoration = "bold", fgFill = "#DCEFD4", border = "Bottom")
percent_style <- openxlsx::createStyle(numFmt = "0.00")
date_style <- openxlsx::createStyle(numFmt = "mmm-yy")

openxlsx::addWorksheet(wb, "Summary")
openxlsx::writeData(wb, "Summary", data.frame(
  note = c(
    "Comparison of Legacy seasonal adjustment vs ECB official seasonal adjustment.",
    "Metric: %QoQ SAAR 3MMA, calculated as a 3-month trailing average of the monthly %QoQ SAAR series used in the Inflation Monitor.",
    "Source file: public/data/inflation_series.csv.",
    paste("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  )
), colNames = FALSE)
openxlsx::writeData(wb, "Summary", summary_rows, startRow = 7)
openxlsx::addStyle(wb, "Summary", header_style, rows = 7, cols = seq_len(ncol(summary_rows)), gridExpand = TRUE)
openxlsx::addStyle(wb, "Summary", date_style, rows = 8:(nrow(summary_rows) + 7), cols = 2:3, gridExpand = TRUE)
openxlsx::addStyle(wb, "Summary", percent_style, rows = 8:(nrow(summary_rows) + 7), cols = 4:ncol(summary_rows), gridExpand = TRUE)
openxlsx::freezePane(wb, "Summary", firstActiveRow = 8)
openxlsx::setColWidths(wb, "Summary", cols = 1:ncol(summary_rows), widths = "auto")

for (i in seq_len(nrow(definitions))) {
  sheet <- definitions$sheet[i]
  data <- comparison_tables[[definitions$label[i]]]
  openxlsx::addWorksheet(wb, sheet)
  openxlsx::writeData(wb, sheet, data)
  openxlsx::addStyle(wb, sheet, header_style, rows = 1, cols = seq_len(ncol(data)), gridExpand = TRUE)
  openxlsx::addStyle(wb, sheet, date_style, rows = 2:(nrow(data) + 1), cols = 1, gridExpand = TRUE)
  openxlsx::addStyle(wb, sheet, percent_style, rows = 2:(nrow(data) + 1), cols = 2:ncol(data), gridExpand = TRUE)
  openxlsx::freezePane(wb, sheet, firstActiveRow = 2)
  openxlsx::setColWidths(wb, sheet, cols = 1:ncol(data), widths = "auto")

  chart_path <- file.path(image_dir, paste0(tolower(definitions$sheet[i]), "_qoq_saar_3mma.png"))
  plot_comparison(data, definitions$label[i], chart_path)
  openxlsx::insertImage(
    wb,
    sheet,
    chart_path,
    startRow = 2,
    startCol = 8,
    width = 8.8,
    height = 4.8
  )
}

openxlsx::saveWorkbook(wb, output_path, overwrite = TRUE)
message(output_path)
