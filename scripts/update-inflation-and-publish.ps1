$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Rscript = "C:\Program Files\R\R-4.3.1\bin\Rscript.exe"
$Git = "C:\Users\alice.drumond\AppData\Local\Programs\Git\cmd\git.exe"
$Npm = "C:\Program Files\nodejs\npm.cmd"
$Npx = "C:\Program Files\nodejs\npx.cmd"
$LogDir = Join-Path $ProjectRoot "logs"
$LogPath = Join-Path $LogDir ("inflation-update-" + (Get-Date -Format "yyyy-MM-dd") + ".log")

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
  $Logged = $false
  for ($Attempt = 1; $Attempt -le 5 -and -not $Logged; $Attempt++) {
    try {
      Add-Content -Path $LogPath -Value $Line -ErrorAction Stop
      $Logged = $true
    } catch {
      if ($Attempt -lt 5) {
        Start-Sleep -Milliseconds 300
      }
    }
  }
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

function Test-InflationOutput {
  $inflationPath = Join-Path $ProjectRoot "public\data\inflation_series.csv"
  if (-not (Test-Path -LiteralPath $inflationPath)) {
    throw "Missing required file: $inflationPath"
  }
  $inflation = @(Import-Csv $inflationPath)

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
    "hicp_headline_hoh_saar",
    "hicp_headline_qoq_saar",
    "hicp_headline_mom_saar",
    "hicp_headline_hoh_saar_legacy",
    "hicp_headline_qoq_saar_legacy",
    "hicp_headline_mom_saar_legacy",
    "hicp_core_yoy_nsa",
    "hicp_core_hoh_saar",
    "hicp_core_qoq_saar",
    "hicp_core_mom_saar",
    "hicp_core_hoh_saar_legacy",
    "hicp_core_qoq_saar_legacy",
    "hicp_core_mom_saar_legacy",
    "hicp_goods_yoy_nsa",
    "hicp_goods_hoh_saar",
    "hicp_goods_qoq_saar",
    "hicp_goods_mom_saar",
    "hicp_goods_hoh_saar_legacy",
    "hicp_goods_qoq_saar_legacy",
    "hicp_goods_mom_saar_legacy",
    "hicp_services_yoy_nsa",
    "hicp_services_hoh_saar",
    "hicp_services_qoq_saar",
    "hicp_services_mom_saar",
    "hicp_services_hoh_saar_legacy",
    "hicp_services_qoq_saar_legacy",
    "hicp_services_mom_saar_legacy",
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
}

Write-Log "Starting Europe monitor inflation-only update"

Invoke-Logged -FilePath $Rscript -Arguments @("R\run_inflation_update.R")
Test-InflationOutput

Invoke-Logged -FilePath $Npm -Arguments @("run", "build")
Test-InflationOutput

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

& $Git add public/data/inflation_series.csv public/data/metadata.json data/processed/inflation_series.csv data/raw/eurostat_*.json data/raw/ecb_hicp_sa_*.csv 2>$null
& $Git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  Invoke-Logged -FilePath $Git -Arguments @("commit", "-m", "Update inflation monitor data $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
  Invoke-Logged -FilePath $Git -Arguments @("push")
} else {
  Write-Log "No inflation data changes to commit"
}

Write-Log "Europe monitor inflation-only update completed"
