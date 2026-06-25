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
source(file.path(project_root, "R/fetch_ecb_speakers.R"), local = TRUE)
source(file.path(project_root, "R/build_site_data.R"), local = TRUE)

ensure_project_dirs(project_root)

build_series_with_fallback <- function(builder, fallback_path, label) {
  tryCatch(
    builder(),
    error = function(error) {
      warning(sprintf("%s update failed: %s. Continuing with last valid local data.", label, error$message))
      if (!file.exists(fallback_path)) {
        stop(sprintf("%s update failed and no fallback file exists at %s", label, fallback_path))
      }
      utils::read.csv(fallback_path, stringsAsFactors = FALSE, check.names = FALSE)
    }
  )
}

message("Building Europe monitor data...")
activity <- build_series_with_fallback(
  builder = function() build_activity_series(project_root),
  fallback_path = file.path(project_root, "data/processed/activity_series.csv"),
  label = "Activity"
)
inflation <- build_series_with_fallback(
  builder = function() build_inflation_series(project_root),
  fallback_path = file.path(project_root, "data/processed/inflation_series.csv"),
  label = "Inflation"
)
speakers <- build_series_with_fallback(
  builder = function() build_ecb_speakers(project_root),
  fallback_path = file.path(project_root, "data/processed/ecb_speakers.csv"),
  label = "ECB Speakers"
)
summary <- build_site_data(project_root, activity, inflation, speakers)

message(sprintf("Activity rows: %s", summary$activity_rows))
message(sprintf("Inflation rows: %s", summary$inflation_rows))
message(sprintf("ECB speaker rows: %s", summary$speaker_rows))
message("Done.")
