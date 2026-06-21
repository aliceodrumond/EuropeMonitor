"use client";

import { useEffect, useMemo, useState } from "react";

type TabId = "activity" | "inflation" | "speakers";
type AxisSide = "left" | "right";
type WindowKey = "all" | "10y" | "5y" | "2y";

type SeriesRow = {
  date: string;
  chart_id: string;
  series_id: string;
  series_name: string;
  country: string;
  value: number;
  axis: AxisSide;
  unit: string;
  source: string;
  source_url: string;
};

type SpeakerRow = {
  date: string;
  member: string;
  position: string;
  country: string;
  event_type: string;
  policy_comments: string;
  bias: "hawkish" | "dovish" | "neutral";
  tags: string;
};

type Metadata = {
  last_updated?: string;
  data_mode?: string;
  generated_by?: string;
};

type ChartDefinition = {
  id: string;
  tab: Exclude<TabId, "speakers">;
  title: string;
  kicker: string;
  yLeftLabel: string;
  yRightLabel?: string;
  wide?: boolean;
  seriesOrder?: string[];
};

type ChartSeries = {
  id: string;
  name: string;
  country: string;
  axis: AxisSide;
  unit: string;
  source: string;
  sourceUrl: string;
  color: string;
  points: Array<{ date: string; value: number; time: number }>;
};

type HoverPoint = {
  seriesId: string;
  name: string;
  value: number;
  unit: string;
  color: string;
  x: number;
  y: number;
};

type HoverState = {
  date: string;
  x: number;
  y: number;
  points: HoverPoint[];
};

const tabs: Array<{ id: TabId; label: string }> = [
  { id: "activity", label: "Activity Monitor" },
  { id: "inflation", label: "Inflation Monitor" },
  { id: "speakers", label: "ECB Speakers" },
];

const charts: ChartDefinition[] = [
  {
    id: "pmi_composite",
    tab: "activity",
    title: "PMI Composite",
    kicker: "Activity",
    yLeftLabel: "Index",
    wide: true,
    seriesOrder: ["pmi_ea", "pmi_de", "pmi_fr", "pmi_es", "pmi_uk", "pmi_it"],
  },
  {
    id: "pmi_manufacturing",
    tab: "activity",
    title: "PMI Manufacturing",
    kicker: "Activity",
    yLeftLabel: "Index",
    wide: true,
    seriesOrder: [
      "pmi_mfg_ea",
      "pmi_mfg_de",
      "pmi_mfg_fr",
      "pmi_mfg_es",
      "pmi_mfg_uk",
      "pmi_mfg_it",
    ],
  },
  {
    id: "pmi_services",
    tab: "activity",
    title: "PMI Services",
    kicker: "Activity",
    yLeftLabel: "Index",
    wide: true,
    seriesOrder: [
      "pmi_srv_ea",
      "pmi_srv_de",
      "pmi_srv_fr",
      "pmi_srv_es",
      "pmi_srv_uk",
      "pmi_srv_it",
    ],
  },
  {
    id: "sentix_pmi",
    tab: "activity",
    title: "Sentix vs PMI Composite",
    kicker: "Sentiment",
    yLeftLabel: "PMI",
    yRightLabel: "Sentix",
    wide: true,
    seriesOrder: ["pmi_ea_sentix", "sentix_ea"],
  },
  {
    id: "weekly_activity",
    tab: "activity",
    title: "Weekly Activity Index",
    kicker: "High frequency",
    yLeftLabel: "z-score",
  },
  {
    id: "toll_mileage",
    tab: "activity",
    title: "Toll Mileage",
    kicker: "Mobility",
    yLeftLabel: "Index",
  },
  {
    id: "financial_conditions",
    tab: "activity",
    title: "Financial Conditions",
    kicker: "Markets",
    yLeftLabel: "z-score",
  },
  {
    id: "gdp",
    tab: "activity",
    title: "GDP",
    kicker: "National accounts",
    yLeftLabel: "% y/y",
  },
  {
    id: "expected_selling_prices",
    tab: "inflation",
    title: "Expected Selling Prices",
    kicker: "Price pressures",
    yLeftLabel: "Balance",
    wide: true,
  },
  {
    id: "wage_tracker",
    tab: "inflation",
    title: "Wage Tracker",
    kicker: "Wages",
    yLeftLabel: "% y/y",
    wide: true,
  },
  {
    id: "regional_inflation",
    tab: "inflation",
    title: "Regional Inflation",
    kicker: "Countries",
    yLeftLabel: "% y/y",
    wide: true,
    seriesOrder: ["hicp_de", "hicp_fr", "hicp_it", "hicp_es"],
  },
  {
    id: "hicp_headline_core",
    tab: "inflation",
    title: "HICP",
    kicker: "Headline and core",
    yLeftLabel: "% y/y",
  },
  {
    id: "hicp_components",
    tab: "inflation",
    title: "HICP core goods and services",
    kicker: "Components",
    yLeftLabel: "% y/y",
  },
];

const palette = [
  "#204f86",
  "#c47a20",
  "#11675f",
  "#a83f39",
  "#3f7f52",
  "#6c5f8d",
  "#111111",
  "#8c7b57",
];

const windows: Array<{ key: WindowKey; label: string; years?: number }> = [
  { key: "all", label: "All" },
  { key: "10y", label: "10Y", years: 10 },
  { key: "5y", label: "5Y", years: 5 },
  { key: "2y", label: "2Y", years: 2 },
];

export default function Home() {
  const [activeTab, setActiveTab] = useState<TabId>("activity");
  const [seriesRows, setSeriesRows] = useState<SeriesRow[]>([]);
  const [speakers, setSpeakers] = useState<SpeakerRow[]>([]);
  const [metadata, setMetadata] = useState<Metadata>({});
  const [loadState, setLoadState] = useState("Loading data");

  useEffect(() => {
    let cancelled = false;

    async function loadData() {
      const [activityText, inflationText, speakersText, metadataResponse] =
        await Promise.all([
          fetchText("/data/activity_series.csv"),
          fetchText("/data/inflation_series.csv"),
          fetchText("/data/ecb_speakers.csv"),
          fetch("/data/metadata.json", { cache: "no-store" }),
        ]);

      if (cancelled) {
        return;
      }

      const nextSeries = [
        ...parseSeriesCsv(activityText),
        ...parseSeriesCsv(inflationText),
      ];

      setSeriesRows(nextSeries);
      setSpeakers(parseSpeakersCsv(speakersText));
      setMetadata(metadataResponse.ok ? await metadataResponse.json() : {});
      setLoadState("Data loaded");
    }

    loadData().catch(() => {
      if (!cancelled) {
        setLoadState("Data unavailable");
      }
    });

    return () => {
      cancelled = true;
    };
  }, []);

  const activeCharts = useMemo(
    () => charts.filter((chart) => chart.tab === activeTab),
    [activeTab],
  );

  const totalSeries = useMemo(
    () => new Set(seriesRows.map((row) => row.series_id)).size,
    [seriesRows],
  );

  return (
    <main className="shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">Europe Macro Monitor</p>
        </div>
        <div className="status-strip" aria-label="Data status">
          <span className="status-pill">
            Updated: {metadata.last_updated ?? "pending"}
          </span>
          <span className="status-pill">{loadState}</span>
          <span className="status-pill">{totalSeries} series</span>
        </div>
      </header>

      <nav className="tabs" aria-label="Sections">
        {tabs.map((tab) => (
          <button
            className="tab"
            data-active={activeTab === tab.id}
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            type="button"
          >
            {tab.label}
          </button>
        ))}
      </nav>

      {activeTab === "speakers" ? (
        <SpeakerTable speakers={speakers} />
      ) : (
        <section className="dashboard-grid">
          {activeCharts.map((chart) => (
            <TimeSeriesChart
              definition={chart}
              key={chart.id}
              rows={seriesRows.filter((row) => row.chart_id === chart.id)}
            />
          ))}
        </section>
      )}

      <p className="footer-note">
        Data mode: {metadata.data_mode ?? "initial mock"}. Data contract:
        CSVs in public/data.
      </p>
    </main>
  );
}

function TimeSeriesChart({
  definition,
  rows,
}: {
  definition: ChartDefinition;
  rows: SeriesRow[];
}) {
  const [windowKey, setWindowKey] = useState<WindowKey>("all");
  const [hiddenSeries, setHiddenSeries] = useState<Set<string>>(
    () => new Set(defaultHiddenSeries(definition)),
  );
  const [hover, setHover] = useState<HoverState | null>(null);

  const series = useMemo(() => buildSeries(rows, definition), [definition, rows]);
  const selectedWindow = windows.find((item) => item.key === windowKey);

  const filteredSeries = useMemo(() => {
    const allTimes = series.flatMap((item) => item.points.map((point) => point.time));
    if (!allTimes.length || !selectedWindow?.years) {
      return series;
    }

    const maxTime = Math.max(...allTimes);
    const minTime = addYears(maxTime, -selectedWindow.years);

    return series.map((item) => ({
      ...item,
      points: item.points.filter((point) => point.time >= minTime),
    }));
  }, [selectedWindow, series]);

  const activeSeries = filteredSeries.filter((item) => !hiddenSeries.has(item.id));
  const chartModel = useMemo(() => buildChartModel(activeSeries), [activeSeries]);

  function toggleSeries(seriesId: string) {
    setHiddenSeries((current) => {
      const next = new Set(current);
      if (next.has(seriesId)) {
        next.delete(seriesId);
      } else {
        next.add(seriesId);
      }
      return next;
    });
  }

  if (!series.length) {
    return (
      <article className="chart-panel" data-wide={definition.wide}>
        <div className="panel-head">
          <div>
            <p className="panel-kicker">{definition.kicker}</p>
            <h2 className="panel-title">{definition.title}</h2>
          </div>
        </div>
        <div className="empty-state">Waiting for data</div>
      </article>
    );
  }

  return (
    <article className="chart-panel" data-wide={definition.wide}>
      <div className="panel-head">
        <div>
          <p className="panel-kicker">{definition.kicker}</p>
          <h2 className="panel-title">{definition.title}</h2>
        </div>
        <div className="window-controls" aria-label="Time window">
          {windows.map((item) => (
            <button
              data-active={item.key === windowKey}
              key={item.key}
              onClick={() => setWindowKey(item.key)}
              type="button"
            >
              {item.label}
            </button>
          ))}
        </div>
      </div>

      <div className="legend" aria-label="Sections">
        {series.map((item) => (
          <button
            className="legend-button"
            data-hidden={hiddenSeries.has(item.id)}
            key={item.id}
            onClick={() => toggleSeries(item.id)}
            type="button"
          >
            <span className="legend-swatch" style={{ background: item.color }} />
            {item.name}
          </button>
        ))}
      </div>

      <div className="chart-frame">
        <svg
          aria-label={definition.title}
          className="chart-svg"
          onMouseLeave={() => setHover(null)}
          onMouseMove={(event) => {
            if (!chartModel) {
              return;
            }
            const rect = event.currentTarget.getBoundingClientRect();
            const svgX = ((event.clientX - rect.left) / rect.width) * chartModel.width;
            const svgY = ((event.clientY - rect.top) / rect.height) * chartModel.height;
            setHover(buildHoverState(chartModel, svgX, svgY));
          }}
          role="img"
          viewBox={`0 0 ${chartModel?.width ?? 920} ${chartModel?.height ?? 380}`}
        >
          {chartModel ? (
            <ChartSvgContent
              definition={definition}
              hover={hover}
              model={chartModel}
            />
          ) : null}
        </svg>

        {hover ? (
          <div
            className="tooltip"
            style={{
              left: `${(hover.x / (chartModel?.width ?? 920)) * 100}%`,
              top: `${(hover.y / (chartModel?.height ?? 380)) * 100}%`,
            }}
          >
            <div className="tooltip-date">{formatDateLabel(hover.date)}</div>
            {hover.points.map((point) => (
              <div className="tooltip-row" key={point.seriesId}>
                <span
                  className="tooltip-swatch"
                  style={{ background: point.color }}
                />
                <span>{point.name}</span>
                <strong>{formatValue(point.value, point.unit)}</strong>
              </div>
            ))}
          </div>
        ) : null}
      </div>
      <p className="source-note">
        Source: <SourceLinks series={series} />
      </p>
    </article>
  );
}

function SourceLinks({ series }: { series: ChartSeries[] }) {
  const sources = uniqueSources(series);

  return (
    <>
      {sources.map((source, index) => (
        <span key={`${source.label}-${source.url}`}>
          {index > 0 ? "; " : ""}
          {source.url ? (
            <a href={source.url} rel="noreferrer" target="_blank">
              {source.label}
            </a>
          ) : (
            source.label
          )}
        </span>
      ))}
    </>
  );
}

function ChartSvgContent({
  definition,
  hover,
  model,
}: {
  definition: ChartDefinition;
  hover: HoverState | null;
  model: ReturnType<typeof buildChartModel>;
}) {
  if (!model) {
    return null;
  }

  const {
    height,
    innerHeight,
    innerWidth,
    leftTicks,
    margin,
    rightTicks,
    scaleX,
    scaleY,
    series,
    width,
    xTicks,
  } = model;

  return (
    <>
      <rect
        fill="transparent"
        height={innerHeight}
        width={innerWidth}
        x={margin.left}
        y={margin.top}
      />
      {leftTicks.map((tick) => {
        const y = scaleY(tick, "left");
        return (
          <g key={`left-${tick}`}>
            <line
              className="grid-line"
              x1={margin.left}
              x2={width - margin.right}
              y1={y}
              y2={y}
            />
            <text
              className="tick-label"
              textAnchor="end"
              x={margin.left - 10}
              y={y + 4}
            >
              {formatNumber(tick)}
            </text>
          </g>
        );
      })}
      {rightTicks.map((tick) => {
        const y = scaleY(tick, "right");
        return (
          <text
            className="tick-label"
            key={`right-${tick}`}
            textAnchor="start"
            x={width - margin.right + 10}
            y={y + 4}
          >
            {formatNumber(tick)}
          </text>
        );
      })}
      {model.leftDomain.min < 0 && model.leftDomain.max > 0 ? (
        <line
          className="zero-line"
          x1={margin.left}
          x2={width - margin.right}
          y1={scaleY(0, "left")}
          y2={scaleY(0, "left")}
        />
      ) : null}
      {xTicks.map((tick) => {
        const x = scaleX(tick);
        return (
          <g key={`x-${tick}`}>
            <line
              className="grid-line"
              x1={x}
              x2={x}
              y1={margin.top}
              y2={height - margin.bottom}
            />
            <text
              className="tick-label"
              textAnchor="middle"
              x={x}
              y={height - margin.bottom + 24}
            >
              {formatYear(tick)}
            </text>
          </g>
        );
      })}
      <line
        className="axis-line"
        x1={margin.left}
        x2={margin.left}
        y1={margin.top}
        y2={height - margin.bottom}
      />
      <line
        className="axis-line"
        x1={margin.left}
        x2={width - margin.right}
        y1={height - margin.bottom}
        y2={height - margin.bottom}
      />
      <text
        className="axis-label"
        textAnchor="start"
        x={margin.left}
        y={24}
      >
        {definition.yLeftLabel}
      </text>
      {definition.yRightLabel ? (
        <text
          className="axis-label"
          textAnchor="end"
          x={width - margin.right}
          y={24}
        >
          {definition.yRightLabel}
        </text>
      ) : null}
      {series.map((item) => (
        <path
          className="series-path"
          d={pathForSeries(item, scaleX, scaleY)}
          key={item.id}
          stroke={item.color}
        />
      ))}
      {hover ? (
        <>
          <line
            className="hover-line"
            x1={hover.x}
            x2={hover.x}
            y1={margin.top}
            y2={height - margin.bottom}
          />
          {hover.points.map((point) => (
            <circle
              className="hover-dot"
              cx={point.x}
              cy={point.y}
              fill={point.color}
              key={point.seriesId}
              r={4}
            />
          ))}
        </>
      ) : null}
    </>
  );
}

function SpeakerTable({ speakers }: { speakers: SpeakerRow[] }) {
  const [query, setQuery] = useState("");
  const normalizedQuery = normalize(query);

  const filteredSpeakers = speakers.filter((speaker) => {
    if (!normalizedQuery) {
      return true;
    }
    return normalize(Object.values(speaker).join(" ")).includes(normalizedQuery);
  });

  return (
    <section className="speaker-panel">
      <div className="table-toolbar">
        <div>
          <p className="panel-kicker">Communication</p>
          <h2 className="panel-title">ECB Speakers</h2>
        </div>
        <input
          aria-label="Buscar em ECB Speakers"
          className="search-input"
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search member, country or comment"
          value={query}
        />
      </div>
      <div className="speaker-table-wrap">
        <table className="speaker-table">
          <thead>
            <tr>
              <th>Date</th>
              <th>Member</th>
              <th>Position</th>
              <th>Country</th>
              <th>Policy Comments</th>
              <th>Bias</th>
            </tr>
          </thead>
          <tbody>
            {filteredSpeakers.map((speaker, index) => (
              <tr key={`${speaker.date}-${speaker.member}-${index}`}>
                <td>{formatFullDateLabel(speaker.date)}</td>
                <td>{speaker.member}</td>
                <td>{speaker.position}</td>
                <td>{speaker.country}</td>
                <td>{speaker.policy_comments}</td>
                <td>
                  <span className={`bias bias-${speaker.bias}`}>
                    {speaker.bias}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

async function fetchText(path: string) {
  const response = await fetch(path, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`Could not load ${path}`);
  }
  return response.text();
}

function parseSeriesCsv(text: string): SeriesRow[] {
  return parseCsv(text)
    .map((row) => ({
      date: row.date ?? "",
      chart_id: row.chart_id ?? "",
      series_id: row.series_id ?? "",
      series_name: row.series_name ?? "",
      country: row.country ?? "",
      value: Number(row.value ?? "NaN"),
      axis: row.axis === "right" ? "right" : "left",
      unit: row.unit ?? "",
      source: row.source ?? "",
      source_url: row.source_url ?? "",
    }))
    .filter((row) => row.date && row.chart_id && Number.isFinite(row.value));
}

function parseSpeakersCsv(text: string): SpeakerRow[] {
  return parseCsv(text).map((row) => ({
    date: row.date ?? "",
    member: row.member ?? "",
    position: row.position ?? "",
    country: row.country ?? "",
    event_type: row.event_type ?? "",
    policy_comments: row.policy_comments ?? "",
    bias:
      row.bias === "hawkish" || row.bias === "dovish" ? row.bias : "neutral",
    tags: row.tags ?? "",
  }));
}

function parseCsv(text: string): Array<Record<string, string>> {
  const rows: string[][] = [];
  let field = "";
  let row: string[] = [];
  let quoted = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const next = text[index + 1];

    if (quoted) {
      if (char === '"' && next === '"') {
        field += '"';
        index += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        field += char;
      }
      continue;
    }

    if (char === '"') {
      quoted = true;
    } else if (char === ",") {
      row.push(field);
      field = "";
    } else if (char === "\n") {
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else if (char !== "\r") {
      field += char;
    }
  }

  if (field || row.length) {
    row.push(field);
    rows.push(row);
  }

  const headers = rows.shift() ?? [];
  return rows
    .filter((items) => items.some((item) => item.length > 0))
    .map((items) =>
      Object.fromEntries(headers.map((header, index) => [header, items[index] ?? ""])),
    );
}

function buildSeries(rows: SeriesRow[], definition: ChartDefinition): ChartSeries[] {
  const seriesMap = new Map<string, ChartSeries>();

  rows.forEach((row) => {
    if (!seriesMap.has(row.series_id)) {
      seriesMap.set(row.series_id, {
        id: row.series_id,
        name: row.series_name,
        country: row.country,
        axis: row.axis,
        unit: row.unit,
        source: row.source,
        sourceUrl: row.source_url,
        color: palette[seriesMap.size % palette.length],
        points: [],
      });
    }

    seriesMap.get(row.series_id)?.points.push({
      date: row.date,
      value: row.value,
      time: parseTime(row.date),
    });
  });

  return [...seriesMap.values()]
    .map((item) => ({
      ...item,
      points: item.points.sort((a, b) => a.time - b.time),
    }))
    .sort((a, b) => {
      const order = definition.seriesOrder ?? [];
      const aIndex = order.indexOf(a.id);
      const bIndex = order.indexOf(b.id);
      if (aIndex === -1 && bIndex === -1) {
        return a.name.localeCompare(b.name);
      }
      if (aIndex === -1) {
        return 1;
      }
      if (bIndex === -1) {
        return -1;
      }
      return aIndex - bIndex;
    })
    .map((item, index) => ({ ...item, color: palette[index % palette.length] }));
}

function buildChartModel(series: ChartSeries[]) {
  const width = 920;
  const height = 390;
  const margin = { top: 36, right: 58, bottom: 48, left: 54 };
  const innerWidth = width - margin.left - margin.right;
  const innerHeight = height - margin.top - margin.bottom;
  const allPoints = series.flatMap((item) => item.points);

  if (!series.length || !allPoints.length) {
    return null;
  }

  const timeDomain = getTimeDomain(allPoints.map((point) => point.time));
  const leftPoints = series
    .filter((item) => item.axis !== "right")
    .flatMap((item) => item.points.map((point) => point.value));
  const rightPoints = series
    .filter((item) => item.axis === "right")
    .flatMap((item) => item.points.map((point) => point.value));
  const leftDomain = getValueDomain(leftPoints.length ? leftPoints : rightPoints);
  const rightDomain = rightPoints.length ? getValueDomain(rightPoints) : leftDomain;

  const scaleX = (time: number) =>
    margin.left +
    ((time - timeDomain.min) / (timeDomain.max - timeDomain.min)) * innerWidth;

  const scaleY = (value: number, axis: AxisSide) => {
    const domain = axis === "right" ? rightDomain : leftDomain;
    return (
      margin.top +
      (1 - (value - domain.min) / (domain.max - domain.min)) * innerHeight
    );
  };

  return {
    height,
    innerHeight,
    innerWidth,
    leftDomain,
    leftTicks: makeTicks(leftDomain.min, leftDomain.max, 5),
    margin,
    rightDomain,
    rightTicks: rightPoints.length ? makeTicks(rightDomain.min, rightDomain.max, 5) : [],
    scaleX,
    scaleY,
    series,
    timeDomain,
    width,
    xTicks: makeTimeTicks(timeDomain.min, timeDomain.max, 7),
  };
}

function buildHoverState(
  model: NonNullable<ReturnType<typeof buildChartModel>>,
  svgX: number,
  svgY: number,
): HoverState | null {
  const { height, margin, scaleX, scaleY, series, timeDomain, width } = model;

  if (
    svgX < margin.left ||
    svgX > width - margin.right ||
    svgY < margin.top ||
    svgY > height - margin.bottom
  ) {
    return null;
  }

  const targetTime =
    timeDomain.min +
    ((svgX - margin.left) / (width - margin.left - margin.right)) *
      (timeDomain.max - timeDomain.min);

  const points = series
    .map((item) => {
      if (!item.points.length) {
        return null;
      }

      const point = nearestPoint(item.points, targetTime);
      if (!point) {
        return null;
      }
      return {
        color: item.color,
        date: point.date,
        name: item.name,
        seriesId: item.id,
        time: point.time,
        unit: item.unit,
        value: point.value,
        x: scaleX(point.time),
        y: scaleY(point.value, item.axis),
      };
    })
    .filter(Boolean) as Array<HoverPoint & { date: string; time: number }>;

  if (!points.length) {
    return null;
  }

  const anchor = points.reduce((closest, point) =>
    Math.abs(point.time - targetTime) < Math.abs(closest.time - targetTime)
      ? point
      : closest,
  );

  return {
    date: anchor.date,
    points: points.map((point) => ({
      color: point.color,
      name: point.name,
      seriesId: point.seriesId,
      unit: point.unit,
      value: point.value,
      x: point.x,
      y: point.y,
    })),
    x: anchor.x,
    y: Math.min(...points.map((point) => point.y)),
  };
}

function pathForSeries(
  series: ChartSeries,
  scaleX: (time: number) => number,
  scaleY: (value: number, axis: AxisSide) => number,
) {
  return series.points
    .map((point, index) => {
      const command = index === 0 ? "M" : "L";
      return `${command}${scaleX(point.time).toFixed(2)},${scaleY(point.value, series.axis).toFixed(2)}`;
    })
    .join(" ");
}

function nearestPoint(
  points: Array<{ date: string; value: number; time: number }>,
  targetTime: number,
) {
  return points.reduce((closest, point) =>
    Math.abs(point.time - targetTime) < Math.abs(closest.time - targetTime)
      ? point
      : closest,
  );
}

function getTimeDomain(times: number[]) {
  const min = Math.min(...times);
  const max = Math.max(...times);
  if (min === max) {
    return { min: addYears(min, -1), max: addYears(max, 1) };
  }
  return { min, max };
}

function getValueDomain(values: number[]) {
  const min = Math.min(...values);
  const max = Math.max(...values);
  if (min === max) {
    return { min: min - 1, max: max + 1 };
  }
  const padding = (max - min) * 0.12;
  return { min: min - padding, max: max + padding };
}

function makeTicks(min: number, max: number, count: number) {
  const step = (max - min) / Math.max(1, count - 1);
  return Array.from({ length: count }, (_, index) => min + step * index);
}

function makeTimeTicks(min: number, max: number, count: number) {
  const step = (max - min) / Math.max(1, count - 1);
  return Array.from({ length: count }, (_, index) => min + step * index);
}

function addYears(time: number, years: number) {
  const date = new Date(time);
  date.setFullYear(date.getFullYear() + years);
  return date.getTime();
}

function parseTime(date: string) {
  return new Date(`${date}T00:00:00`).getTime();
}

function formatYear(time: number) {
  return new Date(time).getFullYear().toString().slice(2);
}

function defaultHiddenSeries(definition: ChartDefinition) {
  if (!definition.id.startsWith("pmi_")) {
    return [];
  }

  return (definition.seriesOrder ?? []).filter((seriesId) => !seriesId.endsWith("_ea"));
}

function uniqueSources(series: ChartSeries[]) {
  const sourceMap = new Map<string, { label: string; url: string }>();

  series.forEach((item) => {
    const label = item.source || "Unspecified source";
    const key = `${label}|${item.sourceUrl}`;
    if (!sourceMap.has(key)) {
      sourceMap.set(key, { label, url: item.sourceUrl });
    }
  });

  return [...sourceMap.values()];
}

function formatDateLabel(date: string) {
  if (!date) {
    return "";
  }
  return new Intl.DateTimeFormat("en-US", {
    month: "2-digit",
    year: "numeric",
  }).format(new Date(`${date}T00:00:00`));
}

function formatFullDateLabel(date: string) {
  if (!date) {
    return "";
  }
  return new Intl.DateTimeFormat("en-US", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  }).format(new Date(`${date}T00:00:00`));
}

function formatValue(value: number, unit: string) {
  const formatted = formatNumber(value);
  return unit === "% y/y" ? `${formatted}%` : formatted;
}

function formatNumber(value: number) {
  const abs = Math.abs(value);
  const digits = abs >= 100 ? 0 : abs >= 10 ? 1 : 2;
  return value.toLocaleString("en-US", {
    maximumFractionDigits: digits,
    minimumFractionDigits: digits,
  });
}

function normalize(value: string) {
  return value
    .toLocaleLowerCase("en-US")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "");
}
