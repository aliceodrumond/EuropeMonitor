import fs from "node:fs";
import path from "node:path";
import ExcelJS from "exceljs";
import sharp from "sharp";

const root = process.cwd();
const inputPath = path.join(root, "data", "processed", "activity_series.csv");
const outputPath = path.join(root, "reports", "sentix_pmi_ols_model.xlsx");
const chartImagePath = path.join(root, "reports", "sentix_pmi_ols_chart.png");
const pmiOverrides = new Map([
  ["2026-06-01", 50.0],
]);

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;

  for (let i = 0; i < text.length; i += 1) {
    const c = text[i];
    const n = text[i + 1];
    if (quoted) {
      if (c === '"' && n === '"') {
        field += '"';
        i += 1;
      } else if (c === '"') {
        quoted = false;
      } else {
        field += c;
      }
    } else if (c === '"') {
      quoted = true;
    } else if (c === ",") {
      row.push(field);
      field = "";
    } else if (c === "\n") {
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else if (c !== "\r") {
      field += c;
    }
  }
  if (field.length || row.length) {
    row.push(field);
    rows.push(row);
  }
  const header = rows.shift();
  return rows.map((values) => Object.fromEntries(header.map((key, idx) => [key, values[idx] ?? ""])));
}

function excelDate(dateText) {
  const [year, month, day] = dateText.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day));
}

function mean(values) {
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function ols(rows) {
  const xs = rows.map((row) => row.sentix);
  const ys = rows.map((row) => row.pmi);
  const xBar = mean(xs);
  const yBar = mean(ys);
  const sxx = xs.reduce((sum, x) => sum + (x - xBar) ** 2, 0);
  const sxy = rows.reduce((sum, row) => sum + (row.sentix - xBar) * (row.pmi - yBar), 0);
  const beta = sxy / sxx;
  const alpha = yBar - beta * xBar;
  const fitted = rows.map((row) => alpha + beta * row.sentix);
  const residuals = rows.map((row, idx) => row.pmi - fitted[idx]);
  const sse = residuals.reduce((sum, value) => sum + value ** 2, 0);
  const sst = ys.reduce((sum, y) => sum + (y - yBar) ** 2, 0);
  const sigma2 = sse / (rows.length - 2);
  const seBeta = Math.sqrt(sigma2 / sxx);
  const seAlpha = Math.sqrt(sigma2 * (1 / rows.length + xBar ** 2 / sxx));
  return {
    alpha,
    beta,
    r2: 1 - sse / sst,
    n: rows.length,
    rmse: Math.sqrt(sse / rows.length),
    seAlpha,
    seBeta,
    tAlpha: alpha / seAlpha,
    tBeta: beta / seBeta,
  };
}

function applyHeaderStyle(row) {
  row.font = { bold: true, color: { argb: "FFFFFFFF" } };
  row.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF1F4E78" } };
  row.alignment = { vertical: "middle", horizontal: "center" };
}

function setColumns(sheet, columns) {
  sheet.columns = columns.map(([header, key, width]) => ({ header, key, width }));
  applyHeaderStyle(sheet.getRow(1));
  sheet.views = [{ state: "frozen", ySplit: 1 }];
}

function linePath(points) {
  return points
    .map((point, idx) => `${idx === 0 ? "M" : "L"} ${point.x.toFixed(1)} ${point.y.toFixed(1)}`)
    .join(" ");
}

function circlePoints(points, color) {
  return points
    .map((point) => `<circle cx="${point.x.toFixed(1)}" cy="${point.y.toFixed(1)}" r="7" fill="${color}" stroke="#ffffff" stroke-width="2"/>`)
    .join("");
}

async function writeChartImage(chartRows, scenarioRows) {
  const width = 1120;
  const height = 620;
  const margin = { left: 72, right: 32, top: 62, bottom: 76 };
  const plotWidth = width - margin.left - margin.right;
  const plotHeight = height - margin.top - margin.bottom;
  const allDates = [...chartRows.map((row) => row.date), "2026-07-01"];
  const yMin = 47;
  const yMax = 53;
  const index = new Map(allDates.map((date, idx) => [date, idx]));
  const x = (date) => margin.left + (index.get(date) / (allDates.length - 1)) * plotWidth;
  const y = (value) => margin.top + ((yMax - value) / (yMax - yMin)) * plotHeight;
  const actualPoints = chartRows.map((row) => ({ x: x(row.date), y: y(row.pmi) }));
  const fittedPoints = chartRows
    .filter((row) => row.date >= "2026-01-01")
    .map((row) => ({ x: x(row.date), y: y(row.fitted) }));
  const julUp = [{ x: x("2026-07-01"), y: y(scenarioRows[0].pmiEstimate) }];
  const julJun = [{ x: x("2026-07-01"), y: y(scenarioRows[1].pmiEstimate) }];
  const ticks = [47, 48, 49, 50, 51, 52, 53];
  const xLabels = allDates.map((date, idx) => {
    const month = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][Number(date.slice(5, 7)) - 1];
    const year = date.slice(2, 4);
    return idx % 2 === 0 || date === "2026-07-01"
      ? `<text x="${x(date).toFixed(1)}" y="${height - 38}" text-anchor="middle" font-size="18" fill="#334155">${month}-${year}</text>`
      : "";
  }).join("");
  const yGrid = ticks.map((tick) => {
    const yy = y(tick);
    return `<line x1="${margin.left}" y1="${yy}" x2="${width - margin.right}" y2="${yy}" stroke="#e2e8f0"/><text x="${margin.left - 14}" y="${yy + 6}" text-anchor="end" font-size="18" fill="#334155">${tick}</text>`;
  }).join("");
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
    <rect width="100%" height="100%" fill="#ffffff"/>
    <text x="${margin.left}" y="34" font-size="27" font-weight="700" fill="#0f172a">PMI Composite: actual, fitted OOS e cenarios de julho</text>
    ${yGrid}
    <line x1="${margin.left}" y1="${height - margin.bottom}" x2="${width - margin.right}" y2="${height - margin.bottom}" stroke="#94a3b8"/>
    <line x1="${margin.left}" y1="${margin.top}" x2="${margin.left}" y2="${height - margin.bottom}" stroke="#94a3b8"/>
    <path d="${linePath(actualPoints)}" fill="none" stroke="#1f77b4" stroke-width="4"/>
    <path d="${linePath(fittedPoints)}" fill="none" stroke="#2ca02c" stroke-width="4" stroke-dasharray="10 8"/>
    ${circlePoints(julUp, "#d62728")}
    ${circlePoints(julJun, "#ff7f0e")}
    ${xLabels}
    <rect x="${margin.left}" y="${height - 26}" width="18" height="5" fill="#1f77b4"/><text x="${margin.left + 26}" y="${height - 20}" font-size="17" fill="#0f172a">PMI Composite</text>
    <rect x="${margin.left + 190}" y="${height - 26}" width="18" height="5" fill="#2ca02c"/><text x="${margin.left + 216}" y="${height - 20}" font-size="17" fill="#0f172a">Fitted OOS</text>
    <circle cx="${margin.left + 360}" cy="${height - 24}" r="7" fill="#d62728"/><text x="${margin.left + 374}" y="${height - 20}" font-size="17" fill="#0f172a">Jul Sentix -7.5: ${scenarioRows[0].pmiEstimate.toFixed(1)}</text>
    <circle cx="${margin.left + 600}" cy="${height - 24}" r="7" fill="#ff7f0e"/><text x="${margin.left + 614}" y="${height - 20}" font-size="17" fill="#0f172a">Jul Sentix -13.4: ${scenarioRows[1].pmiEstimate.toFixed(1)}</text>
  </svg>`;
  await sharp(Buffer.from(svg)).png().toFile(chartImagePath);
}

const csv = fs.readFileSync(inputPath, "utf8");
const sourceRows = parseCsv(csv);
const pmi = new Map();
const sentix = new Map();

for (const row of sourceRows) {
  if (row.chart_id !== "sentix_pmi") continue;
  const value = Number(row.value);
  if (!Number.isFinite(value)) continue;
  if (row.series_id === "pmi_ea_sentix") pmi.set(row.date, value);
  if (row.series_id === "sentix_ea") sentix.set(row.date, value);
}

const data = [...pmi.entries()]
  .filter(([date]) => sentix.has(date))
  .map(([date, pmiValue]) => ({
    date,
    pmi: pmiOverrides.get(date) ?? pmiValue,
    sentix: sentix.get(date),
    note: pmiOverrides.has(date) ? "PMI override: final June 2026 release revised flash 49.5 to 50.0" : "",
  }))
  .sort((a, b) => a.date.localeCompare(b.date));

const train = data.filter((row) => row.date >= "2013-01-01" && row.date <= "2025-12-01");
const outOfSample = data.filter((row) => row.date >= "2026-01-01" && row.date <= "2026-06-01");
const model = ols(train);

for (const row of data) {
  row.fitted = model.alpha + model.beta * row.sentix;
  row.residual = row.pmi - row.fitted;
  row.sample = row.date >= "2013-01-01" && row.date <= "2025-12-01"
    ? "Estimation"
    : row.date >= "2026-01-01" && row.date <= "2026-06-01"
      ? "Out-of-sample"
      : "";
}

const oosRows = outOfSample.map((row) => ({
  ...row,
  fitted: model.alpha + model.beta * row.sentix,
  residual: row.pmi - (model.alpha + model.beta * row.sentix),
}));
const oosRmse = Math.sqrt(mean(oosRows.map((row) => row.residual ** 2)));
const oosMae = mean(oosRows.map((row) => Math.abs(row.residual)));

const scenarios = [
  { date: "2026-07-01", scenario: "Sentix julho = -7.5", sentix: -7.5 },
  { date: "2026-07-01", scenario: "Sentix junho = -13.4", sentix: -13.4 },
].map((row) => ({ ...row, pmiEstimate: model.alpha + model.beta * row.sentix }));

const chartRows = data.filter((item) => item.date >= "2025-01-01" && item.date <= "2026-06-01");
await writeChartImage(chartRows, scenarios);

const workbook = new ExcelJS.Workbook();
workbook.creator = "Codex";
workbook.created = new Date();
workbook.modified = new Date();
workbook.calcProperties.fullCalcOnLoad = true;

const summary = workbook.addWorksheet("Summary");
summary.addRow(["Modelo OLS: PMI Composite Europa = constante + beta * Sentix"]);
summary.addRow(["Fonte", "data/processed/activity_series.csv, chart_id=sentix_pmi"]);
summary.addRow(["Override", "2026-06 PMI Composite atualizado de 49.5 flash para 50.0 final"]);
summary.addRow(["Amostra de estimacao", "2013-01 a 2025-12"]);
summary.addRow(["Fora da amostra", "2026-01 a 2026-06"]);
summary.addRow([]);
summary.addRow(["Parametro", "Valor"]);
summary.addRow(["Constante", model.alpha]);
summary.addRow(["Beta Sentix", model.beta]);
summary.addRow(["R2 in-sample", model.r2]);
summary.addRow(["RMSE in-sample", model.rmse]);
summary.addRow(["N", model.n]);
summary.addRow(["RMSE out-of-sample 1S26", oosRmse]);
summary.addRow(["MAE out-of-sample 1S26", oosMae]);
summary.addRow([]);
summary.addRow(["Cenario", "Sentix", "PMI Composite estimado"]);
for (const row of scenarios) summary.addRow([row.scenario, row.sentix, row.pmiEstimate]);
summary.getColumn(1).width = 34;
summary.getColumn(2).width = 24;
summary.getColumn(3).width = 24;
summary.eachRow((row, rowNumber) => {
  if ([1, 7, 16].includes(rowNumber)) row.font = { bold: true };
});
summary.getColumn(2).numFmt = "0.000";
summary.getColumn(3).numFmt = "0.000";

const modelSheet = workbook.addWorksheet("OLS");
setColumns(modelSheet, [
  ["Metric", "metric", 30],
  ["Value", "value", 18],
]);
[
  ["Constante", model.alpha],
  ["SE constante", model.seAlpha],
  ["t constante", model.tAlpha],
  ["Beta Sentix", model.beta],
  ["SE beta", model.seBeta],
  ["t beta", model.tBeta],
  ["R2", model.r2],
  ["RMSE", model.rmse],
  ["N", model.n],
].forEach((row) => modelSheet.addRow(row));
modelSheet.getColumn(2).numFmt = "0.0000";

const fitSheet = workbook.addWorksheet("Fit");
setColumns(fitSheet, [
  ["Date", "date", 14],
  ["PMI Composite", "pmi", 16],
  ["Sentix", "sentix", 12],
  ["Fitted PMI", "fitted", 14],
  ["Residual", "residual", 14],
  ["Sample", "sample", 18],
  ["Note", "note", 46],
]);
for (const row of data.filter((item) => item.date >= "2013-01-01" && item.date <= "2026-06-01")) {
  fitSheet.addRow({
    date: excelDate(row.date),
    pmi: row.pmi,
    sentix: row.sentix,
    fitted: row.fitted,
    residual: row.residual,
    sample: row.sample,
    note: row.note,
  });
}
fitSheet.getColumn(1).numFmt = "mmm-yy";
for (const col of [2, 3, 4, 5]) fitSheet.getColumn(col).numFmt = "0.0";
fitSheet.autoFilter = "A1:F1";

const oosSheet = workbook.addWorksheet("Out-of-sample 1S26");
setColumns(oosSheet, [
  ["Date", "date", 14],
  ["PMI Composite", "pmi", 16],
  ["Sentix", "sentix", 12],
  ["Fitted PMI", "fitted", 14],
  ["Residual", "residual", 14],
  ["Abs Error", "absError", 14],
  ["Note", "note", 46],
]);
for (const row of oosRows) {
  oosSheet.addRow({
    date: excelDate(row.date),
    pmi: row.pmi,
    sentix: row.sentix,
    fitted: row.fitted,
    residual: row.residual,
    absError: Math.abs(row.residual),
    note: row.note,
  });
}
oosSheet.addRow([]);
oosSheet.addRow(["RMSE", oosRmse]);
oosSheet.addRow(["MAE", oosMae]);
oosSheet.getColumn(1).numFmt = "mmm-yy";
for (const col of [2, 3, 4, 5, 6]) oosSheet.getColumn(col).numFmt = "0.0";
oosSheet.getColumn(2).numFmt = "0.000";

const scenariosSheet = workbook.addWorksheet("Jul-26 scenarios");
setColumns(scenariosSheet, [
  ["Date", "date", 14],
  ["Scenario", "scenario", 28],
  ["Sentix", "sentix", 12],
  ["PMI Composite estimate", "pmiEstimate", 24],
]);
for (const row of scenarios) {
  scenariosSheet.addRow({
    date: excelDate(row.date),
    scenario: row.scenario,
    sentix: row.sentix,
    pmiEstimate: row.pmiEstimate,
  });
}
scenariosSheet.getColumn(1).numFmt = "mmm-yy";
scenariosSheet.getColumn(3).numFmt = "0.0";
scenariosSheet.getColumn(4).numFmt = "0.0";

const chartDataSheet = workbook.addWorksheet("Chart data");
setColumns(chartDataSheet, [
  ["Date", "date", 14],
  ["PMI Composite", "pmi", 16],
  ["Fitted OOS", "fittedOos", 14],
  ["Jul Sentix -7.5", "julSentixUp", 16],
  ["Jul Sentix -13.4", "julSentixJun", 18],
  ["Note", "note", 46],
]);
for (const row of data.filter((item) => item.date >= "2025-01-01" && item.date <= "2026-06-01")) {
  const isOos = row.date >= "2026-01-01";
  chartDataSheet.addRow({
    date: excelDate(row.date),
    pmi: row.pmi,
    fittedOos: isOos ? row.fitted : null,
    julSentixUp: null,
    julSentixJun: null,
    note: row.note,
  });
}
chartDataSheet.addRow({
  date: excelDate("2026-07-01"),
  pmi: null,
  fittedOos: null,
  julSentixUp: scenarios[0].pmiEstimate,
  julSentixJun: scenarios[1].pmiEstimate,
});
chartDataSheet.getColumn(1).numFmt = "mmm-yy";
for (const col of [2, 3, 4, 5]) chartDataSheet.getColumn(col).numFmt = "0.0";

const chartSheet = workbook.addWorksheet("Chart");
chartSheet.getColumn(1).width = 18;
chartSheet.getRow(1).height = 24;
chartSheet.getCell("A1").value = "PMI Composite: actual, fitted fora da amostra e cenarios de julho";
chartSheet.getCell("A1").font = { bold: true, size: 14 };
const chartImageId = workbook.addImage({
  filename: chartImagePath,
  extension: "png",
});
chartSheet.addImage(chartImageId, {
  tl: { col: 0, row: 2 },
  ext: { width: 980, height: 543 },
});
chartSheet.getCell("A32").value = "Julho 2026: Sentix -7.5 => PMI 50.1; Sentix -13.4 => PMI 48.9.";
chartSheet.getCell("A32").font = { bold: true };

const rawSheet = workbook.addWorksheet("Data");
setColumns(rawSheet, [
  ["Date", "date", 14],
  ["PMI Composite", "pmi", 16],
  ["Sentix", "sentix", 12],
  ["Note", "note", 46],
]);
for (const row of data) {
  rawSheet.addRow({ date: excelDate(row.date), pmi: row.pmi, sentix: row.sentix, note: row.note });
}
rawSheet.getColumn(1).numFmt = "mmm-yy";
rawSheet.getColumn(2).numFmt = "0.0";
rawSheet.getColumn(3).numFmt = "0.0";
rawSheet.autoFilter = "A1:C1";

await workbook.xlsx.writeFile(outputPath);

console.log(JSON.stringify({
  outputPath,
  alpha: model.alpha,
  beta: model.beta,
  r2: model.r2,
  rmseInSample: model.rmse,
  rmseOutOfSample: oosRmse,
  scenarios,
}, null, 2));
