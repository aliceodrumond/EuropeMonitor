build_ecb_speakers <- function(project_root) {
  speakers <- data.frame(
    date = c(
      "2026-06-11",
      "2026-06-11",
      "2026-06-15",
      "2026-06-15",
      "2026-06-15",
      "2026-06-16",
      "2026-06-16",
      "2026-06-18",
      "2026-06-19"
    ),
    member = c(
      "Statement",
      "Press conference",
      "Lagarde",
      "Kazaks",
      "Nagel",
      "Escriva",
      "Lane",
      "Kocher",
      "Wunsch"
    ),
    position = c(
      "",
      "",
      "President",
      "Latvia",
      "Germany",
      "Spain",
      "Chief Economist",
      "Austria",
      "Belgium"
    ),
    country = c(
      "ECB",
      "ECB",
      "ECB",
      "Latvia",
      "Germany",
      "Spain",
      "Ireland",
      "Austria",
      "Belgium"
    ),
    event_type = c(
      "Statement",
      "Press conference",
      "Speech",
      "Interview",
      "Speech",
      "Speech",
      "Interview",
      "Speech",
      "Interview"
    ),
    policy_comments = c(
      "+25bps; data-dependent stance; policy remains meeting-by-meeting while uncertainty is elevated.",
      "Labor market remains resilient; upside inflation risks from energy; no insurance hike discussed.",
      "Second-round effects are the key watch item; services inflation and wage increases remain central.",
      "ECB can move gradually, but is ready to act again if inflation evidence deteriorates.",
      "Policy options remain open; rates still broadly neutral; higher energy costs could persist.",
      "ECB must remain agile; direct price pressures may fade, but indirect effects are still uncertain.",
      "June hike was a delta response; latest estimates have moved closer to 2.5%; services are sticky.",
      "Inflation may stay higher for some time; wage growth needs close monitoring.",
      "If data move in the wrong direction, a second hike should not be ruled out."
    ),
    bias = c(
      "neutral",
      "neutral",
      "hawkish",
      "hawkish",
      "hawkish",
      "neutral",
      "hawkish",
      "hawkish",
      "hawkish"
    ),
    tags = c(
      "decision,statement",
      "press,risks",
      "wages,services",
      "rates,gradualism",
      "energy,neutral-rate",
      "agile,second-round",
      "wages,services",
      "wages,inflation",
      "rates,data"
    ),
    stringsAsFactors = FALSE
  )

  write_csv_utf8(speakers, file.path(project_root, "data/processed/ecb_speakers.csv"))
  speakers
}
