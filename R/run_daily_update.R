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

message("Building Europe monitor data...")
activity <- build_activity_series(project_root)
inflation <- build_inflation_series(project_root)
speakers <- build_ecb_speakers(project_root)
summary <- build_site_data(project_root, activity, inflation, speakers)

message(sprintf("Activity rows: %s", summary$activity_rows))
message(sprintf("Inflation rows: %s", summary$inflation_rows))
message(sprintf("ECB speaker rows: %s", summary$speaker_rows))
message("Done.")
