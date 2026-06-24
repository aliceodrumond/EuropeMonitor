$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Rscript = "C:\Program Files\R\R-4.3.1\bin\Rscript.exe"
$Git = "C:\Users\alice.drumond\AppData\Local\Programs\Git\cmd\git.exe"
$Npm = "C:\Program Files\nodejs\npm.cmd"
$Npx = "C:\Program Files\nodejs\npx.cmd"
$LogDir = Join-Path $ProjectRoot "logs"
$LogPath = Join-Path $LogDir ("daily-update-" + (Get-Date -Format "yyyy-MM-dd") + ".log")

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Set-Location $ProjectRoot

$env:PATH = "C:\Program Files\nodejs;" + $env:PATH
$env:NODE_USE_SYSTEM_CA = "1"
$env:BUILD_OUT_DIR = "pages-dist"
$env:CLOUDFLARE_API_TOKEN = [Environment]::GetEnvironmentVariable("CLOUDFLARE_API_TOKEN", "User")
$env:CLOUDFLARE_ACCOUNT_ID = [Environment]::GetEnvironmentVariable("CLOUDFLARE_ACCOUNT_ID", "User")

function Write-Log {
  param([string]$Message)
  $Line = "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $Message"
  Add-Content -Path $LogPath -Value $Line
  Write-Output $Line
}

function Invoke-Logged {
  param(
    [string]$FilePath,
    [string[]]$Arguments
  )

  Write-Log ("Running: " + $FilePath + " " + ($Arguments -join " "))
  $PreviousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $FilePath @Arguments 2>&1 | ForEach-Object { Write-Log $_ }
    if ($LASTEXITCODE -ne 0) {
      throw "$FilePath exited with code $LASTEXITCODE"
    }
  } finally {
    $ErrorActionPreference = $PreviousErrorActionPreference
  }
}

function Assert-FileExists {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing required file: $Path"
  }
}

function Assert-ChartRows {
  param(
    [object[]]$Rows,
    [string]$ChartId,
    [int]$MinimumRows = 1
  )
  $count = @($Rows | Where-Object { $_.chart_id -eq $ChartId }).Count
  if ($count -lt $MinimumRows) {
    throw "Chart $ChartId has $count rows; expected at least $MinimumRows"
  }
  Write-Log "Validated chart ${ChartId}: ${count} rows"
}

function Assert-SeriesRows {
  param(
    [object[]]$Rows,
    [string]$SeriesId,
    [int]$MinimumRows = 1
  )
  $seriesRows = @($Rows | Where-Object { $_.series_id -eq $SeriesId })
  if ($seriesRows.Count -lt $MinimumRows) {
    throw "Series $SeriesId has $($seriesRows.Count) rows; expected at least $MinimumRows"
  }
  $last = $seriesRows[-1]
  Write-Log "Validated series ${SeriesId}: $($seriesRows.Count) rows, last=$($last.date), value=$($last.value)"
}

function Test-OutputData {
  $activityPath = Join-Path $ProjectRoot "public\data\activity_series.csv"
  $inflationPath = Join-Path $ProjectRoot "public\data\inflation_series.csv"
  $speakersPath = Join-Path $ProjectRoot "public\data\ecb_speakers.csv"
  $metadataPath = Join-Path $ProjectRoot "public\data\metadata.json"

  Assert-FileExists $activityPath
  Assert-FileExists $inflationPath
  Assert-FileExists $speakersPath
  Assert-FileExists $metadataPath

  $activity = @(Import-Csv $activityPath)
  $inflation = @(Import-Csv $inflationPath)
  $speakers = @(Import-Csv $speakersPath)

  foreach ($chart in @(
    "pmi_ea_aggregate",
    "pmi_composite",
    "pmi_manufacturing",
    "pmi_services",
    "pmi_gdp",
    "bls_credit_standards",
    "bls_loan_demand",
    "bls_credit_factors",
    "ifo_headline",
    "ifo_sectors",
    "sentix_pmi",
    "zew_sentiment",
    "weekly_activity",
    "toll_mileage"
  )) {
    Assert-ChartRows -Rows $activity -ChartId $chart -MinimumRows 1
  }

  foreach ($series in @(
    "pmi_ea_aggregate",
    "pmi_mfg_ea_aggregate",
    "pmi_srv_ea_aggregate",
    "pmi_ea",
    "pmi_mfg_ea",
    "pmi_srv_ea",
    "pmi_ea_gdp",
    "gdp_qoq_sa_ea",
    "gdp_qoq_sa_bls_standards",
    "gdp_qoq_sa_bls_demand",
    "bls_standards_corporate_ea",
    "bls_standards_consumer_ea",
    "bls_demand_corporate_ea",
    "bls_demand_consumer_ea",
    "bls_factor_capital_ea",
    "bls_factor_market_financing_ea",
    "bls_factor_liquidity_ea",
    "bls_factor_econ_outlook_ea",
    "bls_factor_industry_firm_ea",
    "bls_factor_collateral_ea",
    "ifo_business_climate_de",
    "ifo_current_assessment_de",
    "ifo_expectations_de",
    "ifo_mfg_climate_de",
    "ifo_retail_climate_de",
    "ifo_services_climate_de",
    "ifo_construction_climate_de",
    "wai_de",
    "toll_de",
    "toll_de_daily",
    "sentix_ea",
    "zew_de"
  )) {
    Assert-SeriesRows -Rows $activity -SeriesId $series -MinimumRows 1
  }

  foreach ($chart in @(
    "hicp_headline_rates",
    "hicp_core_rates",
    "hicp_goods_rates",
    "hicp_services_rates",
    "hicp_headline_core",
    "hicp_components",
    "expected_selling_prices",
    "wage_tracker"
  )) {
    Assert-ChartRows -Rows $inflation -ChartId $chart -MinimumRows 1
  }

  foreach ($series in @(
    "hicp_headline_yoy_nsa",
    "hicp_headline_qoq_saar",
    "hicp_headline_mom_saar",
    "hicp_core_yoy_nsa",
    "hicp_core_qoq_saar",
    "hicp_core_mom_saar",
    "hicp_goods_yoy_nsa",
    "hicp_goods_qoq_saar",
    "hicp_goods_mom_saar",
    "hicp_services_yoy_nsa",
    "hicp_services_qoq_saar",
    "hicp_services_mom_saar",
    "hicp_headline",
    "hicp_core",
    "core_services",
    "core_goods",
    "esp_services",
    "core_services_expected",
    "wage_tracker_ea"
  )) {
    Assert-SeriesRows -Rows $inflation -SeriesId $series -MinimumRows 1
  }

  if ($speakers.Count -lt 5) {
    throw "ECB Speakers has only $($speakers.Count) rows; refusing to publish"
  }
  if (@($speakers | Where-Object { $_.tags -eq "fallback" }).Count -gt 0) {
    throw "ECB Speakers is fallback data; refusing to publish"
  }
  foreach ($speaker in $speakers) {
    $comment = [string]$speaker.policy_comments
    if ([string]::IsNullOrWhiteSpace($comment)) {
      throw "ECB Speakers row for $($speaker.date) $($speaker.member) has empty Policy comments"
    }
    if ($comment -ne "No comments relevant for monetary policy") {
      $parts = @($comment -split "\s+\|\s+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      if ($parts.Count -lt 1 -or $parts.Count -gt 3) {
        throw "Policy comments for $($speaker.date) $($speaker.member) must have 1-3 snippets; found $($parts.Count): $comment"
      }
      if ($comment -match "^(European Central Bank|ECB)\s+(President|Chief Economist|Executive Board member|Governing Council member|Vice[- ]President)\b") {
        throw "Policy comments for $($speaker.date) $($speaker.member) starts with boilerplate title/name: $comment"
      }
    }
  }
  Write-Log "Validated ECB Speakers: $($speakers.Count) rows, first=$($speakers[0].date) $($speakers[0].member)"
}

Write-Log "Starting Europe monitor full update"

Invoke-Logged -FilePath $Rscript -Arguments @("R\run_daily_update.R")
Test-OutputData

Invoke-Logged -FilePath $Npm -Arguments @("run", "build")
Test-OutputData

Invoke-Logged -FilePath $Npx -Arguments @(
  "wrangler",
  "pages",
  "deploy",
  "pages-dist/client",
  "--project-name",
  "legacy-europe-monitor",
  "--branch",
  "main"
)

if (Test-Path -LiteralPath $Git) {
  & $Git add public/data data/processed data/raw config R app scripts package.json package-lock.json
  $PendingChanges = & $Git status --porcelain public/data data/processed data/raw config R app scripts package.json package-lock.json
  if ($PendingChanges) {
    $CommitMessage = "Update Europe monitor data $(Get-Date -Format "yyyy-MM-dd HH:mm")"
    Invoke-Logged -FilePath $Git -Arguments @("commit", "-m", $CommitMessage)
    Invoke-Logged -FilePath $Git -Arguments @("push")
  } else {
    Write-Log "No git changes to commit"
  }
}

Write-Log "Europe monitor full update completed"
