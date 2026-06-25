args <- commandArgs(trailingOnly = FALSE)
file_arg <- args[grepl("^--file=", args)]

if (length(file_arg) > 0) {
  script_path <- normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = TRUE)
  project_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
} else {
  project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

source(file.path(project_root, "R/helpers.R"), local = TRUE)
source(file.path(project_root, "R/fetch_activity.R"), local = TRUE)
source(file.path(project_root, "R/fetch_inflation.R"), local = TRUE)
source(file.path(project_root, "R/build_site_data.R"), local = TRUE)

ensure_project_dirs(project_root)

message("Building Europe inflation monitor data...")
inflation <- build_inflation_series(project_root)
public_data <- file.path(project_root, "public/data")
dir.create(public_data, recursive = TRUE, showWarnings = FALSE)
inflation_path <- file.path(public_data, "inflation_series.csv")
metadata_path <- file.path(public_data, "metadata.json")
previous_metadata <- read_metadata_json(metadata_path)
inflation_last_new <- summarize_new_observations(inflation, inflation_path, previous_metadata$inflation_last_new)
write_csv_utf8(inflation, inflation_path)

metadata <- previous_metadata
metadata$last_updated <- format(Sys.Date(), "%Y-%m-%d")
metadata$data_mode <- "source_linked_mock_values"
metadata$generated_by <- "R/run_inflation_update.R"
metadata$inflation_rows <- nrow(inflation)
metadata$inflation_last_new <- inflation_last_new
if (is.null(metadata$activity_last_new)) {
  metadata$activity_last_new <- list(date = "", description = "No new observations in latest update")
}
write_metadata_json(
  metadata,
  metadata_path
)

message(sprintf("Inflation rows: %s", nrow(inflation)))
message("Done.")
