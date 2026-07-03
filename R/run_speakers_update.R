args <- commandArgs(trailingOnly = FALSE)
file_arg <- args[grepl("^--file=", args)]

if (length(file_arg) > 0) {
  script_path <- normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = TRUE)
  project_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
} else {
  project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

source(file.path(project_root, "R/helpers.R"), local = TRUE)
source(file.path(project_root, "R/fetch_ecb_speakers.R"), local = TRUE)
source(file.path(project_root, "R/build_site_data.R"), local = TRUE)

ensure_project_dirs(project_root)

message("Building Europe ECB speakers data...")
speakers <- build_ecb_speakers(project_root)

public_data <- file.path(project_root, "public/data")
dir.create(public_data, recursive = TRUE, showWarnings = FALSE)
write_csv_utf8(speakers, file.path(public_data, "ecb_speakers.csv"))

metadata_path <- file.path(public_data, "metadata.json")
metadata <- read_metadata_json(metadata_path)
metadata$last_updated <- format(Sys.Date(), "%Y-%m-%d")
metadata$data_mode <- "source_linked_mock_values"
metadata$generated_by <- "R/run_speakers_update.R"
metadata$speaker_rows <- nrow(speakers)
write_metadata_json(metadata, metadata_path)

message(sprintf("ECB speaker rows: %s", nrow(speakers)))
message("Done.")
