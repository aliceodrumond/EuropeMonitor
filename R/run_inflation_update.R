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

ensure_project_dirs(project_root)

message("Building Europe inflation monitor data...")
inflation <- build_inflation_series(project_root)
public_data <- file.path(project_root, "public/data")
dir.create(public_data, recursive = TRUE, showWarnings = FALSE)
write_csv_utf8(inflation, file.path(public_data, "inflation_series.csv"))

metadata_path <- file.path(public_data, "metadata.json")
metadata <- c(
  "{",
  sprintf('  "last_updated": "%s",', format(Sys.Date(), "%Y-%m-%d")),
  '  "data_mode": "source_linked_mock_values",',
  '  "generated_by": "R/run_inflation_update.R",',
  sprintf('  "inflation_rows": %s', nrow(inflation)),
  "}"
)
writeLines(metadata, metadata_path, useBytes = TRUE)

message(sprintf("Inflation rows: %s", nrow(inflation)))
message("Done.")
