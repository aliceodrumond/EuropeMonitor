econostream_central_bank_url <- "https://www.econostream-media.com/news/topic/centralbank"

build_ecb_speakers <- function(project_root) {
  speakers <- tryCatch(
    fetch_econostream_ecb_speakers(econostream_central_bank_url),
    error = function(error) {
      warning(sprintf("Econostream fetch failed: %s. Using fallback ECB speaker table.", error$message))
      fallback_ecb_speakers()
    }
  )

  write_csv_utf8(speakers, file.path(project_root, "data/processed/ecb_speakers.csv"))
  speakers
}

fetch_econostream_ecb_speakers <- function(url) {
  page <- read_url_text(url)
  html <- normalize_html(page)

  pattern <- "<h2[^>]*>\\s*<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>\\s*</h2>\\s*<p>(.*?)</p>\\s*<span[^>]*class=\"date\"[^>]*>([0-9]{1,2} [A-Za-z]+ [0-9]{4})"
  matches <- gregexpr(pattern, html, perl = TRUE)
  items <- regmatches(html, matches)[[1]]

  if (!length(items) || identical(items, character(0))) {
    stop("No Econostream article cards found")
  }

  rows <- lapply(items, parse_econostream_item)
  speakers <- do.call(rbind, rows)
  speakers <- speakers[grepl("^ECB", speakers$headline), ]

  if (!nrow(speakers)) {
    stop("No ECB speaker rows found")
  }

  speakers[seq_len(min(30, nrow(speakers))), ]
}

read_url_text <- function(url) {
  native <- tryCatch(
    paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(error) NULL
  )

  if (!is.null(native) && nzchar(native)) {
    return(native)
  }

  script <- sprintf(
    "$ProgressPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new(); (Invoke-WebRequest -Uri '%s' -UseBasicParsing).Content",
    url
  )
  output <- tryCatch(
    system2("powershell", c("-NoProfile", "-Command", script), stdout = TRUE, stderr = TRUE),
    error = function(error) NULL
  )

  if (is.null(output) || !length(output)) {
    stop(sprintf("Could not download %s", url))
  }

  paste(output, collapse = "\n")
}

parse_econostream_item <- function(item) {
  parts <- regexec(
    "<h2[^>]*>\\s*<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>\\s*</h2>\\s*<p>(.*?)</p>\\s*<span[^>]*class=\"date\"[^>]*>([0-9]{1,2} [A-Za-z]+ [0-9]{4})",
    item,
    perl = TRUE
  )
  values <- regmatches(item, parts)[[1]]

  link <- absolute_econostream_url(values[[2]])
  headline <- clean_html(values[[3]])
  summary <- clean_html(values[[4]])
  date <- as.Date(values[[5]], format = "%d %B %Y")
  member <- extract_ecb_member(headline)
  profile <- member_profile(member)
  combined_text <- paste(headline, summary)

  data.frame(
    date = format(date, "%Y-%m-%d"),
    member = member,
    position = profile$position,
    country = profile$country,
    event_type = infer_event_type(headline, summary),
    headline = headline,
    policy_comments = summary,
    bias = infer_policy_bias(combined_text),
    tags = infer_policy_tags(combined_text),
    source = "Econostream Central Bank",
    source_url = link,
    stringsAsFactors = FALSE
  )
}

normalize_html <- function(value) {
  value <- gsub("\r|\n|\t", " ", value)
  gsub("\\s+", " ", value)
}

clean_html <- function(value) {
  value <- gsub("<[^>]+>", "", value)
  value <- gsub("&nbsp;", " ", value, fixed = TRUE)
  value <- gsub("â€™", "'", value, fixed = TRUE)
  value <- gsub("â€œ", "\"", value, fixed = TRUE)
  value <- gsub("â€", "\"", value, fixed = TRUE)
  value <- gsub("â€“", "-", value, fixed = TRUE)
  value <- gsub("â€”", "-", value, fixed = TRUE)
  value <- gsub("&amp;", "&", value, fixed = TRUE)
  value <- gsub("&ndash;", "-", value, fixed = TRUE)
  value <- gsub("&rsquo;", "'", value, fixed = TRUE)
  value <- gsub("&lsquo;", "'", value, fixed = TRUE)
  value <- gsub("&ldquo;", "\"", value, fixed = TRUE)
  value <- gsub("&rdquo;", "\"", value, fixed = TRUE)
  value <- gsub("&quot;", "\"", value, fixed = TRUE)
  value <- gsub("&#39;", "'", value, fixed = TRUE)
  trimws(gsub("\\s+", " ", value))
}

absolute_econostream_url <- function(path) {
  path <- gsub("â€™", "'", path, fixed = TRUE)
  if (grepl("^https?://", path)) {
    return(path)
  }
  paste0("https://www.econostream-media.com", path)
}

extract_ecb_member <- function(headline) {
  headline <- sub("^ECB.s\\s+", "", headline)
  headline <- sub("^ECB\\s+", "", headline)
  name <- sub(":.*$", "", headline)
  name <- sub("\\s+Says.*$", "", name)
  name <- sub("\\s+Would.*$", "", name)
  name <- sub("\\s+Will.*$", "", name)
  name <- sub("\\s+Keeping.*$", "", name)
  name <- sub("\\s+Can.*$", "", name)
  name <- trimws(name)

  if (grepl("^Insight", name, ignore.case = TRUE)) {
    return("Insight")
  }
  if (grepl("^Tone Meter", name, ignore.case = TRUE)) {
    return("Tone Meter")
  }
  name
}

member_profile <- function(member) {
  profiles <- list(
    "Lagarde" = list(position = "President", country = "ECB"),
    "Lane" = list(position = "Chief Economist", country = "Ireland"),
    "Schnabel" = list(position = "Executive Board", country = "Germany"),
    "Elderson" = list(position = "Executive Board", country = "Netherlands"),
    "De Guindos" = list(position = "Vice-President", country = "Spain"),
    "Kazaks" = list(position = "Governing Council", country = "Latvia"),
    "Kazāks" = list(position = "Governing Council", country = "Latvia"),
    "Kažimír" = list(position = "Governing Council", country = "Slovakia"),
    "Nagel" = list(position = "Governing Council", country = "Germany"),
    "Sleijpen" = list(position = "Governing Council", country = "Netherlands"),
    "Stournaras" = list(position = "Governing Council", country = "Greece"),
    "Moulin" = list(position = "Treasury / ECB context", country = "France"),
    "Rehn" = list(position = "Governing Council", country = "Finland"),
    "Makhlouf" = list(position = "Governing Council", country = "Ireland"),
    "Kaasik" = list(position = "Governing Council", country = "Estonia"),
    "Kocher" = list(position = "Governing Council", country = "Austria"),
    "Dolenc" = list(position = "Governing Council", country = "Slovenia"),
    "Wunsch" = list(position = "Governing Council", country = "Belgium"),
    "Cipollone" = list(position = "Executive Board", country = "Italy"),
    "Insight" = list(position = "Analysis", country = "ECB"),
    "Tone Meter" = list(position = "Analysis", country = "ECB")
  )

  if (!is.null(profiles[[member]])) {
    return(profiles[[member]])
  }
  list(position = "ECB speaker", country = "Euro Area")
}

infer_event_type <- function(headline, summary) {
  text <- tolower(paste(headline, summary))
  if (grepl("press conference", text)) return("Press conference")
  if (grepl("interview", text)) return("Interview")
  if (grepl("insight|tone meter|weekly update", text)) return("Analysis")
  if (grepl("said|speech", text)) return("Speech")
  "Article"
}

infer_policy_bias <- function(text) {
  text <- tolower(text)
  hawkish <- c("rate hike", "hike", "more work", "inflation pressures", "restrictive", "not finished", "not complete", "further rate", "second-round", "wages", "upside", "necessary")
  dovish <- c("no commitment", "gradual", "no forward guidance", "wait", "pause", "less hawkish", "no roadmap", "monitor developments")

  hawkish_score <- sum(vapply(hawkish, grepl, logical(1), x = text, fixed = TRUE))
  dovish_score <- sum(vapply(dovish, grepl, logical(1), x = text, fixed = TRUE))

  if (hawkish_score > dovish_score) return("hawkish")
  if (dovish_score > hawkish_score) return("dovish")
  "neutral"
}

infer_policy_tags <- function(text) {
  text <- tolower(text)
  tags <- character(0)
  if (grepl("rate|hike|interest", text)) tags <- c(tags, "rates")
  if (grepl("inflation|price", text)) tags <- c(tags, "inflation")
  if (grepl("wage|second-round", text)) tags <- c(tags, "wages")
  if (grepl("energy|oil|middle east", text)) tags <- c(tags, "energy")
  if (grepl("digital euro|payments", text)) tags <- c(tags, "digital-euro")
  if (grepl("guidance|roadmap|commitment", text)) tags <- c(tags, "guidance")
  if (!length(tags)) tags <- "general"
  paste(unique(tags), collapse = ",")
}

fallback_ecb_speakers <- function() {
  data.frame(
    date = "2026-06-15",
    member = "Lagarde",
    position = "President",
    country = "ECB",
    event_type = "Speech",
    headline = "ECB speaker data unavailable",
    policy_comments = "Econostream could not be reached; rerun R/run_daily_update.R to refresh.",
    bias = "neutral",
    tags = "fallback",
    source = "Fallback",
    source_url = econostream_central_bank_url,
    stringsAsFactors = FALSE
  )
}
