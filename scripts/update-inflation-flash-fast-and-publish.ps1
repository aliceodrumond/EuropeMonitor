$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Rscript = "C:\Program Files\R\R-4.3.1\bin\Rscript.exe"
$Git = "C:\Users\alice.drumond\AppData\Local\Programs\Git\cmd\git.exe"
$Npm = "C:\Program Files\nodejs\npm.cmd"
$Npx = "C:\Program Files\nodejs\npx.cmd"
$LogDir = Join-Path $ProjectRoot "logs"
$LogPath = Join-Path $LogDir ("inflation-flash-fast-update-" + (Get-Date -Format "yyyy-MM-dd") + ".log")

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

function Invoke-WranglerDeploy {
  $DeployArgs = @(
    "wrangler",
    "pages",
    "deploy",
    "pages-dist/client",
    "--project-name",
    "legacy-europe-monitor",
    "--branch",
    "main"
  )

  try {
    Invoke-Logged -FilePath $Npx -Arguments $DeployArgs
  } catch {
    Write-Log "Wrangler deploy failed; retrying once with NODE_TLS_REJECT_UNAUTHORIZED=0 for corporate proxy/certificate issue"
    $PreviousTls = $env:NODE_TLS_REJECT_UNAUTHORIZED
    $env:NODE_TLS_REJECT_UNAUTHORIZED = "0"
    try {
      Invoke-Logged -FilePath $Npx -Arguments $DeployArgs
    } finally {
      if ($null -eq $PreviousTls) {
        Remove-Item Env:\NODE_TLS_REJECT_UNAUTHORIZED -ErrorAction SilentlyContinue
      } else {
        $env:NODE_TLS_REJECT_UNAUTHORIZED = $PreviousTls
      }
    }
  }
}

function Assert-SeriesRows {
  param([object[]]$Rows, [string]$SeriesId, [int]$MinimumRows = 1)
  $seriesRows = @($Rows | Where-Object { $_.series_id -eq $SeriesId })
  if ($seriesRows.Count -lt $MinimumRows) {
    throw "Series $SeriesId has $($seriesRows.Count) rows; expected at least $MinimumRows"
  }
  $last = @($seriesRows | Sort-Object date)[-1]
  Write-Log "Validated series ${SeriesId}: $($seriesRows.Count) rows, last=$($last.date), value=$($last.value)"
}

function Assert-ChartRows {
  param([object[]]$Rows, [string]$ChartId, [int]$MinimumRows = 1)
  $count = @($Rows | Where-Object { $_.chart_id -eq $ChartId }).Count
  if ($count -lt $MinimumRows) {
    throw "Chart $ChartId has $count rows; expected at least $MinimumRows"
  }
  Write-Log "Validated chart ${ChartId}: ${count} rows"
}

function Test-FastInflationOutput {
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
    "hicp_headline_seasonality",
    "hicp_core_seasonality",
    "hicp_goods_seasonality",
    "hicp_services_seasonality",
    "hicp_headline_core",
    "hicp_components"
  )) {
    Assert-ChartRows -Rows $inflation -ChartId $chart -MinimumRows 1
  }
  foreach ($series in @(
    "hicp_headline_yoy_nsa",
    "hicp_headline_mom_nsa_median",
    "hicp_headline_mom_nsa_2026",
    "hicp_headline_hoh_saar_legacy",
    "hicp_headline_qoq_saar",
    "hicp_headline_mom_saar",
    "hicp_headline_qoq_saar_legacy",
    "hicp_headline_mom_saar_legacy",
    "hicp_core_yoy_nsa",
    "hicp_core_mom_nsa_median",
    "hicp_core_mom_nsa_2026",
    "hicp_core_hoh_saar_legacy",
    "hicp_core_qoq_saar",
    "hicp_core_mom_saar",
    "hicp_core_qoq_saar_legacy",
    "hicp_core_mom_saar_legacy",
    "hicp_goods_yoy_nsa",
    "core_goods_mom_nsa_median",
    "core_goods_mom_nsa_2026",
    "hicp_goods_hoh_saar_legacy",
    "hicp_goods_qoq_saar",
    "hicp_goods_mom_saar",
    "hicp_goods_qoq_saar_legacy",
    "hicp_goods_mom_saar_legacy",
    "hicp_services_yoy_nsa",
    "core_services_mom_nsa_median",
    "core_services_mom_nsa_2026",
    "hicp_services_hoh_saar_legacy",
    "hicp_services_qoq_saar",
    "hicp_services_mom_saar",
    "hicp_services_qoq_saar_legacy",
    "hicp_services_mom_saar_legacy"
  )) {
    Assert-SeriesRows -Rows $inflation -SeriesId $series -MinimumRows 1
  }
}

function Invoke-FastInflationPipeline {
  Invoke-Logged -FilePath $Rscript -Arguments @("R\run_inflation_flash_fast_update.R")
  Test-FastInflationOutput
  Invoke-Logged -FilePath $Npm -Arguments @("run", "build")
  Test-FastInflationOutput
  Invoke-WranglerDeploy

  $PreviousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $Git add public/data/inflation_series.csv public/data/metadata.json data/processed/inflation_series.csv data/raw/eurostat_*.json data/raw/eurostat_prc_hicp_midx_*.json R/run_inflation_flash_fast_update.R scripts/update-inflation-flash-fast-and-publish.ps1 R/fetch_inflation.R 2>&1 | ForEach-Object { Write-Log $_ }
    & $Git diff --cached --quiet
    $HasChanges = $LASTEXITCODE -ne 0
  } finally {
    $ErrorActionPreference = $PreviousErrorActionPreference
  }
  if ($HasChanges) {
    Invoke-Logged -FilePath $Git -Arguments @("commit", "-m", "Update fast inflation flash data $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    Invoke-Logged -FilePath $Git -Arguments @("push")
  } else {
    Write-Log "No fast inflation data changes to commit"
  }
}

Write-Log "Starting Europe monitor fast inflation flash update"

$MaxAttempts = 2
for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
  try {
    if ($Attempt -gt 1) {
      Write-Log "Retrying fast inflation flash update after previous failure; attempt $Attempt of $MaxAttempts"
    }
    Invoke-FastInflationPipeline
    Write-Log "Europe monitor fast inflation flash update completed"
    exit 0
  } catch {
    $Message = $_.Exception.Message
    Write-Log "Fast inflation flash update attempt $Attempt of $MaxAttempts failed: $Message"
    if ($Attempt -ge $MaxAttempts) {
      Write-Log "Europe monitor fast inflation flash update FAILED after $MaxAttempts attempts"
      throw
    }
    Start-Sleep -Seconds 30
  }
}
