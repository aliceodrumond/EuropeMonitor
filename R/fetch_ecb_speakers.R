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
  html <- normalize_html(read_url_text(url))
  pattern <- "<h2[^>]*>\\s*<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>\\s*</h2>\\s*<p>(.*?)</p>\\s*<span[^>]*class=\"date\"[^>]*>([0-9]{1,2} [A-Za-z]+ [0-9]{4})"
  items <- regmatches(html, gregexpr(pattern, html, perl = TRUE))[[1]]

  if (!length(items) || identical(items, character(0))) {
    stop("No Econostream article cards found")
  }

  rows <- do.call(rbind, lapply(items, parse_econostream_item))
  rows <- rows[rows$is_member_speech, ]

  if (!nrow(rows)) {
    stop("No ECB member speech rows found")
  }

  rows <- rows[order(rows$member, as.Date(rows$date), decreasing = TRUE), ]
  rows$stance_change <- compare_member_stance(rows)
  rows <- rows[order(as.Date(rows$date), decreasing = TRUE), ]

  rows$is_member_speech <- NULL
  rows$stance_score <- NULL
  rownames(rows) <- NULL
  rows[seq_len(min(30, nrow(rows))), ]
}

parse_econostream_item <- function(item) {
  values <- regmatches(
    item,
    regexec(
      "<h2[^>]*>\\s*<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>\\s*</h2>\\s*<p>(.*?)</p>\\s*<span[^>]*class=\"date\"[^>]*>([0-9]{1,2} [A-Za-z]+ [0-9]{4})",
      item,
      perl = TRUE
    )
  )[[1]]

  headline <- clean_html(values[[3]])
  summary <- strip_econostream_byline(clean_html(values[[4]]))
  member <- extract_ecb_member(headline)
  profile <- member_profile(member)
  text <- paste(headline, summary)
  score <- policy_score(text)

  data.frame(
    date = format(as.Date(values[[5]], format = "%d %B %Y"), "%Y-%m-%d"),
    member = member,
    position = profile$position,
    country = profile$country,
    event_type = infer_event_type(headline, summary),
    policy_comments = extract_policy_highlight(headline, summary),
    bias = score_to_bias(score),
    stance_change = "",
    tags = infer_policy_tags(text),
    source = "Econostream Central Bank",
    source_url = absolute_econostream_url(values[[2]]),
    is_member_speech = is_ecb_member_headline(headline, member),
    stance_score = score,
    stringsAsFactors = FALSE
  )
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

normalize_html <- function(value) {
  value <- gsub("\r|\n|\t", " ", value)
  gsub("\\s+", " ", value)
}

clean_html <- function(value) {
  replacements <- c(
    "&nbsp;" = " ",
    "&amp;" = "&",
    "&aacute;" = "á",
    "&eacute;" = "é",
    "&iacute;" = "í",
    "&oacute;" = "ó",
    "&uacute;" = "ú",
    "&Aacute;" = "Á",
    "&Eacute;" = "É",
    "&Iacute;" = "Í",
    "&Oacute;" = "Ó",
    "&Uacute;" = "Ú",
    "&ccedil;" = "ç",
    "&Scaron;" = "Š",
    "&scaron;" = "š",
    "&ndash;" = "-",
    "&rsquo;" = "'",
    "&lsquo;" = "'",
    "&ldquo;" = "\"",
    "&rdquo;" = "\"",
    "&quot;" = "\"",
    "&#39;" = "'",
    "â€™" = "'",
    "â€œ" = "\"",
    "â€" = "\"",
    "â€“" = "-",
    "â€”" = "-"
  )
  value <- gsub("<[^>]+>", "", value)
  for (pattern in names(replacements)) {
    value <- gsub(pattern, replacements[[pattern]], value, fixed = TRUE)
  }
  trimws(gsub("\\s+", " ", value))
}

strip_econostream_byline <- function(value) {
  value <- sub("^By [^-]+ - [A-Z][A-Z ]+ \\(Econostream\\) -\\s*", "", value)
  value <- sub("^By [^-]+ - [A-Za-z ]+ \\(Econostream\\) -\\s*", "", value)
  trimws(value)
}

absolute_econostream_url <- function(path) {
  path <- clean_html(path)
  if (grepl("^https?://", path)) {
    return(path)
  }
  paste0("https://www.econostream-media.com", path)
}

is_ecb_member_headline <- function(headline, member) {
  grepl("^ECB", headline) &&
    !grepl("Insight|Tone Meter|Weekly Update", headline, ignore.case = TRUE) &&
    !member %in% c("Insight", "Tone Meter", "ECB")
}

extract_ecb_member <- function(headline) {
  known <- names(member_profiles())
  for (member in known) {
    if (grepl(member, headline, fixed = TRUE)) {
      return(member)
    }
  }

  name <- headline
  name <- sub("^ECB'?s\\s+", "", name)
  name <- sub("^ECB.s\\s+", "", name)
  name <- sub("^ECB\\s+", "", name)
  name <- sub(":.*$", "", name)
  name <- sub("\\s+Says.*$", "", name)
  name <- sub("\\s+Would.*$", "", name)
  name <- sub("\\s+Will.*$", "", name)
  name <- sub("\\s+Keeping.*$", "", name)
  name <- sub("\\s+Can.*$", "", name)
  name <- trimws(name)

  if (grepl("^Insight", name, ignore.case = TRUE)) return("Insight")
  if (grepl("^Tone Meter", name, ignore.case = TRUE)) return("Tone Meter")
  name
}

member_profile <- function(member) {
  profiles <- member_profiles()

  if (!is.null(profiles[[member]])) {
    return(profiles[[member]])
  }
  list(position = "ECB speaker", country = "Euro Area")
}

member_profiles <- function() {
  list(
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
    "Escrivá" = list(position = "Governing Council", country = "Spain"),
    "Šimkus" = list(position = "Governing Council", country = "Lithuania"),
    "Kaasik" = list(position = "Governing Council", country = "Estonia"),
    "Kocher" = list(position = "Governing Council", country = "Austria"),
    "Dolenc" = list(position = "Governing Council", country = "Slovenia"),
    "Wunsch" = list(position = "Governing Council", country = "Belgium"),
    "Cipollone" = list(position = "Executive Board", country = "Italy")
  )
}

infer_event_type <- function(headline, summary) {
  text <- tolower(paste(headline, summary))
  if (grepl("interview", text)) return("Interview")
  if (grepl("press conference", text)) return("Press conference")
  if (grepl("speech|said", text)) return("Speech")
  "Article"
}

extract_policy_highlight <- function(headline, summary) {
  claim <- sub("^ECB'?s\\s+[^:]+:\\s*", "", headline)
  claim <- sub("^ECB.s\\s+[^:]+:\\s*", "", claim)
  claim <- if (identical(claim, headline)) "" else claim
  summary_sentence <- sub("(?<=[.!?])\\s+.*$", "", summary, perl = TRUE)
  highlight <- trimws(paste(claim, summary_sentence))
  shorten_text(highlight, 170)
}

shorten_text <- function(value, max_chars) {
  value <- trimws(value)
  if (nchar(value) <= max_chars) {
    return(value)
  }
  paste0(trimws(substr(value, 1, max_chars - 3)), "...")
}

policy_score <- function(text) {
  text <- tolower(text)
  hawkish <- c("rate hike", "hike", "inflation pressures", "restrictive", "not finished", "further rate", "upside", "wages", "deterioration in the inflation outlook", "high inflation")
  dovish <- c("hold", "holding rates", "no commitment", "gradual", "no forward guidance", "wait", "pause", "no roadmap", "refraining from signaling", "unchanged")

  hawkish_score <- sum(vapply(hawkish, grepl, logical(1), x = text, fixed = TRUE))
  dovish_score <- sum(vapply(dovish, grepl, logical(1), x = text, fixed = TRUE))
  hawkish_score - dovish_score
}

score_to_bias <- function(score) {
  if (score > 0) return("hawkish")
  if (score < 0) return("dovish")
  "neutral"
}

compare_member_stance <- function(rows) {
  result <- rep("First recent item", nrow(rows))

  for (member in unique(rows$member)) {
    idx <- which(rows$member == member)
    if (length(idx) < 2) {
      next
    }
    for (pos in seq_len(length(idx) - 1)) {
      current <- rows$stance_score[idx[[pos]]]
      previous <- rows$stance_score[idx[[pos + 1]]]
      delta <- current - previous
      result[idx[[pos]]] <- if (delta > 0) {
        "More hawkish than prior"
      } else if (delta < 0) {
        "Less hawkish than prior"
      } else {
        "Similar to prior"
      }
    }
  }

  result
}

infer_policy_tags <- function(text) {
  text <- tolower(text)
  tags <- character(0)
  if (grepl("rate|hike|interest|hold", text)) tags <- c(tags, "rates")
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
    policy_comments = "Econostream could not be reached; rerun R/run_daily_update.R to refresh.",
    bias = "neutral",
    stance_change = "Not available",
    tags = "fallback",
    source = "Fallback",
    source_url = econostream_central_bank_url,
    stringsAsFactors = FALSE
  )
}
