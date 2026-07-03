args <- commandArgs(trailingOnly = FALSE)
file_arg <- args[grepl("^--file=", args)]

if (length(file_arg) > 0) {
  script_path <- normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = TRUE)
  project_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
} else {
  project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

source(file.path(project_root, "R/helpers.R"), local = TRUE)
source(file.path(project_root, "R/fetch_inflation.R"), local = TRUE)
source(file.path(project_root, "R/build_site_data.R"), local = TRUE)

ensure_project_dirs(project_root)

run_hicp_x12_adjustment_uncached <- run_hicp_x12_adjustment
run_hicp_x12_adjustment <- function(dates, values) {
  valid <- !is.na(dates) & !is.na(values) & values > 0
  cache_input <- data.frame(
    date = as.character(as.Date(dates[valid])),
    value = round(as.numeric(values[valid]), 8),
    stringsAsFactors = FALSE
  )
  cache_key <- paste0(
    length(cache_input$value), "_",
    tail(cache_input$date, 1), "_",
    sprintf("%.8f", tail(cache_input$value, 1)), "_",
    sprintf("%.8f", sum(cache_input$value))
  )
  cache_key <- gsub("[^0-9A-Za-z_.-]", "_", cache_key)
  cache_dir <- file.path(project_root, "data/processed/other_inflation_x13_cache")
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  cache_path <- file.path(cache_dir, paste0("swiss_x13_", cache_key, ".csv"))

  if (file.exists(cache_path) && file.info(cache_path)$size > 0) {
    cached <- utils::read.csv(cache_path, stringsAsFactors = FALSE, check.names = FALSE)
    cached$date <- as.Date(cached$date)
    return(cached)
  }
  if (file.exists(cache_path)) {
    unlink(cache_path)
  }

  start_time <- proc.time()[["elapsed"]]
  adjusted <- run_hicp_x12_adjustment_uncached(dates, values)
  elapsed <- proc.time()[["elapsed"]] - start_time
  message(sprintf("X-13 adjustment completed in %.1fs for latest date %s", elapsed, tail(cache_input$date, 1)))
  write_csv_utf8(adjusted, cache_path)
  adjusted
}

message("Building Other - Inflation Monitor data...")
public_data <- file.path(project_root, "public/data")
dir.create(public_data, recursive = TRUE, showWarnings = FALSE)

inflation_path <- file.path(public_data, "inflation_series.csv")
processed_inflation_path <- file.path(project_root, "data/processed/inflation_series.csv")
metadata_path <- file.path(public_data, "metadata.json")

inflation_ok <- file.exists(inflation_path) && file.info(inflation_path)$size > 0
processed_inflation_ok <- file.exists(processed_inflation_path) && file.info(processed_inflation_path)$size > 0

if (!inflation_ok && !processed_inflation_ok) {
  stop("Missing existing inflation_series.csv. Run the full inflation update once before the Other-only update.")
}

base_path <- if (inflation_ok) inflation_path else processed_inflation_path
previous_inflation <- utils::read.csv(base_path, stringsAsFactors = FALSE, check.names = FALSE)
other_rows <- read_swiss_cpi_rows()

if (!nrow(other_rows)) {
  stop("Swiss CPI update returned no rows.")
}

other_chart_ids <- unique(other_rows$chart_id)
kept <- previous_inflation[!previous_inflation$chart_id %in% other_chart_ids, , drop = FALSE]
inflation <- rbind(kept, other_rows)
inflation <- inflation[order(inflation$chart_id, inflation$series_id, inflation$date), ]

previous_metadata <- read_metadata_json(metadata_path)
other_last_new <- summarize_new_observations(other_rows, inflation_path, previous_metadata[["other-inflation_last_new"]])

write_csv_utf8(inflation, inflation_path)
write_csv_utf8(inflation, processed_inflation_path)

metadata <- previous_metadata
metadata$last_updated <- format(Sys.Date(), "%Y-%m-%d")
metadata$data_mode <- "source_linked_mock_values"
metadata$generated_by <- "R/run_other_inflation_update.R"
metadata$inflation_rows <- nrow(inflation)
metadata[["other-inflation_last_new"]] <- other_last_new
if (is.null(metadata$inflation_last_new)) {
  metadata$inflation_last_new <- list(date = "", description = "No new observations in latest update")
}
if (is.null(metadata$activity_last_new)) {
  metadata$activity_last_new <- list(date = "", description = "No new observations in latest update")
}
write_metadata_json(metadata, metadata_path)

message(sprintf("Other inflation rows: %s", nrow(other_rows)))
message(sprintf("Inflation rows: %s", nrow(inflation)))
message("Done.")
