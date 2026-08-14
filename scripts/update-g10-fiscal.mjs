import { mkdir, readFile, writeFile } from "node:fs/promises";
import ExcelJS from "exceljs";

const IMF_API = "https://www.imf.org/external/datamapper/api/v1";
const IMF_WEO_URL = "https://data.imf.org/Datasets/WEO";
const IMF_WEO_FILE_URL = "https://data.imf.org/-/media/iData/External-Storage/Documents/2F78EE59F79143A7921E5E203D3AAA80/en/WEOApr2026all.xlsx?download=1";
const IMF_FM_URL = "https://www.imf.org/external/datamapper/datasets/FM";
const OECD_URL = "https://sdmx.oecd.org/public/rest/data/OECD.GOV.GIP,DSD_GOV_COFOG@DF_GOV_COFOG_2025,/A.FRA+DEU+ITA+GBR+USA+JPN.GE.PT_OTE_S13..GF07+GF10..PF?startPeriod=2019&endPeriod=2025&dimensionAtObservation=AllDimensions";
const OECD_PAGE_URL = "https://data-explorer.oecd.org/vis?df[ag]=OECD.GOV.GIP&df[ds]=dsDisseminateFinalDMZ&df[id]=DSD_GOV_COFOG@DF_GOV_COFOG_2025";
const SIPRI_FILE_URL = "https://www.sipri.org/sites/default/files/SIPRI-Milex-data-1949-2025_v1.2.xlsx";
const SIPRI_PAGE_URL = "https://www.sipri.org/databases/milex";
const STATCAN_2019_URL = "https://www150.statcan.gc.ca/n1/daily-quotidien/201127/dq201127a-eng.htm";
const STATCAN_2024_URL = "https://www150.statcan.gc.ca/n1/pub/11-627-m/11-627-m2025056-eng.htm";

const scopes = [
  { code: "MAE", name: "G7 aggregate", latestActual: 2024 },
  { code: "USA", name: "United States", latestActual: 2025 },
  { code: "JPN", name: "Japan", latestActual: 2024 },
  { code: "DEU", name: "Germany", latestActual: 2025 },
  { code: "FRA", name: "France", latestActual: 2024 },
  { code: "GBR", name: "United Kingdom", latestActual: 2025 },
  { code: "ITA", name: "Italy", latestActual: 2025 },
  { code: "CAN", name: "Canada", latestActual: 2024 },
];

const countryScopes = scopes.filter((scope) => scope.code !== "MAE");
const fiscalMonitorIndicators = {
  overallFm: "GGXCNL_G01_GDP_PT",
  primaryFm: "GGXONLB_G01_GDP_PT",
  revenueFm: "GGR_G01_GDP_PT",
  expenditureFm: "G_X_G01_GDP_PT",
  grossDebtFm: "G_XWDG_G01_GDP_PT",
  netDebtFm: "GGXWDN_G01_GDP_PT",
};

const weoIndicators = {
  overallWeo: "GGXCNL_NGDP",
  primaryWeo: "GGXONLB_NGDP",
  revenueWeo: "GGR_NGDP",
  expenditureWeo: "GGX_NGDP",
  grossDebtWeo: "GGXWDG_NGDP",
  netDebtWeo: "GGXWDN_NGDP",
  nominalGdpUsd: "NGDPD",
};

const seriesDefinitions = [
  ["overall_balance", "Overall balance", "overall"],
  ["primary_balance", "Primary balance", "primary"],
  ["revenue", "Revenue", "revenue"],
  ["primary_expenditure", "Primary expenditure", "primaryExpenditure"],
  ["gross_debt", "Gross debt", "grossDebt"],
  ["net_debt", "Net debt", "netDebt"],
];

function csvEscape(value) {
  const text = value === null || value === undefined ? "" : String(value);
  return /[",\n\r]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

function toCsv(rows, columns) {
  return `${columns.join(",")}\n${rows.map((row) => columns.map((column) => csvEscape(row[column])).join(",")).join("\n")}\n`;
}

function parseCsv(text) {
  const records = [];
  let row = [], field = "", quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index], next = text[index + 1];
    if (quoted) {
      if (char === '"' && next === '"') { field += '"'; index += 1; }
      else if (char === '"') quoted = false;
      else field += char;
    } else if (char === '"') quoted = true;
    else if (char === ",") { row.push(field); field = ""; }
    else if (char === "\n") { row.push(field); records.push(row); row = []; field = ""; }
    else if (char !== "\r") field += char;
  }
  if (field || row.length) { row.push(field); records.push(row); }
  const headers = records.shift() ?? [];
  return records.filter((record) => record.some(Boolean)).map((record) => Object.fromEntries(headers.map((header, index) => [header, record[index] ?? ""])));
}

async function fetchText(url, headers = {}) {
  const response = await fetch(url, {
    headers: { "user-agent": "Mozilla/5.0", ...headers },
  });
  if (!response.ok) throw new Error(`Request failed (${response.status}): ${url}`);
  return response.text();
}

async function fetchJson(url) {
  return JSON.parse(await fetchText(url, { accept: "application/json" }));
}

async function loadFiscalMonitorData() {
  const entries = await Promise.all(Object.entries(fiscalMonitorIndicators).map(async ([key, indicator]) => {
    const payload = await fetchJson(`${IMF_API}/${indicator}`);
    const allValues = payload.values?.[indicator] ?? {};
    return [key, Object.fromEntries(scopes.map((scope) => [scope.code, allValues[scope.code] ?? {}]))];
  }));
  return Object.fromEntries(entries);
}

function numberFromCell(cell) {
  const raw = typeof cell.value === "object" && cell.value !== null && "result" in cell.value ? cell.value.result : cell.value;
  return finite(raw);
}

async function loadWeoWorkbookData() {
  const workbook = new ExcelJS.Workbook();
  const localPath = process.env.WEO_APR2026_XLSX;
  if (localPath) {
    await workbook.xlsx.load(await readFile(localPath));
  } else {
    const response = await fetch(IMF_WEO_FILE_URL, { headers: { "user-agent": "Mozilla/5.0" } });
    if (!response.ok) throw new Error(`Request failed (${response.status}): ${IMF_WEO_FILE_URL}`);
    await workbook.xlsx.load(Buffer.from(await response.arrayBuffer()));
  }

  const result = Object.fromEntries(Object.keys(weoIndicators).map((key) => [key, Object.fromEntries(scopes.map((scope) => [scope.code, {}]))]));
  const indicatorKey = new Map(Object.entries(weoIndicators).map(([key, indicator]) => [indicator, key]));

  for (const scope of scopes) {
    const sheet = workbook.getWorksheet(scope.code === "MAE" ? "Country Groups" : "Countries");
    if (!sheet) throw new Error(`WEO workbook is missing the ${scope.code === "MAE" ? "Country Groups" : "Countries"} sheet.`);
    const headers = new Map();
    sheet.getRow(1).eachCell((cell, column) => headers.set(cell.text.trim(), column));
    const countryColumn = headers.get("COUNTRY.ID");
    const indicatorColumn = headers.get("INDICATOR.ID");
    const sourceCode = scope.code === "MAE" ? "G119" : scope.code;

    sheet.eachRow((row, rowNumber) => {
      if (rowNumber === 1 || row.getCell(countryColumn).text.trim() !== sourceCode) return;
      const key = indicatorKey.get(row.getCell(indicatorColumn).text.trim());
      if (!key) return;
      for (let year = 1980; year <= 2031; year += 1) {
        const yearColumn = headers.get(String(year));
        const value = yearColumn ? numberFromCell(row.getCell(yearColumn)) : null;
        if (value !== null) result[key][scope.code][year] = value;
      }
    });
  }
  return result;
}

async function loadImfData() {
  const [fiscalMonitor, weo] = await Promise.all([loadFiscalMonitorData(), loadWeoWorkbookData()]);
  return { ...fiscalMonitor, ...weo };
}

function statusFor(scope, year) {
  if (year <= scope.latestActual) return "actual";
  if (year === 2025) return "estimate";
  return "projection";
}

function finite(value) {
  if (value === null || value === undefined || value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function chooseImfValue(weoValue, fiscalMonitorValue) {
  const weo = finite(weoValue);
  if (weo !== null) return { value: weo, source: "weo" };
  const fiscalMonitor = finite(fiscalMonitorValue);
  return { value: fiscalMonitor, source: fiscalMonitor === null ? null : "fiscal-monitor" };
}

function pickSeries(imf, scopeCode, year) {
  const key = String(year);
  const overall = chooseImfValue(imf.overallWeo[scopeCode]?.[key], imf.overallFm[scopeCode]?.[key]);
  const primary = chooseImfValue(imf.primaryWeo[scopeCode]?.[key], imf.primaryFm[scopeCode]?.[key]);
  const revenue = chooseImfValue(imf.revenueWeo[scopeCode]?.[key], imf.revenueFm[scopeCode]?.[key]);
  const expenditure = chooseImfValue(imf.expenditureWeo[scopeCode]?.[key], imf.expenditureFm[scopeCode]?.[key]);
  const grossDebt = chooseImfValue(imf.grossDebtWeo[scopeCode]?.[key], imf.grossDebtFm[scopeCode]?.[key]);
  const netDebt = chooseImfValue(imf.netDebtWeo[scopeCode]?.[key], imf.netDebtFm[scopeCode]?.[key]);
  return {
    overall: overall.value,
    primary: primary.value,
    revenue: revenue.value,
    expenditure: expenditure.value,
    primaryExpenditure: revenue.value !== null && primary.value !== null ? revenue.value - primary.value : null,
    grossDebt: grossDebt.value,
    netDebt: netDebt.value,
    sources: {
      overall: overall.source,
      primary: primary.source,
      revenue: revenue.source,
      expenditure: expenditure.source,
      primaryExpenditure: "derived",
      grossDebt: grossDebt.source,
      netDebt: netDebt.source,
    },
  };
}

function buildHistory(imf) {
  const rows = [];
  for (const scope of scopes) {
    for (let year = 1980; year <= 2031; year += 1) {
      const values = pickSeries(imf, scope.code, year);
      for (const [seriesId, seriesName, key] of seriesDefinitions) {
        const value = values[key];
        if (value === null) continue;
        const derived = key === "primaryExpenditure";
        const sourceType = values.sources[key];
        rows.push({
          scope_code: scope.code,
          scope_name: scope.name,
          year,
          series_id: seriesId,
          series_name: seriesName,
          value: value.toFixed(4),
          status: statusFor(scope, year),
          source: derived ? "IMF WEO / derived" : sourceType === "weo" ? "IMF WEO" : "IMF Fiscal Monitor",
          source_url: sourceType === "fiscal-monitor" ? IMF_FM_URL : IMF_WEO_URL,
          source_note: derived ? "Primary expenditure = revenue - primary balance." : "April 2026 vintage; general government; percent of GDP; Fiscal Monitor used only where WEO is unavailable.",
        });
      }
    }
  }
  return rows;
}

async function loadOecdShares() {
  const text = await fetchText(OECD_URL, { accept: "text/csv", "accept-language": "en-US,en;q=0.9" });
  const sourceRows = parseCsv(text).filter((row) => ["GF07", "GF10"].includes(row.EXPENDITURE));
  const result = {};
  for (const scope of countryScopes.filter((item) => item.code !== "CAN")) {
    const rows = sourceRows.filter((row) => row.REF_AREA === scope.code);
    const years = [...new Set(rows.map((row) => Number(row.TIME_PERIOD)).filter(Number.isFinite))].sort((a, b) => a - b);
    const latestYear = years.at(-1);
    const sharesFor = (year) => {
      const byFunction = Object.fromEntries(rows.filter((row) => Number(row.TIME_PERIOD) === year).map((row) => [row.EXPENDITURE, Number(row.OBS_VALUE)]));
      return finite(byFunction.GF07) !== null && finite(byFunction.GF10) !== null ? byFunction.GF07 + byFunction.GF10 : null;
    };
    result[scope.code] = { actual2019: sharesFor(2019), estimate2025: sharesFor(latestYear), latestYear };
  }
  result.CAN = {
    actual2019: 47.3,
    estimate2025: 48.56,
    latestYear: 2024,
    note: "Statistics Canada CCOFOG shares: 2019 actual; 2024/25 latest available used for the 2025 estimate.",
  };
  return { sourceRows, shares: result };
}

async function loadSipriShares() {
  const workbook = new ExcelJS.Workbook();
  const localPath = process.env.SIPRI_MILEX_XLSX;
  if (localPath) {
    await workbook.xlsx.load(await readFile(localPath));
  } else {
    const response = await fetch(SIPRI_FILE_URL, { headers: { "user-agent": "Mozilla/5.0" } });
    if (!response.ok) throw new Error(`Request failed (${response.status}): ${SIPRI_FILE_URL}`);
    await workbook.xlsx.load(Buffer.from(await response.arrayBuffer()));
  }
  const sheet = workbook.getWorksheet("Share of GDP");
  if (!sheet) throw new Error("SIPRI workbook is missing the Share of GDP sheet.");
  const header = sheet.getRow(6).values;
  const yearColumn = new Map();
  for (let column = 1; column < header.length; column += 1) {
    const year = Number(header[column]);
    if (Number.isFinite(year)) yearColumn.set(year, column);
  }
  const sipriNames = {
    USA: "United States of America",
    JPN: "Japan",
    DEU: "Germany",
    FRA: "France",
    GBR: "United Kingdom",
    ITA: "Italy",
    CAN: "Canada",
  };
  const result = {};
  sheet.eachRow((row, rowNumber) => {
    if (rowNumber <= 6) return;
    const country = String(row.getCell(1).value ?? "").trim();
    const code = Object.entries(sipriNames).find(([, name]) => country === name)?.[0];
    if (!code) return;
    result[code] = {};
    for (const year of [2019, 2025]) {
      const raw = row.getCell(yearColumn.get(year)).value;
      const value = typeof raw === "object" && raw !== null && "result" in raw ? raw.result : raw;
      const number = finite(value);
      if (number !== null) result[code][year] = number * 100;
    }
  });
  return result;
}

function weightedAggregate(countryRows, imf, year) {
  const values = [];
  for (const scope of countryScopes) {
    const gdp = finite(imf.nominalGdpUsd[scope.code]?.[String(year)]);
    const row = countryRows.find((item) => item.scope_code === scope.code && item.year === year);
    if (gdp !== null && row) values.push({ gdp, row });
  }
  const totalGdp = values.reduce((sum, item) => sum + item.gdp, 0);
  if (!totalGdp) return null;
  const components = ["mandatory_proxy", "other_primary", "military", "interest"];
  return Object.fromEntries(components.map((component) => [component, values.reduce((sum, item) => sum + item.gdp * item.row[component], 0) / totalGdp]));
}

function buildComposition(imf, oecd, sipri) {
  const countryRows = [];
  for (const scope of countryScopes) {
    for (const year of [2019, 2025]) {
      const fiscal = pickSeries(imf, scope.code, year);
      const total = fiscal.expenditure;
      const interest = fiscal.primary !== null && fiscal.overall !== null ? fiscal.primary - fiscal.overall : null;
      const shareInfo = oecd.shares[scope.code];
      const socialHealthShare = year === 2019 ? shareInfo?.actual2019 : shareInfo?.estimate2025;
      const military = finite(sipri[scope.code]?.[year]);
      if ([total, interest, socialHealthShare, military].some((value) => value === null || value === undefined)) {
        throw new Error(`Missing composition input for ${scope.code} ${year}.`);
      }
      const mandatoryProxy = total * socialHealthShare / 100;
      const otherPrimary = total - mandatoryProxy - military - interest;
      if (otherPrimary < 0) throw new Error(`Negative other-primary residual for ${scope.code} ${year}.`);
      countryRows.push({
        scope_code: scope.code,
        scope_name: scope.name,
        year,
        mandatory_proxy: mandatoryProxy,
        other_primary: otherPrimary,
        military,
        interest,
        total,
        cofog_year: year === 2019 ? 2019 : shareInfo.latestYear,
      });
    }
  }

  const aggregateRows = [2019, 2025].map((year) => {
    const aggregate = weightedAggregate(countryRows, imf, year);
    if (!aggregate) throw new Error(`Unable to calculate G7 composition for ${year}.`);
    return {
      scope_code: "MAE",
      scope_name: "G7 aggregate",
      year,
      ...aggregate,
      total: Object.values(aggregate).reduce((sum, value) => sum + value, 0),
      cofog_year: year === 2019 ? 2019 : 2023,
    };
  });

  const componentNames = {
    mandatory_proxy: "Social protection + health",
    other_primary: "Other primary expenditure",
    military: "Military expenditure",
    interest: "Interest expenditure",
  };
  const rows = [];
  for (const item of [...aggregateRows, ...countryRows]) {
    for (const [componentId, componentName] of Object.entries(componentNames)) {
      const isEstimate = item.year === 2025;
      rows.push({
        scope_code: item.scope_code,
        scope_name: item.scope_name,
        year: item.year,
        component_id: componentId,
        component_name: componentName,
        value: item[componentId].toFixed(4),
        status: isEstimate ? "estimate" : "actual",
        source: componentId === "military" ? "SIPRI" : componentId === "mandatory_proxy" ? (item.scope_code === "CAN" ? "Statistics Canada / IMF" : "OECD COFOG / IMF") : "IMF / derived residual",
        source_url: componentId === "military" ? SIPRI_PAGE_URL : componentId === "mandatory_proxy" ? (item.scope_code === "CAN" ? STATCAN_2024_URL : OECD_PAGE_URL) : IMF_FM_URL,
        source_note: componentId === "mandatory_proxy" ? `Social protection + health share from ${item.cofog_year}, applied to IMF total expenditure.` : componentId === "other_primary" ? "Residual ensuring the four components sum to total expenditure." : componentId === "interest" ? "Primary balance minus overall balance." : "Military expenditure as a share of GDP.",
      });
    }
  }
  return { countryRows, rows };
}

async function main() {
  const [imf, oecd, sipri] = await Promise.all([loadImfData(), loadOecdShares(), loadSipriShares()]);
  const historyRows = buildHistory(imf);
  const composition = buildComposition(imf, oecd, sipri);

  for (const row of historyRows.filter((item) => item.series_id === "primary_expenditure")) {
    const revenue = historyRows.find((item) => item.scope_code === row.scope_code && item.year === row.year && item.series_id === "revenue");
    const primary = historyRows.find((item) => item.scope_code === row.scope_code && item.year === row.year && item.series_id === "primary_balance");
    if (!revenue || !primary || Math.abs(Number(row.value) - (Number(revenue.value) - Number(primary.value))) > 0.001) {
      throw new Error(`Primary-expenditure identity failed for ${row.scope_code} ${row.year}.`);
    }
  }

  const groupedComposition = new Map();
  for (const row of composition.rows) {
    const key = `${row.scope_code}|${row.year}`;
    groupedComposition.set(key, (groupedComposition.get(key) ?? 0) + Number(row.value));
  }
  for (const [key, total] of groupedComposition) {
    if (!Number.isFinite(total) || total <= 0) throw new Error(`Composition total failed for ${key}.`);
  }

  await mkdir("public/data", { recursive: true });
  await mkdir("data/raw", { recursive: true });
  await writeFile("public/data/g10_fiscal_history.csv", toCsv(historyRows, ["scope_code", "scope_name", "year", "series_id", "series_name", "value", "status", "source", "source_url", "source_note"]));
  await writeFile("public/data/g10_fiscal_composition.csv", toCsv(composition.rows, ["scope_code", "scope_name", "year", "component_id", "component_name", "value", "status", "source", "source_url", "source_note"]));
  await writeFile("public/data/g10_fiscal_metadata.json", `${JSON.stringify({
    generated_at: new Date().toISOString(),
    imf_vintage: "April 2026",
    coverage: "G7 core MVP",
    history_start: 1980,
    history_end: 2031,
    sources: { imf_weo: IMF_WEO_URL, imf_weo_download: IMF_WEO_FILE_URL, imf_fiscal_monitor: IMF_FM_URL, oecd_cofog: OECD_PAGE_URL, sipri: SIPRI_PAGE_URL, statistics_canada_2019: STATCAN_2019_URL, statistics_canada_2024: STATCAN_2024_URL },
    notes: ["No interpolation is applied to missing net-debt or historical fiscal series.", "The 2025 expenditure composition is an estimate using the latest available COFOG shares.", "G7 aggregates in the historical charts use the official IMF Major Advanced Economies series."],
  }, null, 2)}\n`);
  await writeFile("data/raw/imf_g10_fiscal_april_2026.json", `${JSON.stringify(imf, null, 2)}\n`);
  await writeFile("data/raw/oecd_g7_cofog_selected.csv", toCsv(oecd.sourceRows, Object.keys(oecd.sourceRows[0] ?? {})));
  await writeFile("data/raw/sipri_g7_military_share_gdp.csv", toCsv(countryScopes.flatMap((scope) => [2019, 2025].map((year) => ({ scope_code: scope.code, scope_name: scope.name, year, value: sipri[scope.code]?.[year] ?? "" }))), ["scope_code", "scope_name", "year", "value"]));

  console.log(`Wrote ${historyRows.length} fiscal-history rows and ${composition.rows.length} composition rows.`);
}

await main();
