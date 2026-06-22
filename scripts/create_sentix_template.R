library(openxlsx)

args <- commandArgs(trailingOnly = FALSE)
file_arg <- args[grepl("^--file=", args)]
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "scripts/create_sentix_template.R"
project_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "\\", mustWork = TRUE)
out <- file.path(project_root, "Sentix_official_history_template.xlsx")
processed <- file.path(project_root, "data", "processed", "activity_series.csv")

input_dates <- seq(as.Date("2003-01-01"), as.Date("2026-07-01"), by = "month")
input <- data.frame(
  date = format(input_dates, "%Y-%m-%d"),
  sentix_ea = NA_real_,
  notes = "",
  stringsAsFactors = FALSE
)

current <- data.frame()
if (file.exists(processed)) {
  rows <- read.csv(processed, stringsAsFactors = FALSE, check.names = FALSE)
  current <- rows[
    rows$chart_id == "sentix_pmi" & rows$series_id == "sentix_ea",
    c("date", "value", "source")
  ]
  names(current) <- c("date", "current_site_value", "current_site_source")
  current <- current[order(as.Date(current$date)), ]
}

instructions <- data.frame(
  item = c("Preencher", "Frequencia", "Data", "Serie usada no site depois", "Release citado"),
  detail = c(
    "Cole o historico oficial na aba Sentix_Official, coluna sentix_ea. Pode deixar notes em branco.",
    "Mensal, uma linha por mes.",
    "Use o primeiro dia do mes no formato YYYY-MM-DD. Exemplo: 2026-07-01 para o dado publicado em 6/jul.",
    "chart_id=sentix_pmi, series_id=sentix_ea, eixo direito, fonte Sentix.",
    "O proximo valor esperado e julho/2026, publicado em 2026-07-06."
  ),
  stringsAsFactors = FALSE
)

wb <- createWorkbook()
addWorksheet(wb, "Sentix_Official")
writeData(wb, "Sentix_Official", input)
setColWidths(wb, "Sentix_Official", cols = 1:3, widths = c(14, 14, 36))
freezePane(wb, "Sentix_Official", firstRow = TRUE)

addWorksheet(wb, "Current_Site_Sentix")
writeData(wb, "Current_Site_Sentix", current)
setColWidths(wb, "Current_Site_Sentix", cols = 1:3, widths = c(14, 18, 24))
freezePane(wb, "Current_Site_Sentix", firstRow = TRUE)

addWorksheet(wb, "Instructions")
writeData(wb, "Instructions", instructions)
setColWidths(wb, "Instructions", cols = 1:2, widths = c(22, 105))

header <- createStyle(textDecoration = "bold", fgFill = "#D9EAF7", border = "Bottom")
num <- createStyle(numFmt = "0.0")
addStyle(wb, "Sentix_Official", header, rows = 1, cols = 1:3, gridExpand = TRUE)
addStyle(wb, "Current_Site_Sentix", header, rows = 1, cols = 1:max(1, ncol(current)), gridExpand = TRUE)
addStyle(wb, "Instructions", header, rows = 1, cols = 1:2, gridExpand = TRUE)
addStyle(wb, "Sentix_Official", num, rows = 2:(nrow(input) + 1), cols = 2, gridExpand = TRUE)
if (nrow(current) > 0) {
  addStyle(wb, "Current_Site_Sentix", num, rows = 2:(nrow(current) + 1), cols = 2, gridExpand = TRUE)
}

saveWorkbook(wb, out, overwrite = TRUE)
cat(normalizePath(out, winslash = "\\"), "\n", sep = "")
