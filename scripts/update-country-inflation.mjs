import { mkdir, writeFile } from "node:fs/promises";

const countries = {
  DE: "Germany",
  FR: "France",
  IT: "Italy",
  ES: "Spain",
  BE: "Belgium",
};

const components = {
  headline: { code: "CP00", currentCode: "TOTAL", label: "Headline" },
  core: { code: "TOT_X_NRG_FOOD", label: "Core" },
  core_exvolatile: { code: "TOT_X_NRG_FOOD_NP", label: "Core ex-energy & unprocessed food" },
  neig: { code: "IGD_NNRG", label: "NEIG" },
  services: { code: "SERV", label: "Services" },
};

const sourceUrl =
  "https://ec.europa.eu/eurostat/databrowser/view/prc_hicp_midx/default/table?lang=en";

function dimensionCodes(json, id) {
  const index = json.dimension[id].category.index;
  return Object.entries(index)
    .sort((a, b) => a[1] - b[1])
    .map(([code]) => code);
}

function valueAt(json, selection) {
  const ids = json.id;
  const sizes = json.size;
  let flat = 0;
  for (let i = 0; i < ids.length; i += 1) {
    const codes = dimensionCodes(json, ids[i]);
    const pos = codes.indexOf(selection[ids[i]]);
    if (pos < 0) return null;
    flat = flat * sizes[i] + pos;
  }
  const raw = json.value?.[String(flat)];
  return Number.isFinite(raw) ? raw : null;
}

function csvCell(value) {
  const text = String(value ?? "");
  return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

function addRow(rows, { date, chartId, seriesId, seriesName, country, value, unit, note = "" }) {
  if (!Number.isFinite(value)) return;
  rows.push({
    date,
    chart_id: chartId,
    series_id: seriesId,
    series_name: seriesName,
    country,
    value: value.toFixed(6),
    axis: "left",
    unit,
    source: "Eurostat HICP",
    source_url: sourceUrl,
    frequency: "monthly",
    source_note: note,
  });
}

const rows = [];
const indexRows = [];
const currentYear = new Date().getUTCFullYear();

for (const [geo, country] of Object.entries(countries)) {
  const legacyUrl =
    `https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/prc_hicp_midx` +
    `?lang=en&unit=I15&geo=${geo}`;
  const currentUrl =
    `https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/prc_hicp_fpd` +
    `?lang=en&unit=I25&release=FIN&geo=${geo}`;
  const weightsUrl =
    `https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/prc_hicp_inw` +
    `?lang=en&geo=${geo}`;
  const [legacyResponse, currentResponse, weightsResponse] = await Promise.all([
    fetch(legacyUrl),
    fetch(currentUrl),
    fetch(weightsUrl),
  ]);
  if (!legacyResponse.ok) throw new Error(`Eurostat legacy ${geo}: ${legacyResponse.status}`);
  if (!currentResponse.ok) throw new Error(`Eurostat current ${geo}: ${currentResponse.status}`);
  if (!weightsResponse.ok) throw new Error(`Eurostat weights ${geo}: ${weightsResponse.status}`);
  const [legacyJson, currentJson] = await Promise.all([
    legacyResponse.json(),
    currentResponse.json(),
  ]);
  const weightsJson = await weightsResponse.json();
  const legacyTimes = dimensionCodes(legacyJson, "time");
  const currentTimes = dimensionCodes(currentJson, "time");
  const weightTimes = dimensionCodes(weightsJson, "time");

  for (const [key, component] of Object.entries(components)) {
    const legacy = legacyTimes
      .map((period) => ({
        period,
        date: `${period}-01`,
        index: valueAt(legacyJson, {
          freq: "M",
          unit: "I15",
          coicop: component.code,
          geo,
          time: period,
        }),
      }))
      .filter((row) => Number.isFinite(row.index));
    const current = currentTimes
      .map((period) => ({
        period,
        date: `${period}-01`,
        index: valueAt(currentJson, {
          freq: "M",
          unit: "I25",
          release: "FIN",
          coicop18: component.currentCode || component.code,
          geo,
          time: period,
        }),
      }))
      .filter((row) => Number.isFinite(row.index));
    const legacyMap = new Map(legacy.map((row) => [row.period, row.index]));
    const common = current.filter((row) => legacyMap.has(row.period));
    const scale = common.length
      ? legacyMap.get(common.at(-1).period) / common.at(-1).index
      : 1;
    const combined = new Map(legacy.map((row) => [row.period, row]));
    current.forEach((row) => combined.set(row.period, { ...row, index: row.index * scale }));
    const observations = [...combined.values()].sort((a, b) => a.period.localeCompare(b.period));
    observations.forEach((row) =>
      indexRows.push({
        date: row.date,
        geo,
        country,
        component: key,
        nsa_index: row.index.toFixed(8),
      }),
    );

    const latestWeight = weightTimes
      .map((period) => ({
        period,
        value: valueAt(weightsJson, {
          freq: "A",
          coicop: component.code,
          geo,
          time: period,
        }),
      }))
      .filter((row) => Number.isFinite(row.value))
      .at(-1);
    if (latestWeight) {
      addRow(rows, {
        date: `${latestWeight.period}-01-01`,
        chartId: "country_inflation_summary",
        seriesId: `${geo.toLowerCase()}_${key}_weight`,
        seriesName: `${component.label} weight`,
        country,
        value: latestWeight.value / 10,
        unit: "% weight",
      });
    }

    const rateChart = `country_${geo.toLowerCase()}_${key}_rates`;
    for (let i = 0; i < observations.length; i += 1) {
      const current = observations[i];
      const lag1 = observations[i - 1];
      const lag12 = observations[i - 12];
      const yoy = lag12 ? (current.index / lag12.index - 1) * 100 : null;
      const mom = lag1 ? (current.index / lag1.index - 1) * 100 : null;
      addRow(rows, {
        date: current.date,
        chartId: rateChart,
        seriesId: `${geo.toLowerCase()}_${key}_yoy`,
        seriesName: `${component.label} y/y`,
        country,
        value: yoy,
        unit: "% y/y",
      });
      addRow(rows, {
        date: current.date,
        chartId: `country_${geo.toLowerCase()}_${key}_seasonality`,
        seriesId: `${geo.toLowerCase()}_${key}_mom_${current.period.slice(0, 4)}`,
        seriesName: current.period.slice(0, 4),
        country,
        value: mom,
        unit: "% m/m NSA",
      });
    }

    const monthlyHistory = new Map();
    for (const year of [2017, 2018, 2019]) {
      for (const obs of observations.filter((row) => row.period.startsWith(`${year}-`))) {
        const idx = observations.indexOf(obs);
        const lag = observations[idx - 1];
        if (!lag) continue;
        const month = Number(obs.period.slice(5, 7));
        const value = (obs.index / lag.index - 1) * 100;
        if (!monthlyHistory.has(month)) monthlyHistory.set(month, []);
        monthlyHistory.get(month).push(value);
      }
    }
    for (let month = 1; month <= 12; month += 1) {
      const values = monthlyHistory.get(month) || [];
      const average = values.length ? values.reduce((a, b) => a + b, 0) / values.length : null;
      const syntheticDate = `2000-${String(month).padStart(2, "0")}-01`;
      addRow(rows, {
        date: syntheticDate,
        chartId: `country_${geo.toLowerCase()}_${key}_seasonality`,
        seriesId: `${geo.toLowerCase()}_${key}_mom_nsa_median`,
        seriesName: "2017-2019 avg",
        country,
        value: average,
        unit: "% m/m NSA",
      });
      addRow(rows, {
        date: syntheticDate,
        chartId: `country_${geo.toLowerCase()}_${key}_seasonality`,
        seriesId: `${geo.toLowerCase()}_${key}_mom_nsa_range_min`,
        seriesName: "2017-2019 min",
        country,
        value: values.length ? Math.min(...values) : null,
        unit: "% m/m NSA",
      });
      addRow(rows, {
        date: syntheticDate,
        chartId: `country_${geo.toLowerCase()}_${key}_seasonality`,
        seriesId: `${geo.toLowerCase()}_${key}_mom_nsa_range_max`,
        seriesName: "2017-2019 max",
        country,
        value: values.length ? Math.max(...values) : null,
        unit: "% m/m NSA",
      });
    }
  }
}

const keepYears = new Set(["2022", "2023", "2024", "2025", String(currentYear)]);
const filtered = rows.filter(
  (row) =>
    !row.chart_id.endsWith("_seasonality") ||
    row.date.startsWith("2000-") ||
    keepYears.has(row.date.slice(0, 4)),
);

const headers = Object.keys(filtered[0]);
const csv = [
  headers.join(","),
  ...filtered.map((row) => headers.map((header) => csvCell(row[header])).join(",")),
].join("\n");

await mkdir("public/data", { recursive: true });
await writeFile("public/data/country_inflation_series.csv", `\uFEFF${csv}\n`, "utf8");
await mkdir("data/processed", { recursive: true });
const indexHeaders = Object.keys(indexRows[0]);
const indexCsv = [
  indexHeaders.join(","),
  ...indexRows.map((row) => indexHeaders.map((header) => csvCell(row[header])).join(",")),
].join("\n");
await writeFile("data/processed/country_inflation_indices.csv", `${indexCsv}\n`, "utf8");
console.log(`Wrote ${filtered.length} Eurostat country-inflation observations.`);
