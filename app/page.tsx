"use client";

import { useEffect, useMemo, useState } from "react";

type TabId = "activity" | "inflation" | "other-inflation" | "scenario" | "speakers" | "fiscal";
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
  tab: Exclude<TabId, "speakers" | "fiscal">;
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
  bar?: boolean;
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
  { id: "fiscal", label: "Fiscal Monitor" },
];

type FiscalCountry = {
  id: string; name: string; flag: string; signal: "risk" | "supply" | "improving" | "watch";
  thesis: string; balance: number[]; debt: number[]; primary: number; interest: number;
  issuance: string; spread: number; maturity: string; ratings: string; rules: string;
};

type FiscalSpreadRow = {
  date: string;
  country: string;
  countryName: string;
  spread: number;
  time: number;
};

type G10FiscalRow = {
  scopeCode: string;
  scopeName: string;
  year: number;
  seriesId: string;
  seriesName: string;
  value: number;
  status: "actual" | "estimate" | "projection";
};

type G10CompositionRow = {
  scopeCode: string;
  scopeName: string;
  year: number;
  componentId: string;
  componentName: string;
  value: number;
  status: "actual" | "estimate";
};

const g10Scopes = [
  ["MAE", "G7 aggregate"], ["USA", "United States"], ["JPN", "Japan"],
  ["DEU", "Germany"], ["FRA", "France"], ["GBR", "United Kingdom"],
  ["ITA", "Italy"], ["CAN", "Canada"],
] as const;

const g10ScopeColors: Record<string, string> = {
  MAE: "#191919", USA: "#204f86", JPN: "#a83f39", DEU: "#6c5f8d",
  FRA: "#3f7f52", GBR: "#c47a20", ITA: "#11675f", CAN: "#8c7b57",
};

const fiscalYears = ["2025", "2026", "2027"];
const fiscalCountries: FiscalCountry[] = [
  { id: "fr", name: "France", flag: "FR", signal: "risk", thesis: "The euro area's live fiscal-risk story: persistent primary deficits and political execution risk keep OATs under scrutiny.", balance: [-5.1,-5.1,-5.7], debt: [115.6,118.1,120.2], primary: -3.2, interest: 2.1, issuance: "€310bn net M/L", spread: 74, maturity: "8.4 years", ratings: "Aa3 / AA− / AA−", rules: "EDP · 7-year adjustment path" },
  { id: "de", name: "Germany", flag: "DE", signal: "supply", thesis: "A regime shift from scarcity to supply as debt-brake reform funds infrastructure and defence.", balance: [-2.7,-3.7,-4.1], debt: [63.5,65.8,68.0], primary: -1.8, interest: 0.9, issuance: "~€512bn gross", spread: 0, maturity: "7.6 years", ratings: "Aaa / AAA / AAA", rules: "Preventive arm · national rule reformed" },
  { id: "it", name: "Italy", flag: "IT", signal: "improving", thesis: "High debt, but a returning primary surplus and policy stability explain the resilient BTP story.", balance: [-3.1,-2.9,-2.9], debt: [137.1,138.5,139.2], primary: 0.8, interest: 3.9, issuance: "~€350bn gross", spread: 91, maturity: "7.0 years", ratings: "Baa2 / BBB+ / BBB", rules: "EDP · 7-year adjustment path" },
  { id: "uk", name: "United Kingdom", flag: "UK", signal: "watch", thesis: "A tight fiscal-rule buffer leaves gilts sensitive to growth, inflation and OBR forecast revisions.", balance: [-4.7,-4.3,-3.8], debt: [95.8,97.0,97.4], primary: -1.9, interest: 3.4, issuance: "£299bn gilts", spread: 161, maturity: "14.1 years", ratings: "Aa3 / AA / AA−", rules: "OBR stability rule · limited headroom" },
  { id: "es", name: "Spain", flag: "ES", signal: "improving", thesis: "Growth and revenue strength continue to compress debt and reinforce the core-periphery inversion.", balance: [-2.4,-2.4,-2.0], debt: [100.7,99.6,98.9], primary: 0.2, interest: 2.6, issuance: "~€285bn gross", spread: 49, maturity: "7.8 years", ratings: "Baa1 / A / A−", rules: "Preventive arm · 4-year plan" },
  { id: "pt", name: "Portugal", flag: "PT", signal: "improving", thesis: "Primary surpluses and a favourable r−g dynamic keep debt on a steep downward path.", balance: [0.7,-0.1,-0.4], debt: [89.7,87.6,86.0], primary: 2.1, interest: 2.0, issuance: "~€31bn gross", spread: 35, maturity: "7.9 years", ratings: "A3 / A+ / A−", rules: "Preventive arm · 4-year plan" },
  { id: "gr", name: "Greece", flag: "GR", signal: "improving", thesis: "Long maturity, a large primary surplus and rating upgrades outweigh the still-high debt stock.", balance: [1.3,0.8,0.6], debt: [145.7,138.0,131.5], primary: 3.6, interest: 2.3, issuance: "~€8bn bonds", spread: 58, maturity: "18.5 years", ratings: "Baa3 / BBB / BBB−", rules: "Preventive arm · 4-year plan" },
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
    id: "hicp_energy_intensive_rates",
    tab: "inflation",
    title: "HICPX Energy-intensive",
    kicker: "ECB methodology",
    yLeftLabel: "%",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -1, max: 10 } },
    startDate: "2018-01-01",
    seriesOrder: ["hicp_energy_intensive_yoy_nsa", "hicp_energy_intensive_qoq_saar", "hicp_energy_intensive_mom_saar"],
  },
  {
    id: "hicp_energy_intensive_seasonality",
    tab: "inflation",
    title: "HICPX Energy-intensive Seasonality",
    kicker: "% MoM NSA",
    yLeftLabel: "% m/m NSA",
    chartType: "seasonality",
    seriesOrder: ["hicp_energy_intensive_mom_nsa_range_min", "hicp_energy_intensive_mom_nsa_range_max", "hicp_energy_intensive_mom_nsa_median", "hicp_energy_intensive_mom_nsa_2022", "hicp_energy_intensive_mom_nsa_2025", "hicp_energy_intensive_mom_nsa_2026"],
  },
  {
    id: "hicp_wage_intensive_rates",
    tab: "inflation",
    title: "HICPX Wage-intensive",
    kicker: "ECB methodology",
    yLeftLabel: "%",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -1, max: 10 } },
    startDate: "2018-01-01",
    seriesOrder: ["hicp_wage_intensive_yoy_nsa", "hicp_wage_intensive_qoq_saar", "hicp_wage_intensive_mom_saar"],
  },
  {
    id: "hicp_wage_intensive_seasonality",
    tab: "inflation",
    title: "HICPX Wage-intensive Seasonality",
    kicker: "% MoM NSA",
    yLeftLabel: "% m/m NSA",
    chartType: "seasonality",
    seriesOrder: ["hicp_wage_intensive_mom_nsa_range_min", "hicp_wage_intensive_mom_nsa_range_max", "hicp_wage_intensive_mom_nsa_median", "hicp_wage_intensive_mom_nsa_2022", "hicp_wage_intensive_mom_nsa_2025", "hicp_wage_intensive_mom_nsa_2026"],
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
    seriesOrder: ["ecb_pcci_3m_saar", "hicp_headline_pc_pcci_3m_saar", "hicp_headline_pc_pcci_3m_saar_ma3"],
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
    id: "hicp_neig_price_pressures",
    tab: "inflation",
    title: "EU HICP Non-energy Industrial Goods",
    kicker: "Price pressures",
    yLeftLabel: "%",
    yRightLabel: "Survey balance",
    defaultWindow: "10y",
    fixedDomains: { left: { min: -1, max: 7 } },
    seriesOrder: [
      "hicp_neig_yoy_nsa",
      "hicp_neig_qoq_saar_3mma",
      "ec_industry_prices_6m_lag",
      "ec_retail_prices_6m_lag",
    ],
  },
  {
    id: "wage_tracker",
    tab: "inflation",
    title: "Wage Tracker",
    kicker: "Wages",
    yLeftLabel: "% y/y",
    yRightLabel: "Employee coverage (%)",
    fixedDomains: { left: { min: 0, max: 7 }, right: { min: 25, max: 55 } },
    seriesOrder: ["wage_tracker_coverage", "indeed_wage_tracker_yoy", "ecb_negotiated_wages", "wage_tracker_ea", "wage_tracker_ea_monthly", "wage_tracker_unsmoothed", "wage_tracker_excluding"],
  },
  {
    id: "ecb_ces_inflation_expectations",
    tab: "inflation",
    title: "ECB Inflation Expectations",
    kicker: "Expectations",
    yLeftLabel: "%",
    defaultWindow: "5y",
    seriesOrder: [
      "ecb_ces_infl_exp_1y",
      "ecb_ces_infl_exp_3y",
      "ecb_ces_infl_exp_5y",
      "ecb_spf_hicp_3q_ahead",
      "ecb_spf_hicp_7q_ahead",
      "ecb_spf_hicp_2y_ahead",
      "ecb_spf_hicp_lt",
    ],
  },
  {
    id: "ge_ifo_price_expectations",
    tab: "inflation",
    title: "GE IFO Price Expectations",
    kicker: "Price plans",
    yLeftLabel: "Balance",
    defaultWindow: "5y",
    fixedDomains: { left: { min: -30, max: 80 } },
    seriesOrder: [
      "ifo_mfg_prices_de",
      "ifo_services_prices_de",
      "ifo_food_prices_de",
      "ifo_chemical_prices_de",
    ],
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
      ) : activeTab === "fiscal" ? (
        <FiscalMonitor />
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
        {activeTab === "fiscal"
          ? "Fiscal data: IMF WEO and Fiscal Monitor, OECD COFOG, SIPRI and Statistics Canada."
          : `Data mode: ${metadata.data_mode ?? "initial mock"}. Data contract: CSVs in public/data.`}
      </p>
    </main>
  );
}

function FiscalMonitor() {
  const [selectedId, setSelectedId] = useState("g10");
  const [spreadHistory, setSpreadHistory] = useState<FiscalSpreadRow[]>([]);
  const [g10History, setG10History] = useState<G10FiscalRow[]>([]);
  const [g10Composition, setG10Composition] = useState<G10CompositionRow[]>([]);
  const selected = fiscalCountries.find((country) => country.id === selectedId) ?? fiscalCountries[0];
  const maxSpread = Math.max(...fiscalCountries.map((country) => country.spread));

  useEffect(() => {
    fetchText("/data/fiscal_spreads.csv").then((text) => {
      setSpreadHistory(parseCsv(text).map((row) => ({
        country: row.country,
        countryName: row.country_name,
        date: row.date,
        spread: Number(row.spread_bp),
        time: parseTime(row.date),
      })).filter((row) => Number.isFinite(row.spread)));
    }).catch(() => setSpreadHistory([]));
  }, []);

  useEffect(() => {
    Promise.all([
      fetchText("/data/g10_fiscal_history.csv"),
      fetchText("/data/g10_fiscal_composition.csv"),
    ]).then(([historyText, compositionText]) => {
      setG10History(parseCsv(historyText).map((row) => ({
        scopeCode: row.scope_code, scopeName: row.scope_name, year: Number(row.year),
        seriesId: row.series_id, seriesName: row.series_name, value: Number(row.value),
        status: row.status as G10FiscalRow["status"],
      })).filter((row) => Number.isFinite(row.year) && Number.isFinite(row.value)));
      setG10Composition(parseCsv(compositionText).map((row) => ({
        scopeCode: row.scope_code, scopeName: row.scope_name, year: Number(row.year),
        componentId: row.component_id, componentName: row.component_name, value: Number(row.value),
        status: row.status as G10CompositionRow["status"],
      })).filter((row) => Number.isFinite(row.year) && Number.isFinite(row.value)));
    }).catch(() => {
      setG10History([]);
      setG10Composition([]);
    });
  }, []);

  return (
    <section className="fiscal-monitor">
      <div className="fiscal-hero">
        <div>
          <p className="panel-kicker">Sovereign dashboard · Spring 2026</p>
        </div>
        <div className="fiscal-legend" aria-label="Signal legend">
          <span><i data-signal="risk" />Risk</span><span><i data-signal="supply" />Supply</span><span><i data-signal="improving" />Improving</span>
        </div>
      </div>

      <div className="country-rail" role="tablist" aria-label="Country selection">
        <button aria-selected={selectedId === "g10"} className="country-chip g10-chip" data-active={selectedId === "g10"} onClick={() => setSelectedId("g10")} role="tab" type="button">
          <span className="country-code">G10</span><span>G10 Monitor</span><i data-signal="supply" />
        </button>
        {fiscalCountries.map((country) => (
          <button aria-selected={selected.id === country.id} className="country-chip" data-active={selected.id === country.id} key={country.id} onClick={() => setSelectedId(country.id)} role="tab" type="button">
            <span className="country-code">{country.flag}</span><span>{country.name}</span><i data-signal={country.signal} />
          </button>
        ))}
      </div>

      {selectedId === "g10" ? <G10FiscalMonitor composition={g10Composition} history={g10History} /> : <>
      <div className="fiscal-layout">
        <article className="fiscal-country-card">
          <div className="fiscal-country-head"><div><p className="panel-kicker">Country view</p><h3>{selected.name}</h3></div><span className="signal-label" data-signal={selected.signal}>{selected.signal}</span></div>
          <p className="country-thesis">{selected.thesis}</p>
          <div className="fiscal-stat-grid">
            <FiscalStat label="Primary balance" value={`${selected.primary > 0 ? "+" : ""}${selected.primary.toFixed(1)}%`} note="2025 · GDP" />
            <FiscalStat label="Interest bill" value={`${selected.interest.toFixed(1)}%`} note="2025 · GDP" />
            <FiscalStat label="2026 issuance" value={selected.issuance} note="sovereign programme" />
            <FiscalStat label="10Y spread" value={selected.id === "de" ? "Benchmark" : `${selected.spread}bp`} note="vs Bund · indicative" />
          </div>
          <div className="trajectory-block">
            <div className="trajectory-head"><span>Fiscal trajectory</span>{fiscalYears.map((year) => <b key={year}>{year}</b>)}</div>
            <div className="trajectory-row"><span>Balance / GDP</span>{selected.balance.map((value, index) => <strong className={value < -3 ? "negative" : value >= 0 ? "positive" : ""} key={index}>{value.toFixed(1)}%</strong>)}</div>
            <div className="trajectory-row"><span>Debt / GDP</span>{selected.debt.map((value, index) => <strong key={index}>{value.toFixed(1)}%</strong>)}</div>
          </div>
          <div className="fiscal-details"><div><span>Ratings · Moody&apos;s / S&amp;P / Fitch</span><strong>{selected.ratings}</strong></div><div><span>Fiscal framework</span><strong>{selected.rules}</strong></div><div><span>Average maturity</span><strong>{selected.maturity}</strong></div></div>
        </article>

        <article className="fiscal-spread-card">
          <div className="panel-head"><div><p className="panel-kicker">Market pricing</p><h3 className="panel-title">10Y sovereign spread vs Bund</h3></div><span className="asof">Indicative · bp</span></div>
          <div className="spread-list">{fiscalCountries.filter((country) => country.id !== "de").map((country) => <button className="spread-row" key={country.id} onClick={() => setSelectedId(country.id)} type="button"><span>{country.flag}</span><div><i data-signal={country.signal} style={{ width: `${Math.max(5, country.spread / maxSpread * 100)}%` }} /></div><strong>{country.spread}</strong></button>)}</div>
          <p className="source-note">Market spreads are an indicative dashboard snapshot and should be connected to the live rates feed before trading use.</p>
        </article>
      </div>

      <FiscalSpreadHistory rows={spreadHistory} />

      <article className="fiscal-matrix-card">
        <div className="panel-head"><div><p className="panel-kicker">Cross-country screen</p><h3 className="panel-title">The fiscal map at a glance</h3></div><span className="asof">EC Spring Forecast · 21 May 2026</span></div>
        <div className="fiscal-table-wrap"><table className="fiscal-table"><thead><tr><th>Country</th><th>2026 balance</th><th>2026 debt</th><th>Primary</th><th>Interest</th><th>Issuance</th><th>10Y spread</th><th>EU / national rule</th></tr></thead><tbody>{fiscalCountries.map((country) => <tr data-selected={country.id === selected.id} key={country.id} onClick={() => setSelectedId(country.id)}><td><i data-signal={country.signal} />{country.name}</td><td>{country.balance[1].toFixed(1)}%</td><td>{country.debt[1].toFixed(1)}%</td><td>{country.primary.toFixed(1)}%</td><td>{country.interest.toFixed(1)}%</td><td>{country.issuance}</td><td>{country.id === "de" ? "—" : `${country.spread}bp`}</td><td>{country.rules}</td></tr>)}</tbody></table></div>
        <p className="source-note">Sources: European Commission Spring 2026 forecast; national debt-management offices; Eurostat EDP notifications; rating agencies. UK figures follow the OBR/D​​MO framework. Primary balances, interest costs, ratings, maturities and market spreads use latest available or indicative snapshots and retain their own reference periods.</p>
      </article>
      </>}
    </section>
  );
}

function G10FiscalMonitor({ composition, history }: { composition: G10CompositionRow[]; history: G10FiscalRow[] }) {
  const [selectedScopes, setSelectedScopes] = useState<string[]>(["MAE"]);
  const [startYear, setStartYear] = useState(2010);
  const toggleScope = (code: string) => {
    setSelectedScopes((current) => {
      if (current.includes(code)) return current.length === 1 ? current : current.filter((item) => item !== code);
      return current.length < 2 ? [...current, code] : [current[0], code];
    });
  };
  const charts = [
    { title: "General government fiscal balances", kicker: "Fiscal stance", first: "overall_balance", second: "primary_balance", firstLabel: "Overall balance", secondLabel: "Primary balance", zero: true },
    { title: "General government revenue and primary expenditure", kicker: "Size of government", first: "revenue", second: "primary_expenditure", firstLabel: "Revenue", secondLabel: "Primary expenditure" },
    { title: "General government gross and net debt", kicker: "Debt stock", first: "gross_debt", second: "net_debt", firstLabel: "Gross debt", secondLabel: "Net debt" },
  ];

  return <section className="g10-monitor">
    <div className="g10-intro">
      <div><p className="panel-kicker">G10 Fiscal Monitor</p><h2>Fiscal trajectories since the pandemic</h2><p>Long-run general-government balances, spending and debt. The first release covers the G7 core with an official IMF aggregate.</p></div>
      <span className="g10-badge">G7 core · MVP</span>
    </div>
    <div className="g10-toolbar">
      <div className="g10-scope-picker" aria-label="G7 country comparison">
        {g10Scopes.map(([code, name]) => <button aria-pressed={selectedScopes.includes(code)} data-active={selectedScopes.includes(code)} key={code} onClick={() => toggleScope(code)} type="button"><i style={{ background: g10ScopeColors[code] }} />{name}</button>)}
      </div>
      <div className="g10-range-picker" aria-label="History range">
        {[{ year: 2010, label: "2010–2031" }, { year: 2019, label: "2019–2031" }].map((option) => <button data-active={startYear === option.year} key={option.year} onClick={() => setStartYear(option.year)} type="button">{option.label}</button>)}
      </div>
    </div>
    <p className="g10-selection-note">Select up to two economies. Solid/dashed styles distinguish the two measures; lighter forecast segments show IMF estimates and projections.</p>
    <div className="g10-chart-grid">
      {charts.map((chart) => <G10LineChart config={chart} key={chart.title} rows={history} scopes={selectedScopes} startYear={startYear} />)}
      <G10CompositionChart rows={composition} scopes={selectedScopes} />
    </div>
    <div className="g10-method-note"><strong>Methodology.</strong> IMF April 2026 vintage. Primary expenditure equals revenue minus the primary balance. Net-debt gaps are not interpolated. The 2025 expenditure mix is an estimate using the latest available OECD/Statistics Canada functional shares, SIPRI military spending and IMF interest costs.</div>
  </section>;
}

function G10LineChart({ config, rows, scopes, startYear }: { config: { title: string; kicker: string; first: string; second: string; firstLabel: string; secondLabel: string; zero?: boolean }; rows: G10FiscalRow[]; scopes: string[]; startYear: number }) {
  const width = 720, height = 330, margin = { top: 24, right: 20, bottom: 38, left: 54 };
  const innerWidth = width - margin.left - margin.right, innerHeight = height - margin.top - margin.bottom;
  const chartRows = rows.filter((row) => scopes.includes(row.scopeCode) && row.year >= startYear && [config.first, config.second].includes(row.seriesId));
  if (!chartRows.length) return <article className="g10-chart-card"><p className="panel-kicker">{config.kicker}</p><h3>{config.title}</h3><p className="source-note">Waiting for fiscal-history data.</p></article>;
  const values = chartRows.map((row) => row.value);
  let min = Math.min(...values), max = Math.max(...values);
  if (config.zero) { min = Math.min(min, 0); max = Math.max(max, 0); }
  const padding = Math.max(1, (max - min) * .1); min -= padding; max += padding;
  const scaleX = (year: number) => margin.left + (year - startYear) / (2031 - startYear) * innerWidth;
  const scaleY = (value: number) => margin.top + (1 - (value - min) / (max - min)) * innerHeight;
  const yTicks = Array.from({ length: 5 }, (_, index) => min + (max - min) * index / 4);
  const xTickCandidates = startYear === 2010 ? [2010, 2015, 2020, 2025, 2031] : [2019, 2021, 2023, 2025, 2027, 2031];
  const makePath = (points: G10FiscalRow[]) => points.map((point, index) => `${index === 0 || point.year - points[index - 1].year > 1 ? "M" : "L"}${scaleX(point.year).toFixed(2)},${scaleY(point.value).toFixed(2)}`).join(" ");
  const plotted = scopes.flatMap((scopeCode) => [config.first, config.second].map((seriesId, seriesIndex) => {
    const points = chartRows.filter((row) => row.scopeCode === scopeCode && row.seriesId === seriesId).sort((a, b) => a.year - b.year);
    const actual = points.filter((point) => point.status === "actual");
    const forecast = points.filter((point) => point.status !== "actual");
    const lastActual = actual.at(-1);
    return { scopeCode, seriesId, seriesIndex, points, actual, forecast: lastActual && forecast.length ? [lastActual, ...forecast] : forecast };
  }));

  return <article className="g10-chart-card">
    <div className="g10-chart-head"><div><p className="panel-kicker">{config.kicker}</p><h3>{config.title}</h3></div><span>% of GDP</span></div>
    <div className="g10-metric-legend"><span><i />{config.firstLabel}</span><span><i data-dashed="true" />{config.secondLabel}</span></div>
    <svg aria-label={`${config.title}, percent of GDP`} role="img" viewBox={`0 0 ${width} ${height}`}>
      <rect className="g10-pandemic-band" x={scaleX(2020)} y={margin.top} width={Math.max(0, scaleX(2022) - scaleX(2020))} height={innerHeight} />
      <rect className="g10-forecast-band" x={scaleX(2025)} y={margin.top} width={Math.max(0, scaleX(2031) - scaleX(2025))} height={innerHeight} />
      {yTicks.map((tick) => <g key={tick}><line className="grid-line" x1={margin.left} x2={width - margin.right} y1={scaleY(tick)} y2={scaleY(tick)} /><text textAnchor="end" x={margin.left - 8} y={scaleY(tick) + 4}>{tick.toFixed(0)}</text></g>)}
      {xTickCandidates.map((year) => <text key={year} textAnchor="middle" x={scaleX(year)} y={height - 10}>{year}</text>)}
      {config.zero && min < 0 && max > 0 ? <line className="g10-zero" x1={margin.left} x2={width - margin.right} y1={scaleY(0)} y2={scaleY(0)} /> : null}
      <text className="g10-zone-label" x={scaleX(2020) + 5} y={margin.top + 13}>pandemic</text><text className="g10-zone-label" x={scaleX(2025) + 5} y={margin.top + 13}>estimate / projection</text>
      {plotted.map((series) => <g key={`${series.scopeCode}-${series.seriesId}`}>
        {series.actual.length ? <path className="g10-line" d={makePath(series.actual)} stroke={g10ScopeColors[series.scopeCode]} strokeDasharray={series.seriesIndex ? "7 5" : undefined} /> : null}
        {series.forecast.length ? <path className="g10-line g10-line-forecast" d={makePath(series.forecast)} stroke={g10ScopeColors[series.scopeCode]} strokeDasharray={series.seriesIndex ? "9 4 2 4" : "2 4"} /> : null}
        {series.points.map((point) => <circle className="g10-hit" cx={scaleX(point.year)} cy={scaleY(point.value)} key={point.year} r="7"><title>{`${point.scopeName} · ${point.seriesName} · ${point.year}: ${point.value.toFixed(1)}% (${point.status})`}</title></circle>)}
      </g>)}
    </svg>
    <div className="g10-scope-legend">{scopes.map((code) => <span key={code}><i style={{ background: g10ScopeColors[code] }} />{g10Scopes.find(([scope]) => scope === code)?.[1]}</span>)}</div>
    <p className="source-note">Source: <a href="https://www.imf.org/external/datamapper/datasets/FM" rel="noreferrer" target="_blank">IMF Fiscal Monitor</a> and <a href="https://data.imf.org/Datasets/WEO" rel="noreferrer" target="_blank">WEO</a>, April 2026 vintage. Missing observations are left blank.</p>
  </article>;
}

function G10CompositionChart({ rows, scopes }: { rows: G10CompositionRow[]; scopes: string[] }) {
  const width = 720, height = 330, margin = { top: 24, right: 20, bottom: 54, left: 54 };
  const components = [
    ["mandatory_proxy", "Social protection + health", "#204f86"],
    ["other_primary", "Other primary", "#b8b3a7"],
    ["military", "Military", "#a83f39"],
    ["interest", "Interest", "#c47a20"],
  ] as const;
  const bars = scopes.flatMap((scopeCode) => [2019, 2025].map((year) => ({ scopeCode, year, rows: rows.filter((row) => row.scopeCode === scopeCode && row.year === year) })));
  const totals = bars.map((bar) => bar.rows.reduce((sum, row) => sum + row.value, 0));
  if (!totals.some((value) => value > 0)) return <article className="g10-chart-card"><p className="panel-kicker">Expenditure mix</p><h3>Breakdown of total government expenditure</h3><p className="source-note">Waiting for composition data.</p></article>;
  const max = Math.ceil(Math.max(...totals) / 10) * 10, innerWidth = width - margin.left - margin.right, innerHeight = height - margin.top - margin.bottom;
  const scaleY = (value: number) => margin.top + (1 - value / max) * innerHeight;
  const yTicks = Array.from({ length: max / 10 + 1 }, (_, index) => index * 10);
  const barWidth = scopes.length > 1 ? 72 : 104, gap = (innerWidth - bars.length * barWidth) / (bars.length + 1);
  const shortNames: Record<string, string> = { MAE: "G7", USA: "US", JPN: "JP", DEU: "DE", FRA: "FR", GBR: "UK", ITA: "IT", CAN: "CA" };
  return <article className="g10-chart-card">
    <div className="g10-chart-head"><div><p className="panel-kicker">Expenditure mix</p><h3>Breakdown of total government expenditure</h3></div><span>2019 vs 2025e · % GDP</span></div>
    <div className="g10-component-legend">{components.map(([id, name, color]) => <span key={id}><i style={{ background: color }} />{name}</span>)}</div>
    <svg aria-label="Breakdown of total government expenditure in 2019 and 2025" role="img" viewBox={`0 0 ${width} ${height}`}>
      {yTicks.map((tick) => <g key={tick}><line className="grid-line" x1={margin.left} x2={width - margin.right} y1={scaleY(tick)} y2={scaleY(tick)} /><text textAnchor="end" x={margin.left - 8} y={scaleY(tick) + 4}>{tick}</text></g>)}
      {bars.map((bar, barIndex) => {
        const x = margin.left + gap + barIndex * (barWidth + gap); let accumulated = 0;
        return <g key={`${bar.scopeCode}-${bar.year}`}>{components.map(([id, name, color]) => {
          const value = bar.rows.find((row) => row.componentId === id)?.value ?? 0, y = scaleY(accumulated + value), rectHeight = scaleY(accumulated) - y; accumulated += value;
          return <g key={id}><rect fill={color} height={rectHeight} width={barWidth} x={x} y={y}><title>{`${name}: ${value.toFixed(1)}% of GDP`}</title></rect>{rectHeight > 18 ? <text className="g10-bar-value" textAnchor="middle" x={x + barWidth / 2} y={y + rectHeight / 2 + 4}>{value.toFixed(1)}</text> : null}</g>;
        })}<text className="g10-bar-label" textAnchor="middle" x={x + barWidth / 2} y={height - 27}>{shortNames[bar.scopeCode]}</text><text className="g10-bar-year" textAnchor="middle" x={x + barWidth / 2} y={height - 10}>{bar.year === 2025 ? "2025e" : "2019"}</text></g>;
      })}
    </svg>
    <p className="source-note">Sources: IMF, <a href="https://data-explorer.oecd.org/vis?df[ag]=OECD.GOV.GIP&df[ds]=dsDisseminateFinalDMZ&df[id]=DSD_GOV_COFOG@DF_GOV_COFOG_2025" rel="noreferrer" target="_blank">OECD COFOG</a>, Statistics Canada and <a href="https://www.sipri.org/databases/milex" rel="noreferrer" target="_blank">SIPRI</a>. “Mandatory” is a harmonised proxy for social protection plus health; other primary expenditure is the residual.</p>
  </article>;
}

function FiscalSpreadHistory({ rows }: { rows: FiscalSpreadRow[] }) {
  const configs = [
    ["FR", "France", "#a83f39"], ["IT", "Italy", "#11675f"],
    ["ES", "Spain", "#204f86"], ["PT", "Portugal", "#6c5f8d"],
    ["EL", "Greece", "#c47a20"], ["UK", "United Kingdom", "#111111"],
  ] as const;
  if (!rows.length) return null;
  const minTime = parseTime("1990-01-01");
  const maxTime = Math.max(...rows.map((row) => row.time));

  return (
    <article className="fiscal-matrix-card fiscal-history-card">
      <div className="panel-head"><div><p className="panel-kicker">History since 1990</p><h3 className="panel-title">10Y sovereign spreads vs Bund</h3></div><span className="asof">Monthly · basis points</span></div>
      <div className="spread-small-grid">
        {configs.map(([code, name, color]) => <FiscalSpreadChart color={color} key={code} maxTime={maxTime} minTime={minTime} name={name} rows={rows.filter((row) => row.country === code)} />)}
      </div>
      <p className="source-note">Source: <a href="https://ec.europa.eu/eurostat/databrowser/view/irt_lt_mcby_m/default/table" rel="noreferrer" target="_blank">Eurostat / ECB Maastricht criterion long-term interest rates</a>. Greece starts in September 1992. The UK series is a Gilt–Bund yield differential and therefore also reflects different currencies and monetary regimes.</p>
    </article>
  );
}

function FiscalSpreadChart({ color, maxTime, minTime, name, rows }: { color: string; maxTime: number; minTime: number; name: string; rows: FiscalSpreadRow[] }) {
  if (!rows.length) return null;
  const width = 520, height = 250, margin = { top: 18, right: 18, bottom: 30, left: 48 };
  const innerWidth = width - margin.left - margin.right, innerHeight = height - margin.top - margin.bottom;
  const spreadValues = rows.map((row) => row.spread);
  const rawMin = Math.min(0, ...spreadValues), rawMax = Math.max(0, ...spreadValues);
  const padding = Math.max(15, (rawMax - rawMin) * 0.08), min = rawMin - padding, max = rawMax + padding;
  const scaleX = (time: number) => margin.left + (time - minTime) / (maxTime - minTime) * innerWidth;
  const scaleY = (value: number) => margin.top + (1 - (value - min) / (max - min)) * innerHeight;
  const path = rows.map((row, index) => `${index ? "L" : "M"}${scaleX(row.time).toFixed(2)},${scaleY(row.spread).toFixed(2)}`).join(" ");
  const latest = rows[rows.length - 1], peak = rows.reduce((highest, row) => row.spread > highest.spread ? row : highest);
  const years = [1990, 2000, 2010, 2020, new Date(maxTime).getFullYear()].filter((year, index, values) => values.indexOf(year) === index);
  const yTicks = Array.from({ length: 4 }, (_, index) => min + (max - min) * index / 3);

  return <section className="spread-small"><div className="spread-small-head"><h4>{name}</h4><span>Latest {latest.spread.toFixed(0)}bp · Peak {peak.spread.toFixed(0)}bp</span></div><svg aria-label={`${name} 10-year spread versus Bund since 1990`} role="img" viewBox={`0 0 ${width} ${height}`}>{yTicks.map((tick) => <g key={tick}><line className="grid-line" x1={margin.left} x2={width - margin.right} y1={scaleY(tick)} y2={scaleY(tick)} /><text textAnchor="end" x={margin.left - 7} y={scaleY(tick) + 3}>{Math.round(tick)}</text></g>)}{years.map((year) => <text key={year} textAnchor="middle" x={scaleX(parseTime(`${year}-01-01`))} y={height - 8}>{year}</text>)}{min < 0 && max > 0 ? <line className="spread-zero" x1={margin.left} x2={width - margin.right} y1={scaleY(0)} y2={scaleY(0)} /> : null}<path className="spread-history-path" d={path} stroke={color} /><circle cx={scaleX(latest.time)} cy={scaleY(latest.spread)} fill={color} r="3"><title>{latest.date}: {latest.spread} bp</title></circle></svg></section>;
}

function FiscalStat({ label, value, note }: { label: string; value: string; note: string }) {
  return <div className="fiscal-stat"><span>{label}</span><strong>{value}</strong><small>{note}</small></div>;
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

  return <StandardTimeSeriesChart definition={definition} rows={rows} />;
}

function StandardTimeSeriesChart({
  definition,
  rows,
}: {
  definition: ChartDefinition;
  rows: SeriesRow[];
}) {
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
                background: item.dashArray || item.bar ? "transparent" : item.color,
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
    rightDomain,
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
        item.bar ? (
          <g clipPath={`url(#${clipId})`} key={item.id}>
            {item.points.map((point) => {
              const y = scaleY(point.value, item.axis);
              const baseline = scaleY(rightDomain.min, item.axis);
              const barWidth = Math.max(1.5, Math.min(8, (innerWidth / Math.max(item.points.length, 1)) * 0.8));
              return <rect fill={item.color} fillOpacity={0.8} height={Math.max(0, baseline - y)} key={`${item.id}-${point.date}`} width={barWidth} x={scaleX(point.time) - barWidth / 2} y={y} />;
            })}
          </g>
        ) :
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
            d={pathForSeries(item, scaleX, scaleY, definition)}
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
  if (seriesId === "wage_tracker_coverage") {
    return { color: "#e2e2e2", bar: true };
  }
  if (seriesId === "indeed_wage_tracker_yoy") {
    return { color: "#216e39" };
  }
  if (seriesId === "ecb_negotiated_wages") {
    return { color: "#a83f39", dashArray: "7 4" };
  }
  if (seriesId === "wage_tracker_ea") {
    return { color: "#0057b8" };
  }
  if (seriesId === "wage_tracker_ea_monthly") {
    return { color: "#0057b8", dashArray: "5 4" };
  }
  if (seriesId === "wage_tracker_unsmoothed") {
    return { color: "#ff6f00" };
  }
  if (seriesId === "wage_tracker_excluding") {
    return { color: "#7a3db8" };
  }
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
  if (metricId === "hicp_headline_pc_pcci_3m_saar") {
    return { color: "#11675f", dashArray: "2 4" };
  }
  if (metricId === "hicp_headline_pc_pcci_3m_saar_ma3") {
    return { color: "#b9dfd4" };
  }
  if (metricId === "ecb_spf_hicp_3q_ahead") {
    return { color: "#7a4db3", dashArray: "5 4" };
  }
  if (metricId === "ecb_spf_hicp_7q_ahead") {
    return { color: "#c17a2c", dashArray: "5 4" };
  }
  if (metricId === "ecb_spf_hicp_2y_ahead") {
    return { color: "#2f7db7", dashArray: "5 4" };
  }
  if (metricId === "ecb_spf_hicp_lt") {
    return { color: "#11675f", dashArray: "5 4" };
  }
  if (metricId === "ifo_mfg_prices_de") {
    return { color: "#003399" };
  }
  if (metricId === "ifo_services_prices_de") {
    return { color: "#ff7800" };
  }
  if (metricId === "ifo_food_prices_de") {
    return { color: "#cccccc" };
  }
  if (metricId === "ifo_chemical_prices_de") {
    return { color: "#8eb4e2" };
  }
  if (metricId === "hicp_neig_yoy_nsa") {
    return { color: "#111111" };
  }
  if (metricId === "hicp_neig_qoq_saar_3mma") {
    return { color: "#a83f39" };
  }
  if (metricId === "ec_industry_prices_6m_lag") {
    return { color: "#11675f" };
  }
  if (metricId === "ec_retail_prices_6m_lag") {
    return { color: "#d68b2d", dashArray: "6 5" };
  }
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
  definition: ChartDefinition,
) {
  const maxGap = definition.id === "ge_ifo_price_expectations"
    ? 62 * 24 * 60 * 60 * 1000
    : Number.POSITIVE_INFINITY;

  return series.points
    .map((point, index) => {
      const previous = series.points[index - 1];
      const command = index === 0 || point.time - previous.time > maxGap ? "M" : "L";
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
