library(openxlsx)

output_path <- file.path(getwd(), "PMI_official_data_template.xlsx")
dates <- seq(as.Date("1998-01-01"), as.Date("2026-06-01"), by = "month")
columns <- c(
  "date",
  "euro_area_final",
  "euro_area_flash",
  "germany_final",
  "france_final",
  "spain_final",
  "uk_final",
  "italy_final"
)

wb <- createWorkbook(creator = "Legacy Europe Monitor")
addWorksheet(wb, "Instructions", gridLines = FALSE)

instructions <- data.frame(
  Item = c(
    "Purpose",
    "Source",
    "Frequency",
    "Final series",
    "Flash series",
    "Missing values",
    "Do not change",
    "Date convention"
  ),
  Guidance = c(
    "Supply official PMI history for the Europe Monitor charts.",
    "Use only official S&P Global / HCOB PMI data or a licensed redistribution of those exact series.",
    "Monthly.",
    "Paste the final published Euro Area and country indices in the *_final columns.",
    "Paste only the Euro Area flash estimate in euro_area_flash. Do not backfill it with final values.",
    "Leave cells blank when a series did not exist or a value is unavailable.",
    "Keep sheet names, column names, date rows and workbook structure unchanged.",
    "Values belong to the reference month shown in date, formatted as YYYY-MM."
  ),
  stringsAsFactors = FALSE
)
writeData(wb, "Instructions", instructions, withFilter = FALSE)

header_style <- createStyle(
  fontColour = "#FFFFFF",
  fgFill = "#1F4E78",
  textDecoration = "bold",
  halign = "center",
  valign = "center"
)
section_style <- createStyle(
  fontColour = "#1F1F1F",
  fgFill = "#D9EAF7",
  textDecoration = "bold",
  valign = "top"
)
date_style <- createStyle(numFmt = "yyyy-mm", halign = "center")
number_style <- createStyle(numFmt = "0.0", halign = "right")

addStyle(wb, "Instructions", section_style, rows = 1, cols = 1:2, gridExpand = TRUE)
setColWidths(wb, "Instructions", cols = 1, widths = 20)
setColWidths(wb, "Instructions", cols = 2, widths = 95)
setRowHeights(wb, "Instructions", rows = 1:nrow(instructions) + 1, heights = 30)
wrapText <- createStyle(wrapText = TRUE, valign = "top")
addStyle(wb, "Instructions", wrapText, rows = 2:(nrow(instructions) + 1), cols = 1:2, gridExpand = TRUE)
freezePane(wb, "Instructions", firstActiveRow = 2)

for (sheet in c("Composite", "Manufacturing", "Services")) {
  addWorksheet(wb, sheet, gridLines = FALSE)
  data <- data.frame(date = dates, matrix(NA_real_, nrow = length(dates), ncol = 7))
  names(data) <- columns
  writeData(wb, sheet, data, withFilter = TRUE, keepNA = FALSE)
  addStyle(wb, sheet, header_style, rows = 1, cols = 1:length(columns), gridExpand = TRUE)
  addStyle(wb, sheet, date_style, rows = 2:(nrow(data) + 1), cols = 1, gridExpand = TRUE)
  addStyle(wb, sheet, number_style, rows = 2:(nrow(data) + 1), cols = 2:length(columns), gridExpand = TRUE)
  dataValidation(
    wb, sheet,
    cols = 2:length(columns), rows = 2:(nrow(data) + 1),
    type = "decimal", operator = "between", value = c(0, 100),
    allowBlank = TRUE
  )
  freezePane(wb, sheet, firstActiveRow = 2, firstActiveCol = 2)
  setColWidths(wb, sheet, cols = 1, widths = 13)
  setColWidths(wb, sheet, cols = 2:length(columns), widths = 20)
  setRowHeights(wb, sheet, rows = 1, heights = 28)
}

saveWorkbook(wb, output_path, overwrite = TRUE)
cat(output_path)
