econostream_central_bank_url <- "https://www.econostream-media.com/news/topic/centralbank"

build_ecb_speakers <- function(project_root) {
  processed_path <- file.path(project_root, "data/processed/ecb_speakers.csv")
  speakers <- tryCatch(
    fetch_econostream_ecb_speakers(econostream_central_bank_url),
    error = function(error) {
      previous <- tryCatch(
        read.csv(processed_path, stringsAsFactors = FALSE, check.names = FALSE),
        error = function(...) NULL
      )
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

  speakers <- apply_speaker_highlight_overrides(speakers)
  write_csv_utf8(speakers, processed_path)
  speakers
}

apply_speaker_highlight_overrides <- function(speakers) {
  escriva_chain_transmission <- paste(
    "In other words, price increases are being transmitted throughout production chains and goods markets.",
    "We are seeing this, for example, in transportation services and in food production sectors that use plastics or energy as inputs."
  )

  idx <- speakers$member == "EscrivÃ¡" &
    speakers$date == "2026-06-23" &
    grepl("diplomatic_resolution_scenario", speakers$source_url, fixed = TRUE)

  speakers$policy_comments[idx] <- escriva_chain_transmission
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
  tmp <- tempfile(fileext = ".html")
  script <- sprintf(
    "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -TimeoutSec 45 -Uri %s -OutFile %s",
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

normalize_ecb_member_name <- function(member) {
  if (grepl("Vuj", member, fixed = TRUE)) return("Vujcic")
  if (grepl("Kaz", member, fixed = TRUE) || grepl("im", member, fixed = TRUE)) {
    if (grepl("mir|mÃ­r|mír", member, ignore.case = TRUE)) return("Kazimir")
  }
  if (grepl("Escriv", member, fixed = TRUE)) return("Escriva")
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
  if (grepl("Vuj", member, fixed = TRUE)) return("Vujcic")
  if (grepl("Kaz", member, fixed = TRUE) || grepl("im", member, fixed = TRUE)) return("Kazimir")
  if (grepl("Escriv", member, fixed = TRUE)) return("Escriva")
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
  claim <- sub("^ECB'?s\\s+[^:]+:\\s*", "", headline)
  claim <- sub("^ECB.s\\s+[^:]+:\\s*", "", claim)
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
  hawkish <- c("rate hike", "hike", "inflation pressures", "restrictive", "wages", "high inflation")
  dovish <- c("hold", "holding rates", "no commitment", "gradual", "no forward guidance", "wait", "pause", "no roadmap", "refraining from signaling", "unchanged")

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

  for (member in unique(rows$member)) {
    idx <- which(rows$member == member)
    if (length(idx) < 2) {
      next
    }
    for (pos in seq_len(length(idx) - 1)) {
      current <- bias_to_stance_bucket(rows$bias[idx[[pos]]])
      previous <- bias_to_stance_bucket(rows$bias[idx[[pos + 1]]])
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
