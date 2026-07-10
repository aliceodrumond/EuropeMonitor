"use client";

import { useEffect, useMemo, useState } from "react";

type TabId = "activity" | "inflation" | "other-inflation" | "scenario" | "speakers";
type AxisSide = "left" | "right";
type WindowKey = "all" | "10y" | "5y" | "2y" | "1y" | "6m";
type SeasonalSource = "ecb" | "legacy";

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
  frequency: string;
  source_note: string;
};

type SpeakerRow = {
  date: string;
  member: string;
  position: string;
  country: string;
  event_type: string;
  policy_comments: string;
  bias: "hawkish" | "mildly hawkish" | "dovish" | "mildly dovish" | "neutral";
  stance_change: string;
  tags: string;
  source_url: string;
};

type Metadata = {
  last_updated?: string;
  data_mode?: string;
  generated_by?: string;
  activity_last_new?: LastNewObservation;
  inflation_last_new?: LastNewObservation;
};

type ScenarioTrackerData = {
  snapshots?: ScenarioSnapshot[];
};

type ScenarioSnapshot = {
  id: string;
  date: string;
  trigger: string;
  coreView: string;
  confidence: string;
  activity: string[];
  inflation: string[];
  rates: string[];
  risks: string[];
};

type LastNewObservation = {
  date?: string;
  description?: string;
};

type ChartDefinition = {
  id: string;
  tab: Exclude<TabId, "speakers">;
  title: string;
  kicker: string;
  yLeftLabel: string;
  chartType?: "time" | "seasonality";
  yRightLabel?: string;
  fixedDomains?: Partial<Record<AxisSide, { min: number; max: number }>>;
  defaultWindow?: WindowKey;
  flexibleAxisControls?: boolean;
  invertRightAxis?: boolean;
  startDate?: string;
  wide?: boolean;
  seriesOrder?: string[];
  seasonalToggle?: boolean;
};

type ChartSeries = {
  id: string;
  name: string;
  country: string;
  axis: AxisSide;
  unit: string;
  source: string;
  sourceUrl: string;
  frequency: string;
  sourceNote: string;
  color: string;
  dashArray?: string;
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
  { id: "speakers", label: "ECB Speakers" },
  { id: "scenario", label: "Scenario Tracker" },
  { id: "activity", label: "Activity Monitor" },
  { id: "inflation", label: "Inflation Monitor" },
  { id: "other-inflation", label: "Other - Inflation Monitor" },
];

const charts: ChartDefinition[] = [
  {
    id: "scenario_eurusd_real_rates",
    tab: "scenario",
    title: "EURUSD vs 2Y Real Rate Differential",
    kicker: "Market Check",
    yLeftLabel: "EURUSD",
    yRightLabel: "EA-US 2Y real rates, pp",
    fixedDomains: { right: { min: -2.5, max: 1.5 } },
    flexibleAxisControls: true,
    seriesOrder: ["eurusd", "real_2y_differential_ea_us"],
    defaultWindow: "2y",
    wide: true,
  },
  {
    id: "pmi_ea_aggregate",
    tab: "activity",
    title: "Eurozone PMIs",
    kicker: "Activity",
    yLeftLabel: "Index",
    seriesOrder: ["pmi_ea_aggregate", "pmi_mfg_ea_aggregate", "pmi_srv_ea_aggregate"],
    fixedDomains: { left: { min: 35, max: 65 } },
    defaultWindow: "10y",
  },
  {
    id: "pmi_gdp",
    tab: "activity",
    title: "PMI Composite vs GDP",
    kicker: "Growth",
    yLeftLabel: "PMI",
    yRightLabel: "% q/q SA",
    fixedDomains: { left: { min: 35, max: 65 }, right: { min: -2.5, max: 2.5 } },
    seriesOrder: ["pmi_ea_gdp", "gdp_qoq_sa_ea"],
    defaultWindow: "all",
  },
  {
    id: "pmi_composite",
    tab: "activity",
    title: "PMI Composite",
    kicker: "Activity",
    yLeftLabel: "Index",
    seriesOrder: ["pmi_ea", "pmi_de", "pmi_fr", "pmi_es", "pmi_uk", "pmi_it"],
    defaultWindow: "10y",
  },
  {
    id: "pmi_manufacturing",
    tab: "activity",
    title: "PMI Manufacturing",
    kicker: "Activity",
    yLeftLabel: "Index",
    seriesOrder: [
      "pmi_mfg_ea",
      "pmi_mfg_de",
      "pmi_mfg_fr",
      "pmi_mfg_es",
      "pmi_mfg_uk",
      "pmi_mfg_it",
    ],
    defaultWindow: "10y",
  },
  {
    id: "pmi_services",
    tab: "activity",
    title: "PMI Services",
    kicker: "Activity",
    yLeftLabel: "Index",
    seriesOrder: [
      "pmi_srv_ea",
      "pmi_srv_de",
      "pmi_srv_fr",
      "pmi_srv_es",
      "pmi_srv_uk",
      "pmi_srv_it",
    ],
    defaultWindow: "10y",
  },
  {
    id: "bls_credit_standards",
    tab: "activity",
    title: "ECB BLS: Credit standards",
    kicker: "ECB Lending Survey",
    yLeftLabel: "GDP q/q",
    yRightLabel: "Net %",
    fixedDomains: { left: { min: -3, max: 3 }, right: { min: 30, max: -20 } },
    seriesOrder: [
      "gdp_qoq_sa_bls_standards",
      "bls_standards_corporate_ea",
      "bls_standards_consumer_ea",
    ],
    defaultWindow: "all",
    startDate: "2005-01-01",
  },
  {
    id: "bls_loan_demand",
    tab: "activity",
    title: "ECB BLS: Loan demand",
    kicker: "ECB Lending Survey",
    yLeftLabel: "GDP q/q",
    yRightLabel: "Net %",
    fixedDomains: { left: { min: -3, max: 3 }, right: { min: -50, max: 50 } },
    seriesOrder: [
      "gdp_qoq_sa_bls_demand",
      "bls_demand_consumer_ea",
      "bls_demand_corporate_ea",
    ],
    defaultWindow: "all",
    startDate: "2005-01-01",
  },
  {
    id: "bls_credit_factors",
    tab: "activity",
    title: "Factors affecting credit standards in the past 3m",
    kicker: "ECB Lending Survey",
    yLeftLabel: "Net %",
    fixedDomains: { left: { min: -10, max: 15 } },
    seriesOrder: [
      "bls_factor_capital_ea",
      "bls_factor_market_financing_ea",
      "bls_factor_liquidity_ea",
      "bls_factor_econ_outlook_ea",
      "bls_factor_industry_firm_ea",
      "bls_factor_collateral_ea",
    ],
    defaultWindow: "2y",
  },
  {
    id: "sentix_pmi",
    tab: "activity",
    title: "Sentix vs PMI Composite",
    kicker: "Sentiment",
    yLeftLabel: "PMI",
    yRightLabel: "Sentix",
    fixedDomains: { left: { min: 40, max: 64 }, right: { min: -55, max: 50 } },
    seriesOrder: ["pmi_ea_sentix", "sentix_ea"],
  },
  {
    id: "zew_sentiment",
    tab: "activity",
    title: "ZEW Indicator",
    kicker: "Sentiment",
    yLeftLabel: "Balance",
    seriesOrder: ["zew_de"],
  },
  {
    id: "ifo_headline",
    tab: "activity",
    title: "GE IFO",
    kicker: "Survey",
    yLeftLabel: "Index",
    fixedDomains: { left: { min: 70, max: 110 } },
    seriesOrder: [
      "ifo_business_climate_de",
      "ifo_current_assessment_de",
      "ifo_expectations_de",
    ],
    defaultWindow: "10y",
  },
  {
    id: "ifo_sectors",
    tab: "activity",
    title: "GE: IFO Climate by Sectors",
    kicker: "Survey",
    yLeftLabel: "Balance",
    fixedDomains: { left: { min: -50, max: 40 } },
    seriesOrder: [
      "ifo_mfg_climate_de",
      "ifo_retail_climate_de",
      "ifo_services_climate_de",
      "ifo_construction_climate_de",
    ],
    defaultWindow: "10y",
  },
  {
    id: "weekly_activity",
    tab: "activity",
    title: "Germany Weekly Activity Index",
    kicker: "High frequency",
    yLeftLabel: "%",
    defaultWindow: "2y",
  },
  {
    id: "toll_mileage",
    tab: "activity",
    title: "Toll Mileage",
    kicker: "Mobility",
    yLeftLabel: "Index",
    defaultWindow: "6m",
    seriesOrder: ["toll_de", "toll_de_daily"],
  },
  {
    id: "hicp_headline_rates",
    tab: "inflation",
    title: "HICP Headline",
    kicker: "Inflation",
    yLeftLabel: "%",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -2, max: 12 } },
    startDate: "2018-01-01",
    seasonalToggle: true,
    seriesOrder: ["hicp_headline_yoy_nsa", "hicp_headline_hoh_saar", "hicp_headline_qoq_saar", "hicp_headline_mom_saar", "hicp_headline_hoh_saar_legacy", "hicp_headline_qoq_saar_legacy", "hicp_headline_mom_saar_legacy"],
  },
  {
    id: "hicp_core_rates",
    tab: "inflation",
    title: "HICP Core ex-Energy, Food, Alcohol and Tobacco",
    kicker: "Inflation",
    yLeftLabel: "%",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -2, max: 8 } },
    startDate: "2018-01-01",
    seasonalToggle: true,
    seriesOrder: ["hicp_core_yoy_nsa", "hicp_core_hoh_saar", "hicp_core_qoq_saar", "hicp_core_mom_saar", "hicp_core_hoh_saar_legacy", "hicp_core_qoq_saar_legacy", "hicp_core_mom_saar_legacy"],
  },
  {
    id: "hicp_headline_seasonality",
    tab: "inflation",
    title: "HICP Headline Seasonality",
    kicker: "% MoM NSA",
    yLeftLabel: "% m/m NSA",
    chartType: "seasonality",
    seriesOrder: ["hicp_headline_mom_nsa_range_min", "hicp_headline_mom_nsa_range_max", "hicp_headline_mom_nsa_median", "hicp_headline_mom_nsa_2022", "hicp_headline_mom_nsa_2025", "hicp_headline_mom_nsa_2026"],
  },
  {
    id: "hicp_core_seasonality",
    tab: "inflation",
    title: "HICP Core Seasonality",
    kicker: "% MoM NSA",
    yLeftLabel: "% m/m NSA",
    chartType: "seasonality",
    seriesOrder: ["hicp_core_mom_nsa_range_min", "hicp_core_mom_nsa_range_max", "hicp_core_mom_nsa_median", "hicp_core_mom_nsa_2022", "hicp_core_mom_nsa_2025", "hicp_core_mom_nsa_2026"],
  },
  {
    id: "hicp_goods_rates",
    tab: "inflation",
    title: "HICP Non-Energy Industrial Goods",
    kicker: "Inflation",
    yLeftLabel: "%",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -3, max: 8 } },
    startDate: "2018-01-01",
    seasonalToggle: true,
    seriesOrder: ["hicp_goods_yoy_nsa", "hicp_goods_hoh_saar", "hicp_goods_qoq_saar", "hicp_goods_mom_saar", "hicp_goods_hoh_saar_legacy", "hicp_goods_qoq_saar_legacy", "hicp_goods_mom_saar_legacy"],
  },
  {
    id: "hicp_services_rates",
    tab: "inflation",
    title: "HICP Services",
    kicker: "Inflation",
    yLeftLabel: "%",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -1, max: 9 } },
    startDate: "2018-01-01",
    seasonalToggle: true,
    seriesOrder: ["hicp_services_yoy_nsa", "hicp_services_hoh_saar", "hicp_services_qoq_saar", "hicp_services_mom_saar", "hicp_services_hoh_saar_legacy", "hicp_services_qoq_saar_legacy", "hicp_services_mom_saar_legacy"],
  },
  {
    id: "hicp_energy_wage_sensitive",
    tab: "inflation",
    title: "HICPX Energy and Wage Sensitive",
    kicker: "ECB methodology",
    yLeftLabel: "% y/y",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -1, max: 10 } },
    startDate: "2018-01-01",
    seriesOrder: ["hicp_energy_sensitive_yoy_nsa", "hicp_wage_sensitive_yoy_nsa"],
  },
  {
    id: "hicp_goods_seasonality",
    tab: "inflation",
    title: "HICP Non-Energy Industrial Goods Seasonality",
    kicker: "% MoM NSA",
    yLeftLabel: "% m/m NSA",
    chartType: "seasonality",
    seriesOrder: ["core_goods_mom_nsa_range_min", "core_goods_mom_nsa_range_max", "core_goods_mom_nsa_median", "core_goods_mom_nsa_2022", "core_goods_mom_nsa_2025", "core_goods_mom_nsa_2026"],
  },
  {
    id: "hicp_services_seasonality",
    tab: "inflation",
    title: "HICP Services Seasonality",
    kicker: "% MoM NSA",
    yLeftLabel: "% m/m NSA",
    chartType: "seasonality",
    seriesOrder: ["core_services_mom_nsa_range_min", "core_services_mom_nsa_range_max", "core_services_mom_nsa_median", "core_services_mom_nsa_2022", "core_services_mom_nsa_2025", "core_services_mom_nsa_2026"],
  },
  {
    id: "hicp_services_ex_volatiles_rates",
    tab: "inflation",
    title: "HICP Services ex-Volatiles",
    kicker: "Inflation",
    yLeftLabel: "%",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -1, max: 9 } },
    startDate: "2018-01-01",
    seriesOrder: ["hicp_services_ex_volatiles_yoy_nsa", "hicp_services_ex_volatiles_qoq_saar", "hicp_services_ex_volatiles_mom_saar"],
  },
  {
    id: "hicp_services_ex_volatiles_seasonality",
    tab: "inflation",
    title: "HICP Services ex-Volatiles Seasonality",
    kicker: "% MoM NSA",
    yLeftLabel: "% m/m NSA",
    chartType: "seasonality",
    seriesOrder: ["hicp_services_ex_volatiles_mom_nsa_range_min", "hicp_services_ex_volatiles_mom_nsa_range_max", "hicp_services_ex_volatiles_mom_nsa_median", "hicp_services_ex_volatiles_mom_nsa_2022", "hicp_services_ex_volatiles_mom_nsa_2025", "hicp_services_ex_volatiles_mom_nsa_2026"],
  },
  {
    id: "ecb_pcci_3m_saar",
    tab: "inflation",
    title: "PCCI",
    kicker: "Underlying inflation",
    yLeftLabel: "% 3M SAAR",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -1, max: 8 } },
    startDate: "2018-01-01",
    seriesOrder: ["ecb_pcci_3m_saar"],
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
  {
    id: "expected_selling_prices",
    tab: "inflation",
    title: "Services HICP vs EC Services Survey",
    kicker: "Price pressures",
    yLeftLabel: "Survey balance",
    yRightLabel: "% y/y",
    fixedDomains: { left: { min: -15, max: 40 }, right: { min: -1, max: 7 } },
    seriesOrder: ["esp_services", "core_services_expected"],
  },
  {
    id: "wage_tracker",
    tab: "inflation",
    title: "Wage Tracker",
    kicker: "Wages",
    yLeftLabel: "% y/y",
  },
  {
    id: "ecb_ces_inflation_expectations",
    tab: "inflation",
    title: "ECB Consumer Inflation Expectations",
    kicker: "Expectations",
    yLeftLabel: "%",
    defaultWindow: "all",
    seriesOrder: ["ecb_ces_infl_exp_1y", "ecb_ces_infl_exp_3y", "ecb_ces_infl_exp_5y"],
  },
  {
    id: "swiss_cpi_headline_rates",
    tab: "other-inflation",
    title: "Switzerland CPI Headline",
    kicker: "Inflation",
    yLeftLabel: "%",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -2, max: 8 } },
    startDate: "2018-01-01",
    seriesOrder: ["swiss_cpi_headline_yoy_nsa", "swiss_cpi_headline_hoh_saar", "swiss_cpi_headline_qoq_saar", "swiss_cpi_headline_mom_saar"],
  },
  {
    id: "swiss_cpi_core_rates",
    tab: "other-inflation",
    title: "Switzerland CPI Core",
    kicker: "Inflation",
    yLeftLabel: "%",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -2, max: 6 } },
    startDate: "2018-01-01",
    seriesOrder: ["swiss_cpi_core_yoy_nsa", "swiss_cpi_core_hoh_saar", "swiss_cpi_core_qoq_saar", "swiss_cpi_core_mom_saar"],
  },
  {
    id: "swiss_cpi_headline_seasonality",
    tab: "other-inflation",
    title: "Switzerland CPI Headline Seasonality",
    kicker: "% MoM NSA",
    yLeftLabel: "% m/m NSA",
    chartType: "seasonality",
    seriesOrder: ["swiss_cpi_headline_mom_nsa_range_min", "swiss_cpi_headline_mom_nsa_range_max", "swiss_cpi_headline_mom_nsa_median", "swiss_cpi_headline_mom_nsa_2022", "swiss_cpi_headline_mom_nsa_2025", "swiss_cpi_headline_mom_nsa_2026"],
  },
  {
    id: "swiss_cpi_core_seasonality",
    tab: "other-inflation",
    title: "Switzerland CPI Core Seasonality",
    kicker: "% MoM NSA",
    yLeftLabel: "% m/m NSA",
    chartType: "seasonality",
    seriesOrder: ["swiss_cpi_core_mom_nsa_range_min", "swiss_cpi_core_mom_nsa_range_max", "swiss_cpi_core_mom_nsa_median", "swiss_cpi_core_mom_nsa_2022", "swiss_cpi_core_mom_nsa_2025", "swiss_cpi_core_mom_nsa_2026"],
  },
  {
    id: "swiss_cpi_goods_rates",
    tab: "other-inflation",
    title: "Switzerland CPI Goods",
    kicker: "Inflation",
    yLeftLabel: "%",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -4, max: 8 } },
    startDate: "2018-01-01",
    seriesOrder: ["swiss_cpi_goods_yoy_nsa", "swiss_cpi_goods_hoh_saar", "swiss_cpi_goods_qoq_saar", "swiss_cpi_goods_mom_saar"],
  },
  {
    id: "swiss_cpi_services_rates",
    tab: "other-inflation",
    title: "Switzerland CPI Services",
    kicker: "Inflation",
    yLeftLabel: "%",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -2, max: 6 } },
    startDate: "2018-01-01",
    seriesOrder: ["swiss_cpi_services_yoy_nsa", "swiss_cpi_services_hoh_saar", "swiss_cpi_services_qoq_saar", "swiss_cpi_services_mom_saar"],
  },
  {
    id: "swiss_cpi_goods_seasonality",
    tab: "other-inflation",
    title: "Switzerland CPI Goods Seasonality",
    kicker: "% MoM NSA",
    yLeftLabel: "% m/m NSA",
    chartType: "seasonality",
    seriesOrder: ["swiss_cpi_goods_mom_nsa_range_min", "swiss_cpi_goods_mom_nsa_range_max", "swiss_cpi_goods_mom_nsa_median", "swiss_cpi_goods_mom_nsa_2022", "swiss_cpi_goods_mom_nsa_2025", "swiss_cpi_goods_mom_nsa_2026"],
  },
  {
    id: "swiss_cpi_services_seasonality",
    tab: "other-inflation",
    title: "Switzerland CPI Services Seasonality",
    kicker: "% MoM NSA",
    yLeftLabel: "% m/m NSA",
    chartType: "seasonality",
    seriesOrder: ["swiss_cpi_services_mom_nsa_range_min", "swiss_cpi_services_mom_nsa_range_max", "swiss_cpi_services_mom_nsa_median", "swiss_cpi_services_mom_nsa_2022", "swiss_cpi_services_mom_nsa_2025", "swiss_cpi_services_mom_nsa_2026"],
  },
  {
    id: "swiss_cpi_energy_fuels_rates",
    tab: "other-inflation",
    title: "Switzerland CPI Energy & Fuels",
    kicker: "Inflation",
    yLeftLabel: "%",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -25, max: 35 } },
    startDate: "2018-01-01",
    seriesOrder: ["swiss_cpi_energy_fuels_yoy_nsa", "swiss_cpi_energy_fuels_hoh_saar", "swiss_cpi_energy_fuels_qoq_saar", "swiss_cpi_energy_fuels_mom_saar"],
  },
  {
    id: "swiss_cpi_energy_fuels_seasonality",
    tab: "other-inflation",
    title: "Switzerland CPI Energy & Fuels Seasonality",
    kicker: "% MoM NSA",
    yLeftLabel: "% m/m NSA",
    chartType: "seasonality",
    seriesOrder: ["swiss_cpi_energy_fuels_mom_nsa_range_min", "swiss_cpi_energy_fuels_mom_nsa_range_max", "swiss_cpi_energy_fuels_mom_nsa_median", "swiss_cpi_energy_fuels_mom_nsa_2022", "swiss_cpi_energy_fuels_mom_nsa_2025", "swiss_cpi_energy_fuels_mom_nsa_2026"],
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

const seasonalityLabels = ["Dec -1", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const windows: Array<{ key: WindowKey; label: string; months?: number; years?: number }> = [
  { key: "all", label: "All" },
  { key: "10y", label: "10Y", years: 10 },
  { key: "5y", label: "5Y", years: 5 },
  { key: "2y", label: "2Y", years: 2 },
  { key: "1y", label: "1Y", years: 1 },
  { key: "6m", label: "6M", months: 6 },
];

export default function Home() {
  const [activeTab, setActiveTab] = useState<TabId>("speakers");
  const [seriesRows, setSeriesRows] = useState<SeriesRow[]>([]);
  const [speakers, setSpeakers] = useState<SpeakerRow[]>([]);
  const [metadata, setMetadata] = useState<Metadata>({});
  const [scenario, setScenario] = useState<ScenarioTrackerData>({});
  const [loadState, setLoadState] = useState("Loading data");

  useEffect(() => {
    let cancelled = false;

    async function loadData() {
      const [activityText, inflationText, speakersText, scenarioMarketText, scenarioResponse, metadataResponse] =
        await Promise.all([
          fetchText("/data/activity_series.csv"),
          fetchText("/data/inflation_series.csv"),
          fetchText("/data/ecb_speakers.csv"),
          fetchText("/data/scenario_market_series.csv"),
          fetch("/data/scenario_tracker.json", { cache: "no-store" }),
          fetch("/data/metadata.json", { cache: "no-store" }),
        ]);

      if (cancelled) {
        return;
      }

      const nextSeries = [
        ...parseSeriesCsv(activityText),
        ...parseSeriesCsv(inflationText),
        ...parseSeriesCsv(scenarioMarketText),
      ];

      setSeriesRows(nextSeries);
      setSpeakers(parseSpeakersCsv(speakersText));
      setScenario(scenarioResponse.ok ? await scenarioResponse.json() : {});
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
          <p className="eyebrow">Macro Europe Monitor</p>
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
      ) : activeTab === "scenario" ? (
        <ScenarioTracker scenario={scenario} rows={seriesRows} />
      ) : (
        <>
          <TabDataBanner metadata={metadata} rows={seriesRows} tab={activeTab} />
          {activeTab === "inflation" ? <HicpSummaryTable rows={seriesRows} /> : null}
          <section className="dashboard-grid">
            {activeCharts.map((chart) => (
              <TimeSeriesChart
                definition={chart}
                key={chart.id}
                rows={seriesRows.filter((row) => row.chart_id === chart.id)}
              />
            ))}
          </section>
        </>
      )}

      <p className="footer-note">
        Data mode: {metadata.data_mode ?? "initial mock"}. Data contract:
        CSVs in public/data.
      </p>
    </main>
  );
}

function TabDataBanner({
  metadata,
  rows,
  tab,
}: {
  metadata: Metadata;
  rows: SeriesRow[];
  tab: Exclude<TabId, "speakers">;
}) {
  const summary = tab === "activity" ? metadata.activity_last_new : metadata.inflation_last_new;
  const fallback = useMemo(() => latestTabUpdate(rows, tab), [rows, tab]);
  const date = summary?.date ? formatFullDateLabel(summary.date) : fallback.dateLabel;
  const description = summary?.description || fallback.description;

  return (
    <section className="tab-data-banner">
      <span>Last data updated: {date}</span>
      <strong>{description}</strong>
    </section>
  );
}

function HicpSummaryTable({ rows }: { rows: SeriesRow[] }) {
  const [seasonalSource, setSeasonalSource] = useState<SeasonalSource>("ecb");
  const tableRows = useMemo(
    () => buildHicpSummaryRows(rows, seasonalSource),
    [rows, seasonalSource],
  );

  return (
    <article className="chart-panel hicp-summary-panel" data-wide="true">
      <div className="panel-head">
        <div>
          <p className="panel-kicker">Inflation</p>
          <h2 className="panel-title">HICP Summary</h2>
        </div>
        <div className="seasonal-controls" aria-label="Seasonal adjustment source">
          <button
            data-active={seasonalSource === "ecb"}
            onClick={() => setSeasonalSource("ecb")}
            type="button"
          >
            SA - ECB
          </button>
          <button
            data-active={seasonalSource === "legacy"}
            onClick={() => setSeasonalSource("legacy")}
            type="button"
          >
            SA - Legacy
          </button>
        </div>
      </div>
      <div className="hicp-summary-wrap">
        <table className="hicp-summary-table">
          <thead>
            <tr>
              <th>Breakdown</th>
              <th>% YoY NSA</th>
              <th>vs Prior</th>
              <th>% QoQ SAAR</th>
              <th>vs Prior</th>
              <th>% MoM SAAR</th>
              <th>vs Prior</th>
              <th>Latest</th>
            </tr>
          </thead>
          <tbody>
            {tableRows.map((item) => (
              <tr key={item.label}>
                <td>{item.label}</td>
                <td>{formatSummaryValue(item.yoy)}</td>
                <td style={heatmapStyle(item.yoyChange, tableRows.map((row) => row.yoyChange))}>
                  {formatChangeValue(item.yoyChange)}
                </td>
                <td>{formatSummaryValue(item.qoq)}</td>
                <td style={heatmapStyle(item.qoqChange, tableRows.map((row) => row.qoqChange))}>
                  {formatChangeValue(item.qoqChange)}
                </td>
                <td>{formatSummaryValue(item.mom)}</td>
                <td style={heatmapStyle(item.momChange, tableRows.map((row) => row.momChange))}>
                  {formatChangeValue(item.momChange)}
                </td>
                <td>{item.date ? <span className="latest-date">{formatDateLabel(item.date)}</span> : ""}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </article>
  );
}

function TimeSeriesChart({
  definition,
  rows,
}: {
  definition: ChartDefinition;
  rows: SeriesRow[];
}) {
  if (definition.chartType === "seasonality") {
    return <SeasonalityChart definition={definition} rows={rows} />;
  }

  const [windowKey, setWindowKey] = useState<WindowKey>(definition.defaultWindow ?? "all");
  const [hiddenSeries, setHiddenSeries] = useState<Set<string>>(
    () => new Set(defaultHiddenSeries(definition)),
  );
  const [seasonalSource, setSeasonalSource] = useState<SeasonalSource>("ecb");
  const [rightAxisMode, setRightAxisMode] = useState<"fixed" | "auto">("fixed");
  const [rightAxisDirection, setRightAxisDirection] = useState<"normal" | "inverted">("normal");
  const [hover, setHover] = useState<HoverState | null>(null);

  const series = useMemo(() => buildSeries(rows, definition), [definition, rows]);
  const displaySeries = useMemo(
    () => filterSeasonalSource(series, definition, seasonalSource),
    [definition, seasonalSource, series],
  );
  const selectedWindow = windows.find((item) => item.key === windowKey);

  const filteredSeries = useMemo(() => {
    const startTime = definition.startDate
      ? new Date(`${definition.startDate}T00:00:00`).getTime()
      : null;
    const startFiltered = startTime
      ? displaySeries.map((item) => ({
          ...item,
          points: item.points.filter((point) => point.time >= startTime),
        }))
      : displaySeries;
    const allTimes = startFiltered.flatMap((item) => item.points.map((point) => point.time));
    if (!allTimes.length || (!selectedWindow?.years && !selectedWindow?.months)) {
      return startFiltered;
    }

    const maxTime = Math.max(...allTimes);
    const minTime = selectedWindow.years
      ? addYears(maxTime, -selectedWindow.years)
      : addMonths(maxTime, -(selectedWindow.months ?? 0));

    return startFiltered.map((item) => ({
      ...item,
      points: item.points.filter((point) => point.time >= minTime),
    }));
  }, [definition.startDate, displaySeries, selectedWindow]);

  const activeSeries = filteredSeries.filter((item) => !hiddenSeries.has(item.id));
  const effectiveDefinition = useMemo(
    () => applyFlexibleAxisSettings(definition, rightAxisMode, rightAxisDirection),
    [definition, rightAxisDirection, rightAxisMode],
  );
  const chartModel = useMemo(() => buildChartModel(activeSeries, effectiveDefinition), [activeSeries, effectiveDefinition]);

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
        <div className="chart-controls">
          {definition.seasonalToggle ? (
            <div className="seasonal-controls" aria-label="Seasonal adjustment source">
              <button
                data-active={seasonalSource === "ecb"}
                onClick={() => setSeasonalSource("ecb")}
                type="button"
              >
                SA - ECB
              </button>
              <button
                data-active={seasonalSource === "legacy"}
                onClick={() => setSeasonalSource("legacy")}
                type="button"
              >
                SA - Legacy
              </button>
            </div>
          ) : null}
          {definition.flexibleAxisControls ? (
            <div className="axis-controls" aria-label="Axis settings">
              <button
                data-active={rightAxisMode === "fixed"}
                onClick={() => setRightAxisMode("fixed")}
                type="button"
              >
                Fixed axis
              </button>
              <button
                data-active={rightAxisMode === "auto"}
                onClick={() => setRightAxisMode("auto")}
                type="button"
              >
                Auto axis
              </button>
              <button
                data-active={rightAxisDirection === "normal"}
                onClick={() => setRightAxisDirection("normal")}
                type="button"
              >
                Normal
              </button>
              <button
                data-active={rightAxisDirection === "inverted"}
                onClick={() => setRightAxisDirection("inverted")}
                type="button"
              >
                Invert
              </button>
            </div>
          ) : null}
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
      </div>

      <div className="legend" aria-label="Sections">
        {displaySeries.map((item) => (
          <button
            className="legend-button"
            data-hidden={hiddenSeries.has(item.id)}
            key={item.id}
            onClick={() => toggleSeries(item.id)}
            type="button"
          >
            <span
              className="legend-swatch"
              style={{
                background: item.dashArray ? "transparent" : item.color,
                borderColor: item.color,
              }}
            />
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
          viewBox={`0 0 ${chartModel?.width ?? 920} ${chartModel?.height ?? 470}`}
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
              top: `${(hover.y / (chartModel?.height ?? 470)) * 100}%`,
            }}
          >
            <div className="tooltip-date">{formatDateLabel(hover.date, definition.id)}</div>
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

function SeasonalityChart({
  definition,
  rows,
}: {
  definition: ChartDefinition;
  rows: SeriesRow[];
}) {
  const [hiddenSeries, setHiddenSeries] = useState<Set<string>>(new Set());
  const series = useMemo(() => buildSeries(rows, definition), [definition, rows]);
  const rangeMin = series.find((item) => item.id.endsWith("_range_min"));
  const rangeMax = series.find((item) => item.id.endsWith("_range_max"));
  const visibleSeries = series.filter((item) => !item.id.endsWith("_range_min") && !item.id.endsWith("_range_max"));
  const activeSeries = series.filter((item) => !hiddenSeries.has(item.id));
  const model = useMemo(() => buildSeasonalityModel(series), [series]);

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

  if (!series.length || !model) {
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
      </div>

      <div className="legend" aria-label="Sections">
        {visibleSeries.map((item) => (
          <button
            className="legend-button"
            data-hidden={hiddenSeries.has(item.id)}
            key={item.id}
            onClick={() => toggleSeries(item.id)}
            type="button"
          >
            <span
              className="legend-swatch"
              style={{
                background: item.dashArray ? "transparent" : item.color,
                borderColor: item.color,
              }}
            />
            {item.name}
          </button>
        ))}
        <span className="legend-button static-legend">
          <span className="legend-swatch range-swatch" />
          2012-2025 range
        </span>
      </div>

      <div className="chart-frame">
        <svg
          aria-label={definition.title}
          className="chart-svg"
          role="img"
          viewBox={`0 0 ${model.width} ${model.height}`}
        >
          <rect
            fill="transparent"
            height={model.innerHeight}
            width={model.innerWidth}
            x={model.margin.left}
            y={model.margin.top}
          />
          {model.yTicks.map((tick) => {
            const y = model.scaleY(tick);
            return (
              <g key={`seasonal-y-${tick}`}>
                <line
                  className="grid-line"
                  x1={model.margin.left}
                  x2={model.width - model.margin.right}
                  y1={y}
                  y2={y}
                />
                <text className="tick-label" textAnchor="end" x={model.margin.left - 10} y={y + 4}>
                  {formatNumber(tick)}
                </text>
              </g>
            );
          })}
          {model.domain.min < 0 && model.domain.max > 0 ? (
            <line
              className="zero-line"
              x1={model.margin.left}
              x2={model.width - model.margin.right}
              y1={model.scaleY(0)}
              y2={model.scaleY(0)}
            />
          ) : null}
          {seasonalityLabels.map((label, index) => {
            const x = model.scaleX(index);
            return (
              <g key={label}>
                <line
                  className="grid-line"
                  x1={x}
                  x2={x}
                  y1={model.margin.top}
                  y2={model.height - model.margin.bottom}
                />
                <text className="tick-label" textAnchor="middle" x={x} y={model.height - model.margin.bottom + 24}>
                  {label}
                </text>
              </g>
            );
          })}
          <line className="axis-line" x1={model.margin.left} x2={model.margin.left} y1={model.margin.top} y2={model.height - model.margin.bottom} />
          <line className="axis-line" x1={model.margin.left} x2={model.width - model.margin.right} y1={model.height - model.margin.bottom} y2={model.height - model.margin.bottom} />
          <text className="axis-label" textAnchor="start" x={model.margin.left} y={24}>
            {definition.yLeftLabel}
          </text>
          {rangeMin && rangeMax ? (
            <path className="seasonality-range" d={seasonalityRangePath(rangeMin, rangeMax, model.scaleX, model.scaleY)} />
          ) : null}
          {activeSeries
            .filter((item) => !item.id.endsWith("_range_min") && !item.id.endsWith("_range_max"))
            .map((item) => (
            <path
              className="series-path"
              d={pathForSeasonalitySeries(item, model.scaleX, model.scaleY)}
              key={item.id}
              stroke={item.color}
              strokeDasharray={item.dashArray}
            />
          ))}
        </svg>
      </div>
      <p className="source-note">
        Source: <SourceLinks series={series} />
      </p>
    </article>
  );
}

function applyFlexibleAxisSettings(
  definition: ChartDefinition,
  rightAxisMode: "fixed" | "auto",
  rightAxisDirection: "normal" | "inverted",
): ChartDefinition {
  if (!definition.flexibleAxisControls) {
    return definition;
  }

  const fixedRight = definition.fixedDomains?.right;
  const nextFixedDomains = { ...definition.fixedDomains };
  if (rightAxisMode === "auto") {
    delete nextFixedDomains.right;
  } else if (fixedRight) {
    nextFixedDomains.right =
      rightAxisDirection === "inverted"
        ? { min: Math.max(fixedRight.min, fixedRight.max), max: Math.min(fixedRight.min, fixedRight.max) }
        : { min: Math.min(fixedRight.min, fixedRight.max), max: Math.max(fixedRight.min, fixedRight.max) };
  }

  return {
    ...definition,
    fixedDomains: nextFixedDomains,
    invertRightAxis: rightAxisDirection === "inverted",
    yRightLabel:
      rightAxisDirection === "inverted" && definition.yRightLabel
        ? `${definition.yRightLabel} (inverted)`
        : definition.yRightLabel?.replace(" (inverted)", ""),
  };
}

function SourceLinks({ series }: { series: ChartSeries[] }) {
  const sources = uniqueSources(series);

  return (
    <>
      {sources.map((source, index) => {
        const label = source.frequency
          ? `${source.label} (${toTitleCase(source.frequency)})`
          : source.label;
        const labelWithNote = source.note ? `${label} ${source.note}` : label;
        return (
          <span key={`${source.label}-${source.url}-${source.frequency}-${source.note}`}>
            {index > 0 ? "; " : ""}
            {source.url ? (
              <a href={source.url} rel="noreferrer" target="_blank">
                {labelWithNote}
              </a>
            ) : (
              labelWithNote
            )}
          </span>
        );
      })}
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
  const clipId = `${definition.id}-plot-clip`;

  return (
    <>
      <defs>
        <clipPath id={clipId}>
          <rect
            height={innerHeight}
            width={innerWidth}
            x={margin.left}
            y={margin.top}
          />
        </clipPath>
      </defs>
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
              className={definition.id === "sentix_pmi" ? "tick-label sentix-pmi-left-tick" : "tick-label"}
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
            className={definition.id === "sentix_pmi" ? "tick-label sentix-pmi-right-tick" : "tick-label"}
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
      {definition.yRightLabel ? (
        <line
          className="axis-line"
          x1={width - margin.right}
          x2={width - margin.right}
          y1={margin.top}
          y2={height - margin.bottom}
        />
      ) : null}
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
      {series.map((item) =>
        item.id.endsWith("_daily") ? (
          <g clipPath={`url(#${clipId})`} key={item.id}>
            {item.points.map((point) => (
              <circle
                className="series-point"
                cx={scaleX(point.time)}
                cy={scaleY(point.value, item.axis)}
                fill={item.color}
                key={`${item.id}-${point.date}`}
                r={2.2}
              />
            ))}
          </g>
        ) : (
          <path
            className="series-path"
            clipPath={`url(#${clipId})`}
            d={pathForSeries(item, scaleX, scaleY)}
            key={item.id}
            stroke={item.color}
            strokeDasharray={item.dashArray}
          />
        ),
      )}
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
              <th>Policy Comments</th>
              <th>Bias</th>
              <th>vs Previous</th>
            </tr>
          </thead>
          <tbody>
            {filteredSpeakers.map((speaker, index) => (
              <tr key={`${speaker.date}-${speaker.member}-${index}`}>
                <td>{formatFullDateLabel(speaker.date)}</td>
                <td>
                  {speaker.source_url ? (
                    <a href={speaker.source_url} rel="noreferrer" target="_blank">
                      {speaker.member} ({speaker.country})
                    </a>
                  ) : (
                    `${speaker.member} (${speaker.country})`
                  )}
                </td>
                <td>{speaker.position}</td>
                <td className={isPriorityEcbMember(speaker.member) ? "priority-policy-comment" : ""}>
                  {speaker.policy_comments}
                </td>
                <td>
                  <span className={`bias ${biasClassName(speaker.bias)}`}>
                    {speaker.bias}
                  </span>
                </td>
                <td>{speaker.stance_change}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function ScenarioTracker({
  scenario,
  rows,
}: {
  scenario: ScenarioTrackerData;
  rows: SeriesRow[];
}) {
  const latest = [...(scenario.snapshots ?? [])].sort((a, b) => parseTime(b.date) - parseTime(a.date))[0];
  const marketChart = charts.find((chart) => chart.id === "scenario_eurusd_real_rates");

  return (
    <section className="scenario-layout">
      {marketChart ? (
        <TimeSeriesChart
          definition={marketChart}
          rows={rows.filter((row) => row.chart_id === marketChart.id)}
        />
      ) : null}

      <article className="scenario-panel">
        <div className="panel-head">
          <div>
            <p className="panel-kicker">Scenario Tracker</p>
            <h2 className="panel-title">
              {latest?.coreView ?? "Waiting for scenario snapshot"}
            </h2>
          </div>
          {latest ? (
            <span className="scenario-date">{formatFullDateLabel(latest.date)}</span>
          ) : null}
        </div>
        {latest ? (
          <>
            <div className="scenario-meta">
              <span>{latest.trigger}</span>
              <strong>Confidence: {latest.confidence}</strong>
            </div>
            <div className="scenario-columns">
              <ScenarioList title="Activity" items={latest.activity} />
              <ScenarioList title="Inflation" items={latest.inflation} />
              <ScenarioList title="ECB / Rates" items={latest.rates} />
              <ScenarioList title="Risks" items={latest.risks} />
            </div>
          </>
        ) : (
          <div className="empty-state">Waiting for scenario data</div>
        )}
      </article>
    </section>
  );
}

function ScenarioList({ items, title }: { items: string[]; title: string }) {
  return (
    <section className="scenario-section">
      <h3>{title}</h3>
      <ul>
        {items.map((item) => (
          <li key={item}>{item}</li>
        ))}
      </ul>
    </section>
  );
}

function isPriorityEcbMember(member: string) {
  return ["lagarde", "lane", "schnabel"].includes(member.trim().toLowerCase());
}

function biasClassName(bias: SpeakerRow["bias"]) {
  return `bias-${bias.replace(/\s+/g, "-")}`;
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
      frequency: row.frequency ?? "",
      source_note: row.source_note ?? "",
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
    bias: parseSpeakerBias(row.bias),
    stance_change: row.stance_change ?? "",
    tags: row.tags ?? "",
    source_url: row.source_url ?? "",
  }));
}

function parseSpeakerBias(value?: string): SpeakerRow["bias"] {
  if (
    value === "hawkish" ||
    value === "mildly hawkish" ||
    value === "dovish" ||
    value === "mildly dovish" ||
    value === "neutral"
  ) {
    return value;
  }
  return "neutral";
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
        frequency: row.frequency,
        sourceNote: row.source_note,
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
    .map((item, index) => {
      const style = styleForSeries(item.id, palette[index % palette.length]);
      return { ...item, ...style };
    });
}

function styleForSeries(seriesId: string, fallbackColor: string) {
  if (seriesId.endsWith("_range_min") || seriesId.endsWith("_range_max")) {
    return { color: "#c7c7c7" };
  }
  if (seriesId.endsWith("_median")) {
    return { color: "#111111", dashArray: "6 5" };
  }
  if (seriesId.endsWith("_2022")) {
    return { color: "#4d77c3" };
  }
  if (seriesId.endsWith("_2025")) {
    return { color: "#d68b2d" };
  }
  if (seriesId.endsWith("_2026")) {
    return { color: "#178f65" };
  }
  const metricId = seriesId.replace("_legacy", "");
  if (metricId.endsWith("_yoy_nsa")) {
    return { color: "#111111" };
  }
  if (metricId.endsWith("_qoq_saar")) {
    return { color: "#a83f39" };
  }
  if (metricId.endsWith("_hoh_saar")) {
    return { color: "#11675f" };
  }
  if (metricId.endsWith("_mom_saar")) {
    return { color: "#65b88f", dashArray: "6 5" };
  }
  return { color: fallbackColor };
}

function filterSeasonalSource(
  series: ChartSeries[],
  definition: ChartDefinition,
  source: SeasonalSource,
) {
  if (!definition.seasonalToggle) {
    return series;
  }

  const baseOrder = (definition.seriesOrder ?? []).filter((seriesId) => !seriesId.endsWith("_legacy"));
  const visibleIds = new Set<string>();
  baseOrder.forEach((seriesId) => {
    visibleIds.add(source === "legacy" && !seriesId.endsWith("_yoy_nsa") ? `${seriesId}_legacy` : seriesId);
  });

  return series
    .filter((item) => visibleIds.has(item.id))
    .sort((a, b) => {
      const aBase = a.id.replace("_legacy", "");
      const bBase = b.id.replace("_legacy", "");
      return baseOrder.indexOf(aBase) - baseOrder.indexOf(bBase);
    });
}

function buildSeasonalityModel(series: ChartSeries[]) {
  const width = 920;
  const height = 430;
  const margin = { top: 30, right: 24, bottom: 46, left: 50 };
  const innerWidth = width - margin.left - margin.right;
  const innerHeight = height - margin.top - margin.bottom;
  const values = series.flatMap((item) => item.points.map((point) => point.value));

  if (!values.length) {
    return null;
  }

  const domain = getValueDomain(values);
  const scaleX = (index: number) =>
    margin.left + (index / Math.max(1, seasonalityLabels.length - 1)) * innerWidth;
  const scaleY = (value: number) =>
    margin.top + (1 - (value - domain.min) / (domain.max - domain.min)) * innerHeight;

  return {
    domain,
    height,
    innerHeight,
    innerWidth,
    margin,
    scaleX,
    scaleY,
    width,
    yTicks: makeTicks(domain.min, domain.max, 5),
  };
}

function seasonalityIndex(date: string) {
  if (date.startsWith("1999-12")) {
    return 0;
  }
  return new Date(`${date}T00:00:00`).getMonth() + 1;
}

function pathForSeasonalitySeries(
  series: ChartSeries,
  scaleX: (index: number) => number,
  scaleY: (value: number) => number,
) {
  return series.points
    .map((point, index) => {
      const command = index === 0 ? "M" : "L";
      return `${command}${scaleX(seasonalityIndex(point.date)).toFixed(2)},${scaleY(point.value).toFixed(2)}`;
    })
    .join(" ");
}

function seasonalityRangePath(
  rangeMin: ChartSeries,
  rangeMax: ChartSeries,
  scaleX: (index: number) => number,
  scaleY: (value: number) => number,
) {
  const minByIndex = new Map(rangeMin.points.map((point) => [seasonalityIndex(point.date), point.value]));
  const maxPoints = rangeMax.points
    .map((point) => ({ index: seasonalityIndex(point.date), value: point.value }))
    .sort((a, b) => a.index - b.index);
  const minPoints = [...minByIndex.entries()]
    .map(([index, value]) => ({ index, value }))
    .sort((a, b) => b.index - a.index);
  const top = maxPoints
    .map((point, index) => `${index === 0 ? "M" : "L"}${scaleX(point.index).toFixed(2)},${scaleY(point.value).toFixed(2)}`)
    .join(" ");
  const bottom = minPoints
    .map((point) => `L${scaleX(point.index).toFixed(2)},${scaleY(point.value).toFixed(2)}`)
    .join(" ");
  return `${top} ${bottom} Z`;
}

function buildHicpSummaryRows(rows: SeriesRow[], source: SeasonalSource) {
  const definitions = [
    {
      label: "Headline",
      yoy: "hicp_headline_yoy_nsa",
      qoq: "hicp_headline_qoq_saar",
      mom: "hicp_headline_mom_saar",
    },
    {
      label: "Core",
      yoy: "hicp_core_yoy_nsa",
      qoq: "hicp_core_qoq_saar",
      mom: "hicp_core_mom_saar",
    },
    {
      label: "Goods",
      yoy: "hicp_goods_yoy_nsa",
      qoq: "hicp_goods_qoq_saar",
      mom: "hicp_goods_mom_saar",
    },
    {
      label: "Services",
      yoy: "hicp_services_yoy_nsa",
      qoq: "hicp_services_qoq_saar",
      mom: "hicp_services_mom_saar",
    },
  ];

  return definitions.map((definition) => {
    const qoqId = source === "legacy" ? `${definition.qoq}_legacy` : definition.qoq;
    const momId = source === "legacy" ? `${definition.mom}_legacy` : definition.mom;
    const yoy = latestPointWithChange(rows, definition.yoy);
    const qoq = latestPointWithChange(rows, qoqId);
    const mom = latestPointWithChange(rows, momId);
    const latestTime = Math.max(
      yoy ? parseTime(yoy.date) : -Infinity,
      qoq ? parseTime(qoq.date) : -Infinity,
      mom ? parseTime(mom.date) : -Infinity,
    );
    const latestDate = Number.isFinite(latestTime) ? new Date(latestTime).toISOString().slice(0, 10) : "";
    const alignedYoy = yoy?.date === latestDate ? yoy : undefined;
    const alignedQoq = qoq?.date === latestDate ? qoq : undefined;
    const alignedMom = mom?.date === latestDate ? mom : undefined;
    return {
      date: latestDate,
      label: definition.label,
      mom: alignedMom?.value,
      momChange: alignedMom?.change,
      qoq: alignedQoq?.value,
      qoqChange: alignedQoq?.change,
      yoy: alignedYoy?.value,
      yoyChange: alignedYoy?.change,
    };
  });
}

function latestPointWithChange(rows: SeriesRow[], seriesId: string) {
  const points = rows
    .filter((row) => row.series_id === seriesId)
    .sort((a, b) => parseTime(a.date) - parseTime(b.date));
  const latest = points.at(-1);
  if (!latest) {
    return undefined;
  }
  const previous = points.at(-2);
  return {
    ...latest,
    change: previous ? latest.value - previous.value : undefined,
  };
}

function latestTabUpdate(rows: SeriesRow[], tab: Exclude<TabId, "speakers">) {
  const chartMap = new Map(charts.map((chart) => [chart.id, chart]));
  const tabChartIds = new Set(charts.filter((chart) => chart.tab === tab).map((chart) => chart.id));
  const tabRows = rows.filter((row) => tabChartIds.has(row.chart_id));
  if (!tabRows.length) {
    return { dateLabel: "pending", description: "Waiting for data" };
  }

  const maxTime = Math.max(...tabRows.map((row) => parseTime(row.date)));
  const latestRows = tabRows.filter((row) => parseTime(row.date) === maxTime);
  const descriptions = [...new Set(
    latestRows.map((row) => chartMap.get(row.chart_id)?.title || row.series_name),
  )].slice(0, 3);

  return {
    dateLabel: formatFullDateLabel(new Date(maxTime).toISOString().slice(0, 10)),
    description: descriptions.join(", "),
  };
}

function buildChartModel(series: ChartSeries[], definition?: ChartDefinition) {
  const width = 920;
  const height = 470;
  const margin = { top: 30, right: 54, bottom: 42, left: 50 };
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
  const leftDomain = definition?.fixedDomains?.left ?? getValueDomain(leftPoints.length ? leftPoints : rightPoints);
  const rightBaseDomain = definition?.fixedDomains?.right ?? (rightPoints.length ? getValueDomain(rightPoints) : leftDomain);
  const rightDomain =
    definition?.invertRightAxis && rightBaseDomain.min < rightBaseDomain.max
      ? { min: rightBaseDomain.max, max: rightBaseDomain.min }
      : rightBaseDomain;

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

function addMonths(time: number, months: number) {
  const date = new Date(time);
  date.setMonth(date.getMonth() + months);
  return date.getTime();
}

function parseTime(date: string) {
  return new Date(`${date}T00:00:00`).getTime();
}

function formatYear(time: number) {
  return new Date(time).getFullYear().toString().slice(2);
}

function defaultHiddenSeries(definition: ChartDefinition) {
  if (definition.id === "pmi_gdp" || definition.id === "pmi_ea_aggregate") {
    return [];
  }

  if (!definition.id.startsWith("pmi_")) {
    return [];
  }

  return (definition.seriesOrder ?? []).filter((seriesId) => !seriesId.endsWith("_ea"));
}

function uniqueSources(series: ChartSeries[]) {
  const sourceMap = new Map<string, { frequency: string; label: string; note: string; url: string }>();

  series.forEach((item) => {
    const label = item.source || "Unspecified source";
    const key = `${label}|${item.sourceUrl}|${item.frequency}|${item.sourceNote}`;
    if (!sourceMap.has(key)) {
      sourceMap.set(key, { frequency: item.frequency, label, note: item.sourceNote, url: item.sourceUrl });
    }
  });

  return [...sourceMap.values()];
}

function formatDateLabel(date: string, chartId?: string) {
  if (!date) {
    return "";
  }
  if (chartId === "weekly_activity") {
    return new Intl.DateTimeFormat("en-GB", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
    }).format(new Date(`${date}T00:00:00`));
  }
  return new Intl.DateTimeFormat("en-US", {
    month: "2-digit",
    year: "numeric",
  }).format(new Date(`${date}T00:00:00`));
}

function toTitleCase(value: string) {
  return value
    .split(/\s+/)
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join(" ");
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

function formatSummaryValue(value?: number) {
  return Number.isFinite(value) ? formatFixedTwo(value as number) : "";
}

function formatChangeValue(value?: number) {
  if (!Number.isFinite(value)) {
    return "";
  }
  const numeric = value as number;
  const sign = numeric > 0 ? "+" : "";
  return `${sign}${formatFixedTwo(numeric)}`;
}

function formatFixedTwo(value: number) {
  return value.toLocaleString("en-US", {
    maximumFractionDigits: 2,
    minimumFractionDigits: 2,
  });
}

function heatmapStyle(value: number | undefined, values: Array<number | undefined>) {
  if (!Number.isFinite(value)) {
    return undefined;
  }
  const numericValues = values.filter((item): item is number => Number.isFinite(item));
  if (!numericValues.length) {
    return undefined;
  }
  const maxAbs = Math.max(...numericValues.map((item) => Math.abs(item))) || 1;
  const intensity = Math.min(Math.abs(value as number) / maxAbs, 1);
  const color = (value as number) >= 0 ? "168, 63, 57" : "17, 103, 95";
  return {
    background: `rgba(${color}, ${0.1 + intensity * 0.24})`,
    color: (value as number) >= 0 ? "#7f2f2a" : "#0f5f58",
    fontWeight: 720,
  };
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
