econostream_central_bank_url <- "https://www.econostream-media.com/news/topic/centralbank"

build_ecb_speakers <- function(project_root) {
  processed_path <- file.path(project_root, "data/processed/ecb_speakers.csv")
  previous <- read_speaker_csv(processed_path)
  speakers <- tryCatch(
    normalize_speaker_columns(fetch_econostream_ecb_speakers(econostream_central_bank_url)),
    error = function(error) {
      has_valid_previous <- !is.null(previous) && nrow(previous) > 0 &&
        !any(previous$tags == "fallback", na.rm = TRUE)

      if (has_valid_previous) {
        warning(sprintf("Econostream fetch failed: %s. Keeping last valid speaker table.", error$message))
        previous
      } else {
        warning(sprintf("Econostream fetch failed: %s. Using fallback ECB speaker table.", error$message))
        fallback_ecb_speakers()
      }
    }
  )

  speakers <- normalize_speaker_columns(speakers)
  speakers <- keep_recent_and_priority_speeches(speakers, previous, max_rows = 20)
  speakers <- apply_speaker_highlight_overrides(speakers)
  speakers <- apply_current_view_tone_calibration(speakers, previous)
  write_csv_utf8(speakers, processed_path)
  speakers
}

read_speaker_csv <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }
  size <- file.info(path)$size
  if (is.na(size) || size <= 0) {
    return(NULL)
  }
  bytes <- readBin(path, "raw", size)
  text <- rawToChar(bytes)
  text <- iconv(text, from = "UTF-8", to = "ASCII//TRANSLIT", sub = "")
  text <- sub("^\ufeff", "", text)
  if (!grepl("\n$", text)) {
    text <- paste0(text, "\n")
  }
  temp_path <- tempfile(fileext = ".csv")
  writeLines(text, temp_path, useBytes = TRUE)
  on.exit(unlink(temp_path), add = TRUE)
  result <- tryCatch(
    normalize_speaker_columns(read.csv(temp_path, stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8")),
    error = function(...) NULL
  )
  if (!is.null(result) && nrow(result) > 0 && "date" %in% names(result)) {
    return(result)
  }
  NULL
}

normalize_speaker_columns <- function(speakers) {
  if (is.null(speakers) || !is.data.frame(speakers)) {
    return(speakers)
  }
  names(speakers) <- sub("^\\ufeff", "", names(speakers))
  names(speakers) <- sub("^ÃƒÂ¯\\.\\.date$", "date", names(speakers))
  names(speakers) <- sub("^ÃƒÂ¯..date$", "date", names(speakers))
  if ("source_url" %in% names(speakers)) {
    speakers$source_url <- clean_speaker_url(speakers$source_url)
  }
  if ("policy_comments" %in% names(speakers)) {
    speakers$policy_comments <- clean_speaker_text(speakers$policy_comments)
  }
  if (!"tone_calibration" %in% names(speakers)) {
    speakers$tone_calibration <- ""
  }
  speakers$tone_calibration[is.na(speakers$tone_calibration)] <- ""
  speakers
}

clean_speaker_text <- function(value) {
  value <- gsub("<U\\+[0-9A-Fa-f]+>", "", value)
  value <- gsub("\\s+", " ", value)
  trimws(value)
}

clean_speaker_url <- function(value) {
  value <- gsub("<U\\+[0-9A-Fa-f]+>", "", value)
  value <- iconv(value, from = "", to = "ASCII//TRANSLIT", sub = "")
  value <- gsub("[\"'`]", "", value)
  trimws(value)
}

keep_recent_and_priority_speeches <- function(speakers, previous, max_rows = 20) {
  priority_members <- c("Lagarde", "Lane", "Schnabel", "Nagel")
  if (is.null(previous) || !nrow(previous) || any(previous$tags == "fallback", na.rm = TRUE)) {
    return(head(order_speaker_rows(speakers), max_rows))
  }

  common_columns <- intersect(names(speakers), names(previous))
  if (!"date" %in% common_columns) {
    warning("Previous ECB speaker table had no usable date column; keeping fetched rows only.")
    return(head(order_speaker_rows(speakers), max_rows))
  }
  combined <- rbind(
    speakers[, common_columns, drop = FALSE],
    previous[, common_columns, drop = FALSE]
  )
  combined <- dedupe_speaker_rows(combined)
  combined$date_value <- as.Date(combined$date)

  priority_latest <- do.call(rbind, lapply(priority_members, function(member) {
    rows <- combined[combined$member == member, , drop = FALSE]
    if (!nrow(rows)) return(NULL)
    rows <- rows[order(-as.numeric(rows$date_value)), , drop = FALSE]
    rows[1, , drop = FALSE]
  }))

  base_rows <- head(order_speaker_rows(combined[, common_columns, drop = FALSE]), max_rows)
  if (is.null(priority_latest) || !nrow(priority_latest)) {
    return(order_speaker_rows(base_rows))
  }

  required <- rbind(base_rows, priority_latest[, common_columns, drop = FALSE])
  required <- dedupe_speaker_rows(required)
  head(order_speaker_rows(required), max_rows)
}

dedupe_speaker_rows <- function(speakers) {
  if (!nrow(speakers)) return(speakers)
  speakers$member <- vapply(speakers$member, normalize_ecb_member_name_ascii, character(1))
  comments <- tolower(trimws(gsub("\\s+", " ", speakers$policy_comments)))
  if ("source_url" %in% names(speakers)) {
    url_key <- tolower(gsub("[^a-z0-9]+", "", speakers$source_url))
    key <- ifelse(
      nzchar(url_key),
      paste(speakers$member, speakers$date, url_key, sep = "|"),
      paste(speakers$member, speakers$date, comments, sep = "|")
    )
  } else {
    key <- paste(speakers$member, speakers$date, comments, sep = "|")
  }
  speakers[!duplicated(key), , drop = FALSE]
}

order_speaker_rows <- function(speakers) {
  if (!nrow(speakers)) return(speakers)
  speakers$date_value <- as.Date(speakers$date)
  speakers <- speakers[order(-as.numeric(speakers$date_value), speakers$member), , drop = FALSE]
  speakers$date_value <- NULL
  rownames(speakers) <- NULL
  speakers
}

apply_speaker_highlight_overrides <- function(speakers) {
  escriva_chain_transmission <- paste(
    "In other words, price increases are being transmitted throughout production chains and goods markets.",
    "We are seeing this, for example, in transportation services and in food production sectors that use plastics or energy as inputs."
  )

  idx <- speakers$member == "Escriva" &
    speakers$date == "2026-06-23" &
    grepl("diplomatic_resolution_scenario", speakers$source_url, fixed = TRUE)

  speakers$policy_comments[idx] <- escriva_chain_transmission

  idx <- speakers$member == "Lagarde" &
    speakers$date == "2026-06-29" &
    grepl("june_hike_was_not_an_insurance_move", speakers$source_url, fixed = TRUE)

  speakers$policy_comments[idx] <- "The June hike was not an insurance move and was robust across scenarios."

  idx <- speakers$member == "Lagarde" &
    speakers$date == "2026-07-03" &
    grepl("general_sense_of_the_direction_we_will_take", speakers$source_url, fixed = TRUE)

  speakers$policy_comments[idx] <- paste(
    "She did not know whether more tightening was coming, but had a general sense of the direction policy would take.",
    "She was confident the June hike was the right choice, with a large majority already prepared to tighten in April.",
    "Underlying inflation continued to accelerate and second-round effects were being watched closely.",
    sep = " | "
  )
  speakers$bias[idx] <- "mildly hawkish"
  speakers$tags[idx] <- "rates,inflation,growth"

  idx <- speakers$member == "Schnabel" &
    speakers$date == "2026-06-27" &
    grepl("further_rate_hikes_upside_inflation_risks", speakers$source_url, fixed = TRUE)

  speakers$policy_comments[idx] <- "Further rate hikes were flagged, alongside upside inflation risks."

  idx <- speakers$member == "Moulin" &
    speakers$date == "2026-07-03" &
    grepl("balance_of_risk_is_in_the_right_place", speakers$source_url, fixed = TRUE)

  speakers$policy_comments[idx] <- paste(
    "We are in a good position and the balance of risks is in the right place.",
    "We were not entering into a new cycle of hikes.",
    "We made no commitment for the next meetings.",
    sep = " | "
  )
  speakers$bias[idx] <- "mildly dovish"
  speakers$tags[idx] <- "rates,inflation,energy"
  speakers
}

apply_current_view_tone_calibration <- function(speakers, previous = NULL) {
  if (is.null(speakers) || !nrow(speakers)) return(speakers)

  speakers <- mark_current_view_calibration_rows(speakers, previous)

  for (i in seq_len(nrow(speakers))) {
    comment <- speakers$policy_comments[[i]]
    if (identical(comment, "No comments relevant for monetary policy")) {
      speakers$bias[[i]] <- "neutral"
      next
    }

    text <- paste(comment, speakers$tags[[i]], speakers$source_url[[i]])
    score <- speaker_policy_score(
      speakers$member[[i]],
      text,
      use_current_view_prior = identical(speakers$tone_calibration[[i]], current_view_calibration_marker())
    )
    speakers$bias[[i]] <- score_to_bias(score)
  }

  speakers <- speakers[order(speakers$member, as.Date(speakers$date), decreasing = TRUE), ]
  speakers$stance_change <- compare_member_stance(speakers)
  speakers <- speakers[order(-as.numeric(as.Date(speakers$date)), speakers$member), ]
  rownames(speakers) <- NULL
  speakers
}

mark_current_view_calibration_rows <- function(speakers, previous = NULL) {
  marker <- current_view_calibration_marker()
  if (!"tone_calibration" %in% names(speakers)) {
    speakers$tone_calibration <- ""
  }
  speakers$tone_calibration[is.na(speakers$tone_calibration)] <- ""

  has_previous <- !is.null(previous) && nrow(previous) > 0 &&
    !any(previous$tags == "fallback", na.rm = TRUE)
  if (!has_previous) {
    return(speakers)
  }

  previous <- normalize_speaker_columns(previous)
  previous_keys <- speaker_row_keys(previous)
  current_keys <- speaker_row_keys(speakers)
  newly_seen <- !(current_keys %in% previous_keys)
  already_consumed <- unique(previous$member[previous$tone_calibration == marker])

  for (member in setdiff(unique(speakers$member), already_consumed)) {
    if (current_ecb_member_tone_prior(member) == 0) {
      next
    }
    idx <- which(speakers$member == member & newly_seen)
    if (!length(idx)) {
      next
    }
    dates <- as.Date(speakers$date[idx])
    idx <- idx[order(as.numeric(dates), idx)]
    speakers$tone_calibration[idx[[1]]] <- marker
  }

  speakers
}

speaker_row_keys <- function(speakers) {
  if (is.null(speakers) || !nrow(speakers)) return(character(0))
  member <- vapply(speakers$member, normalize_ecb_member_name_ascii, character(1))
  comments <- tolower(trimws(gsub("\\s+", " ", speakers$policy_comments)))
  if ("source_url" %in% names(speakers)) {
    url_key <- tolower(gsub("[^a-z0-9]+", "", speakers$source_url))
    return(ifelse(
      nzchar(url_key),
      paste(member, speakers$date, url_key, sep = "|"),
      paste(member, speakers$date, comments, sep = "|")
    ))
  }
  paste(member, speakers$date, comments, sep = "|")
}

fetch_econostream_ecb_speakers <- function(url) {
  html <- normalize_html(read_url_text(url))
  pattern <- "<h2[^>]*>\\s*<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>\\s*</h2>\\s*<p>(.*?)</p>\\s*<span[^>]*class=\"date\"[^>]*>([0-9]{1,2} [A-Za-z]+ [0-9]{4})"
  items <- regmatches(html, gregexpr(pattern, html, perl = TRUE))[[1]]

  if (!length(items) || identical(items, character(0))) {
    stop("No Econostream article cards found")
  }

  rows <- do.call(rbind, lapply(items, parse_econostream_item))
  rows$source_order <- seq_len(nrow(rows))
  rows <- rows[rows$is_member_speech, ]

  if (!nrow(rows)) {
    stop("No ECB member speech rows found")
  }

  rows <- rows[order(rows$member, as.Date(rows$date), decreasing = TRUE), ]
  rows$stance_change <- compare_member_stance(rows)
  rows <- rows[order(-as.numeric(as.Date(rows$date)), rows$source_order), ]

  rows$is_member_speech <- NULL
  rows$stance_score <- NULL
  rows$source_order <- NULL
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
  member <- normalize_ecb_member_name(member)
  member <- normalize_ecb_member_name_ascii(member)
  profile <- member_profile(member)
  text <- paste(headline, summary)
  score <- speaker_policy_score(member, text, use_current_view_prior = FALSE)

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
    tone_calibration = "",
    is_member_speech = is_ecb_member_headline(headline, member),
    stance_score = score,
    stringsAsFactors = FALSE
  )
}

read_url_text <- function(url, timeout_seconds = 45) {
  tmp <- tempfile(fileext = ".html")
  script <- sprintf(
    "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -TimeoutSec %s -Uri %s -OutFile %s",
    as.character(timeout_seconds),
    shQuote(url, type = "sh"),
    shQuote(normalizePath(tmp, winslash = "\\", mustWork = FALSE), type = "sh")
  )
  tryCatch(system2("powershell", c("-NoProfile", "-Command", script), stdout = FALSE, stderr = FALSE), error = function(error) NULL)

  if (file.exists(tmp) && file.info(tmp)$size > 0) {
    value <- paste(readLines(tmp, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    if (nzchar(value)) {
      return(value)
    }
  }

  native <- tryCatch(
    paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(error) NULL
  )

  if (!is.null(native) && nzchar(native)) {
    return(native)
  }

  stop(sprintf("Could not download %s", url))
}

normalize_html <- function(value) {
  value <- gsub("<U\\+0101>", "a", value, fixed = TRUE)
  value <- gsub("<U\\+0107>", "c", value, fixed = TRUE)
  value <- gsub("<U\\+010D>", "c", value, fixed = TRUE)
  value <- gsub("<U\\+0146>", "n", value, fixed = TRUE)
  value <- gsub("<U\\+0161>", "s", value, fixed = TRUE)
  value <- gsub("<U\\+017D>", "Z", value, fixed = TRUE)
  value <- gsub("<U\\+017E>", "z", value, fixed = TRUE)
  value <- gsub("<U\\+2019>", "'", value, fixed = TRUE)
  value <- gsub("<U\\+201C>", "\"", value, fixed = TRUE)
  value <- gsub("<U\\+201D>", "\"", value, fixed = TRUE)
  value <- gsub("\r|\n|\t", " ", value)
  gsub("\\s+", " ", value)
}

clean_html <- function(value) {
  replacements <- c(
    "&nbsp;" = " ",
    "&amp;" = "&",
    "&aacute;" = "ÃƒÆ’Ã‚Â¡",
    "&eacute;" = "ÃƒÆ’Ã‚Â©",
    "&iacute;" = "ÃƒÆ’Ã‚Â­",
    "&oacute;" = "ÃƒÆ’Ã‚Â³",
    "&uacute;" = "ÃƒÆ’Ã‚Âº",
    "&Aacute;" = "ÃƒÆ’Ã‚Â",
    "&Eacute;" = "ÃƒÆ’Ã¢â‚¬Â°",
    "&Iacute;" = "ÃƒÆ’Ã‚Â",
    "&Oacute;" = "ÃƒÆ’Ã¢â‚¬Å“",
    "&Uacute;" = "ÃƒÆ’Ã…Â¡",
    "&ccedil;" = "ÃƒÆ’Ã‚Â§",
    "&Scaron;" = "Ãƒâ€¦Ã‚Â ",
    "&scaron;" = "Ãƒâ€¦Ã‚Â¡",
    "&ndash;" = "-",
    "&rsquo;" = "'",
    "&lsquo;" = "'",
    "&ldquo;" = "\"",
    "&rdquo;" = "\"",
    "&quot;" = "\"",
    "&#39;" = "'",
    "ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢" = "'",
    "ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“" = "\"",
    "ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â" = "\"",
    "ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ" = "-",
    "ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â" = "-"
  )
  value <- gsub("<[^>]+>", "", value)
  for (pattern in names(replacements)) {
    value <- gsub(pattern, replacements[[pattern]], value, fixed = TRUE)
  }
  trimws(gsub("\\s+", " ", value))
}

strip_econostream_byline <- function(value) {
  value <- sub("^By [^-]+ - [A-Za-z ,]+ \\(Econostream\\) -\\s*", "", value)
  value <- sub("^By [^-]+ - [A-Za-z ,]+ -\\s*", "", value)
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

normalize_ecb_member_name <- function(member) {
  if (grepl("Kazaks", member, ignore.case = TRUE)) return("Kazaks")
  if (grepl("Vuj", member, fixed = TRUE)) return("Vujcic")
  if (grepl("Kaz", member, fixed = TRUE) || grepl("im", member, fixed = TRUE)) {
    if (grepl("mir|mÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­r|mÃƒÆ’Ã‚Â­r", member, ignore.case = TRUE)) return("Kazimir")
    return("Kazaks")
  }
  if (grepl("Escriv", member, fixed = TRUE)) return("Escriva")
  if (grepl("igman", member, ignore.case = TRUE)) return("Zigman")
  member
}

member_profile <- function(member) {
  profiles <- member_profiles()

  if (!is.null(profiles[[member]])) {
    return(profiles[[member]])
  }
  list(position = "ECB speaker", country = "Euro Area")
}

normalize_ecb_member_name_ascii <- function(member) {
  member <- iconv(member, from = "", to = "ASCII//TRANSLIT", sub = "")
  if (grepl("Kazaks", member, ignore.case = TRUE)) return("Kazaks")
  if (grepl("Vuj", member, fixed = TRUE)) return("Vujcic")
  if (grepl("Kazimir|Kaimr", member, ignore.case = TRUE) || grepl("im", member, fixed = TRUE)) return("Kazimir")
  if (grepl("Kaz", member, fixed = TRUE)) return("Kazaks")
  if (grepl("Escriv", member, fixed = TRUE)) return("Escriva")
  if (grepl("igman", member, ignore.case = TRUE)) return("Zigman")
  member
}

member_profiles <- function() {
  list(
    "Vujcic" = list(position = "Vice-President", country = "Croatia"),
    "Kazimir" = list(position = "Governing Council", country = "Slovakia"),
    "Escriva" = list(position = "Governing Council", country = "Spain"),
    "Lagarde" = list(position = "President", country = "ECB"),
    "Lane" = list(position = "Chief Economist", country = "Ireland"),
    "Schnabel" = list(position = "Executive Board", country = "Germany"),
    "Elderson" = list(position = "Executive Board", country = "Netherlands"),
    "De Guindos" = list(position = "Vice-President", country = "Spain"),
    "Kazaks" = list(position = "Governing Council", country = "Latvia"),
    "KazÃƒâ€žÃ‚Âks" = list(position = "Governing Council", country = "Latvia"),
    "KaÃƒâ€¦Ã‚Â¾imÃƒÆ’Ã‚Â­r" = list(position = "Governing Council", country = "Slovakia"),
    "Nagel" = list(position = "Governing Council", country = "Germany"),
    "Sleijpen" = list(position = "Governing Council", country = "Netherlands"),
    "Stournaras" = list(position = "Governing Council", country = "Greece"),
    "Moulin" = list(position = "Treasury / ECB context", country = "France"),
    "Rehn" = list(position = "Governing Council", country = "Finland"),
    "Makhlouf" = list(position = "Governing Council", country = "Ireland"),
    "EscrivÃƒÆ’Ã‚Â¡" = list(position = "Governing Council", country = "Spain"),
    "Ãƒâ€¦Ã‚Â imkus" = list(position = "Governing Council", country = "Lithuania"),
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
  summary_text <- clean_policy_comment_text(summary)
  candidates <- split_policy_sentences(summary_text)
  candidates <- candidates[nchar(candidates) >= 18]
  candidates <- candidates[!is_boilerplate_policy_comment(candidates)]
  candidates <- unique(candidates)

  if (!length(candidates)) {
    fallback <- clean_policy_comment_text(extract_headline_claim(headline))
    fallback_candidates <- split_policy_sentences(fallback)
    fallback_candidates <- fallback_candidates[nchar(fallback_candidates) >= 18]
    fallback_candidates <- fallback_candidates[!is_boilerplate_policy_comment(fallback_candidates)]
    fallback_scores <- vapply(fallback_candidates, policy_comment_score, numeric(1))
    if (length(fallback_scores) && any(fallback_scores > 0)) {
      return(shorten_text(fallback_candidates[order(fallback_scores, decreasing = TRUE)[[1]]], 150))
    }
    return("No comments relevant for monetary policy")
  }

  scores <- vapply(candidates, policy_comment_score, numeric(1))
  keep <- scores > 0
  if (!any(keep)) {
    fallback <- clean_policy_comment_text(extract_headline_claim(headline))
    fallback_candidates <- split_policy_sentences(fallback)
    fallback_candidates <- fallback_candidates[nchar(fallback_candidates) >= 18]
    fallback_candidates <- fallback_candidates[!is_boilerplate_policy_comment(fallback_candidates)]
    fallback_scores <- vapply(fallback_candidates, policy_comment_score, numeric(1))
    if (length(fallback_scores) && any(fallback_scores > 0)) {
      return(shorten_text(fallback_candidates[order(fallback_scores, decreasing = TRUE)[[1]]], 150))
    }
    return("No comments relevant for monetary policy")
  }

  ranked <- order(scores, decreasing = TRUE)
  selected <- character(0)
  for (sentence in candidates[ranked]) {
    sentence <- shorten_text(sentence, 150)
    if (!sentence %in% selected) {
      selected <- c(selected, sentence)
    }
    if (length(selected) >= 3) {
      break
    }
  }

  paste(selected, collapse = " | ")
}

extract_headline_claim <- function(headline) {
  claim <- sub("^ECB\\S*\\s+[^:]+:\\s*", "", headline, perl = TRUE)
  if (identical(claim, headline)) {
    claim <- sub("^ECB\\S*\\s+\\S+\\s+", "", headline, perl = TRUE)
  }
  claim <- sub("^Presentation Flags\\s+", "", claim, ignore.case = TRUE, perl = TRUE)
  if (identical(claim, headline)) "" else claim
}

clean_policy_comment_text <- function(value) {
  value <- gsub("\\s+", " ", value)
  value <- gsub(
    "\\bEuropean Central Bank\\s+(President|Chief Economist|Executive Board member|Governing Council member|Vice-President)\\s+[^,.;:]+\\s+(said|told|argued|noted|warned)\\s+(on\\s+[A-Za-z]+\\s+)?(that\\s+)?",
    "",
    value,
    ignore.case = TRUE,
    perl = TRUE
  )
  value <- gsub(
    "\\bECB\\s+(President|Chief Economist|Executive Board member|Governing Council member|Vice-President)\\s+[^,.;:]+\\s+(said|told|argued|noted|warned)\\s+(on\\s+[A-Za-z]+\\s+)?(that\\s+)?",
    "",
    value,
    ignore.case = TRUE,
    perl = TRUE
  )
  value <- gsub("\\b[A-Z][a-z]+\\s+said\\s+(on\\s+[A-Za-z]+\\s+)?(that\\s+)?", "", value, perl = TRUE)
  value <- gsub("\\bEuropean Central Bank Vice President\\s+[^,.;:]+\\s+(said|told|argued|noted|warned|stressed|indicated)\\s+(on\\s+[A-Za-z]+\\s+)?(that\\s+)?", "", value, ignore.case = TRUE, perl = TRUE)
  value <- gsub("\\bBoris\\s+Vuj\\S*\\s+(said|told|argued|noted|warned|stressed|indicated)\\s+(on\\s+[A-Za-z]+\\s+)?(that\\s+)?", "", value, ignore.case = TRUE, perl = TRUE)
  value <- gsub("\\b[A-Z][A-Za-z]+\\s+[A-Z][A-Za-z]+\\s+(said|told|argued|noted|warned|stressed|indicated)\\s+(on\\s+[A-Za-z]+\\s+)?(that\\s+)?", "", value, perl = TRUE)
  trimws(value)
}

split_policy_sentences <- function(value) {
  parts <- unlist(strsplit(value, "(?<=[.!?])\\s+|\\s+;\\s+", perl = TRUE))
  parts <- trimws(parts)
  parts <- parts[nzchar(parts)]
  unique(parts)
}

is_boilerplate_policy_comment <- function(value) {
  text <- tolower(trimws(value))
  grepl(
    "^(european central bank|ecb)\\s+(president|chief economist|executive board member|governing council member|vice[- ]president)\\b",
    text,
    perl = TRUE
  ) |
    grepl(
      "^(central bank|governing council|executive board)\\s+",
      text,
      perl = TRUE
    )
}

policy_comment_score <- function(value) {
  text <- tolower(value)
  score <- 0
  guidance <- c(
    "next meeting", "june", "july", "september", "rate path", "pre-commitment",
    "pre commitment", "forward guidance", "roadmap", "hold", "hike", "cut",
    "pause", "forceful response", "not yet warranted", "data-dependent",
    "data dependent", "no commitment", "no pre-commitment"
  )
  inflation <- c(
    "inflation", "price", "wage", "second-round", "second round", "persistent",
    "embedded", "upside", "downside", "baseline", "scenario", "risk",
    "energy", "oil", "goods", "services", "production chains", "inputs"
  )
  monetary_policy <- c(
    "monetary policy", "interest rate", "rates", "restrictive", "neutral rate",
    "policy", "transmission"
  )

  score <- score + 4 * sum(vapply(guidance, grepl, logical(1), x = text, fixed = TRUE))
  score <- score + 3 * sum(vapply(inflation, grepl, logical(1), x = text, fixed = TRUE))
  score <- score + 2 * sum(vapply(monetary_policy, grepl, logical(1), x = text, fixed = TRUE))

  if (grepl("digital euro|cyber|sovereignty|architecture|banks|payments", text)) {
    score <- score - 8
  }
  score
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
  hawkish <- c(
    "rate hike", "hike", "inflation pressures", "restrictive", "wages", "high inflation",
    "more hikes", "not finished", "upside inflation", "second-round effects are emerging",
    "still have work to do", "not completely contained"
  )
  dovish <- c(
    "hold", "holding rates", "no commitment", "gradual", "no forward guidance", "wait",
    "pause", "no roadmap", "refraining from signaling", "unchanged", "no new cycle",
    "not rush", "no urgency", "stay where we are", "no signs of critical second-round"
  )

  hawkish_score <- sum(vapply(hawkish, grepl, logical(1), x = text, fixed = TRUE))
  dovish_score <- sum(vapply(dovish, grepl, logical(1), x = text, fixed = TRUE))
  if (grepl("case for holding rates", text, fixed = TRUE) &&
      grepl("very hard", text, fixed = TRUE)) {
    dovish_score <- max(0, dovish_score - 2)
    hawkish_score <- hawkish_score + 2
  }
  if (grepl("forceful response not yet warranted", text, fixed = TRUE) ||
      grepl("forceful response not warranted", text, fixed = TRUE)) {
    dovish_score <- dovish_score + 3
  } else if (grepl("not yet warranted", text, fixed = TRUE)) {
    dovish_score <- dovish_score + 3
  }
  if (grepl("probably between the baseline and milder scenario", text, fixed = TRUE)) {
    dovish_score <- dovish_score + 2
  } else if (grepl("milder scenario", text, fixed = TRUE)) {
    dovish_score <- dovish_score + 2
  }
  hawkish_score <- hawkish_score + 2 * sum(vapply(c("further rate", "not finished", "upside", "deterioration in the inflation outlook"), grepl, logical(1), x = text, fixed = TRUE))
  hawkish_score - dovish_score
}

current_view_calibration_marker <- function() {
  "current_view_2026-07-09"
}

current_ecb_member_tone_prior <- function(member) {
  # Calibrated from the 9 Jul 2026 Deutsche Bank Governing Council table
  # provided by the user. Positive = more hawkish, negative = more dovish.
  priors <- c(
    Schnabel = 2,
    Simkus = 2,
    Nagel = 1,
    Panetta = 1,
    Wunsch = 1,
    Makhlouf = 1,
    Kaasik = 1,
    Kocher = 1,
    Vujcic = 1,
    Lane = 1,
    Escriva = 1,
    Kazimir = 1,
    Lagarde = 0,
    Moulin = -1,
    Demarco = -1,
    Kazaks = -1,
    Rehn = -1,
    Sleijpen = -1,
    Pereira = -1,
    Stournaras = -2
  )
  normalized <- normalize_ecb_member_name_ascii(member)
  if (!normalized %in% names(priors)) {
    return(0)
  }
  value <- priors[[normalized]]
  if (is.na(value)) 0 else value
}

current_view_phrase_score <- function(text) {
  text <- tolower(text)
  hawkish <- c(
    "more hikes are needed",
    "one more rate hike",
    "keeping options open",
    "options open",
    "still have work to do",
    "june hike is too small",
    "inflation threat is lower, but not completely contained",
    "second-round effects are emerging",
    "energy disruptions to last",
    "services prices are key",
    "new projections",
    "inflation to remain higher for longer",
    "upside risks",
    "not foreclosing",
    "raise interest rates further"
  )
  dovish <- c(
    "good to stay where we are",
    "stay where we are",
    "no new cycle",
    "not rush",
    "no urgency",
    "under no pressure",
    "no pressure to act urgently",
    "no pressure to act",
    "no need to respond forcefully",
    "no critical second-round",
    "don't want to surprise markets",
    "doesn't want to surprise markets",
    "not speculate on future ecb rates",
    "balance of risks is in the right place",
    "no commitment",
    "hold"
  )
  sum(vapply(hawkish, grepl, logical(1), x = text, fixed = TRUE)) -
    sum(vapply(dovish, grepl, logical(1), x = text, fixed = TRUE))
}

speaker_policy_score <- function(member, text, use_current_view_prior = FALSE) {
  base_score <- policy_score(text) + current_view_phrase_score(text)
  text_lower <- tolower(text)
  non_policy_only <- grepl("digital euro|cyber|payments|ai can boost", text_lower) &&
    !grepl("inflation|rate|monetary policy|transmission|oil|wage|second-round", text_lower)
  if (non_policy_only) {
    return(base_score)
  }

  calibration <- 0
  if (isTRUE(use_current_view_prior)) {
    calibration <- current_ecb_member_tone_prior(member)
    calibration <- max(min(calibration, 2), -2)
    if (abs(base_score) >= 3) {
      calibration <- sign(calibration) * min(abs(calibration), 1)
    }
  }
  base_score + calibration
}

score_to_bias <- function(score) {
  if (score >= 3) return("hawkish")
  if (score > 0) return("mildly hawkish")
  if (score <= -3) return("dovish")
  if (score < 0) return("mildly dovish")
  "neutral"
}

score_to_stance_bucket <- function(score) {
  bias_to_stance_bucket(score_to_bias(score))
}

bias_to_stance_bucket <- function(bias) {
  switch(
    bias,
    "dovish" = -2,
    "mildly dovish" = -1,
    "neutral" = 0,
    "mildly hawkish" = 1,
    "hawkish" = 2,
    0
  )
}

compare_member_stance <- function(rows) {
  result <- rep("First recent item", nrow(rows))
  marker <- current_view_calibration_marker()
  if (!"tone_calibration" %in% names(rows)) {
    rows$tone_calibration <- ""
  }

  for (member in unique(rows$member)) {
    idx <- which(rows$member == member)
    for (pos in seq_along(idx)) {
      if (!identical(rows$tone_calibration[idx[[pos]]], marker) && pos == length(idx)) {
        next
      }
      current <- bias_to_stance_bucket(rows$bias[idx[[pos]]])
      previous <- if (identical(rows$tone_calibration[idx[[pos]]], marker)) {
        current_ecb_member_tone_prior(member)
      } else {
        bias_to_stance_bucket(rows$bias[idx[[pos + 1]]])
      }
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
    tone_calibration = "",
    stringsAsFactors = FALSE
  )
}

