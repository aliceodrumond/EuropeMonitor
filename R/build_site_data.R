build_site_data <- function(project_root, activity, inflation, speakers) {
  public_data <- file.path(project_root, "public/data")
  dir.create(public_data, recursive = TRUE, showWarnings = FALSE)

  activity_path <- file.path(public_data, "activity_series.csv")
  inflation_path <- file.path(public_data, "inflation_series.csv")
  metadata_path <- file.path(public_data, "metadata.json")
  previous_metadata <- read_metadata_json(metadata_path)
  activity_last_new <- summarize_new_observations(activity, activity_path, previous_metadata$activity_last_new)
  inflation_last_new <- summarize_new_observations(inflation, inflation_path, previous_metadata$inflation_last_new)

  write_csv_utf8(activity, activity_path)
  write_csv_utf8(inflation, inflation_path)
  write_csv_utf8(speakers, file.path(public_data, "ecb_speakers.csv"))

  source_count <- length(unique(c(activity$source_url, inflation$source_url)))
  metadata <- list(
    last_updated = format(Sys.Date(), "%Y-%m-%d"),
    data_mode = "source_linked_mock_values",
    generated_by = "R/run_daily_update.R",
    source_links = source_count,
    activity_last_new = activity_last_new,
    inflation_last_new = inflation_last_new
  )

  write_metadata_json(metadata, metadata_path)

  invisible(list(
    activity_rows = nrow(activity),
    inflation_rows = nrow(inflation),
    speaker_rows = nrow(speakers)
  ))
}

read_metadata_json <- function(path) {
  if (!file.exists(path) || !requireNamespace("jsonlite", quietly = TRUE)) {
    return(list())
  }
  tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) list())
}

write_metadata_json <- function(metadata, path) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package jsonlite is required to write metadata.json")
  }
  jsonlite::write_json(metadata, path, auto_unbox = TRUE, pretty = TRUE)
}

summarize_new_observations <- function(current, previous_path, previous_summary = NULL) {
  empty_summary <- list(date = "", description = "No new observations in latest update")
  if (!file.exists(previous_path)) {
    return(if (is.null(previous_summary)) empty_summary else previous_summary)
  }

  previous <- tryCatch(
    utils::read.csv(previous_path, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) data.frame()
  )
  if (!nrow(previous) || !all(c("date", "series_id") %in% names(previous))) {
    return(if (is.null(previous_summary)) empty_summary else previous_summary)
  }

  current$key <- paste(current$date, current$series_id, sep = "|")
  previous$key <- paste(previous$date, previous$series_id, sep = "|")
  added <- current[!current$key %in% previous$key, , drop = FALSE]
  current$key <- NULL
  if (!nrow(added)) {
    return(if (is.null(previous_summary)) empty_summary else previous_summary)
  }

  added$date_value <- as.Date(added$date)
  latest_date <- max(added$date_value, na.rm = TRUE)
  latest <- added[added$date_value == latest_date, , drop = FALSE]
  latest <- latest[order(latest$source, latest$series_name), , drop = FALSE]
  first <- latest[1, , drop = FALSE]
  description <- sprintf(
    "%s: %s",
    first$source,
    paste(unique(latest$series_name), collapse = ", ")
  )
  list(
    date = format(latest_date, "%Y-%m-%d"),
    description = description
  )
}
