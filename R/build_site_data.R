build_site_data <- function(project_root, activity, inflation, speakers) {
  public_data <- file.path(project_root, "public/data")
  dir.create(public_data, recursive = TRUE, showWarnings = FALSE)

  write_csv_utf8(activity, file.path(public_data, "activity_series.csv"))
  write_csv_utf8(inflation, file.path(public_data, "inflation_series.csv"))
  write_csv_utf8(speakers, file.path(public_data, "ecb_speakers.csv"))

  source_count <- length(unique(c(activity$source_url, inflation$source_url)))
  metadata <- c(
    "{",
    sprintf('  "last_updated": "%s",', format(Sys.Date(), "%Y-%m-%d")),
    '  "data_mode": "source_linked_mock_values",',
    '  "generated_by": "R/run_daily_update.R",',
    sprintf('  "source_links": %s', source_count),
    "}"
  )

  writeLines(metadata, file.path(public_data, "metadata.json"), useBytes = TRUE)

  invisible(list(
    activity_rows = nrow(activity),
    inflation_rows = nrow(inflation),
    speaker_rows = nrow(speakers)
  ))
}
