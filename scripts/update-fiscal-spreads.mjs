import { mkdir, readFile, writeFile } from "node:fs/promises";

const countries = [
  ["FR", "France"],
  ["IT", "Italy"],
  ["ES", "Spain"],
  ["PT", "Portugal"],
  ["EL", "Greece"],
  ["UK", "United Kingdom"],
];
const geos = ["DE", ...countries.map(([code]) => code)];
const query = geos.map((code) => `geo=${code}`).join("&");
const sourceUrl = "https://ec.europa.eu/eurostat/databrowser/view/irt_lt_mcby_m/default/table";
const apiUrl = `https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/irt_lt_mcby_m?lang=en&${query}&sinceTimePeriod=1990-01`;

const data = process.env.EUROSTAT_FISCAL_JSON
  ? JSON.parse(await readFile(process.env.EUROSTAT_FISCAL_JSON, "utf8"))
  : await fetch(apiUrl).then((response) => {
      if (!response.ok) throw new Error(`Eurostat request failed: ${response.status}`);
      return response.json();
    });
const times = Object.keys(data.dimension.time.category.index);
const geoIndex = data.dimension.geo.category.index;
const timeCount = times.length;
const valueAt = (geo, timeIndex) => data.value?.[geoIndex[geo] * timeCount + timeIndex];

const rows = ["date,country,country_name,spread_bp,source,source_url"];
for (const [code, name] of countries) {
  times.forEach((period, timeIndex) => {
    const countryYield = valueAt(code, timeIndex);
    const bundYield = valueAt("DE", timeIndex);
    if (!Number.isFinite(countryYield) || !Number.isFinite(bundYield)) return;
    const spread = Math.round((countryYield - bundYield) * 1000) / 10;
    rows.push(`${period}-01,${code},${name},${spread},Eurostat / ECB,${sourceUrl}`);
  });
}

await mkdir("public/data", { recursive: true });
await writeFile("public/data/fiscal_spreads.csv", `${rows.join("\n")}\n`);
console.log(`Wrote ${rows.length - 1} fiscal spread observations.`);
