param(
  [ValidateSet("LegacyX13", "OfficialEcbSa")]
  [string]$Mode = "LegacyX13"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Rscript = "C:\Program Files\R\R-4.3.1\bin\Rscript.exe"
$Git = "C:\Users\alice.drumond\AppData\Local\Programs\Git\cmd\git.exe"
$Npm = "C:\Program Files\nodejs\npm.cmd"
$Npx = "C:\Program Files\nodejs\npx.cmd"
$PinkBaseUrl = "http://127.0.0.1:8766"
$PinkTo = "5531988380196"
$N8NRoot = "C:\Users\alice.drumond\OneDrive - Legacy Capital Gestora de Recursos Ltda\Documents\N8N"
$PublishedUrl = "https://legacy-europe-monitor.pages.dev"
$LogDir = Join-Path $ProjectRoot "logs"
$ModeSlug = if ($Mode -eq "OfficialEcbSa") { "official-ecb-sa" } else { "legacy-x13" }
$LogPath = Join-Path $LogDir ("inflation-fast-$ModeSlug-update-" + (Get-Date -Format "yyyy-MM-dd") + ".log")

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Set-Location $ProjectRoot

$env:PATH = "C:\Program Files\nodejs;" + $env:PATH
$env:NODE_USE_SYSTEM_CA = "1"
$env:BUILD_OUT_DIR = "pages-dist"
$env:CLOUDFLARE_API_TOKEN = [Environment]::GetEnvironmentVariable("CLOUDFLARE_API_TOKEN", "User")
$env:CLOUDFLARE_ACCOUNT_ID = [Environment]::GetEnvironmentVariable("CLOUDFLARE_ACCOUNT_ID", "User")
$env:INFLATION_FAST_MODE = if ($Mode -eq "OfficialEcbSa") { "official_ecb_sa" } else { "legacy_x13" }

function Write-Log {
  param([string]$Message)
  $Line = "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $Message"
  Add-Content -Path $LogPath -Value $Line
  Write-Output $Line
}

function Test-WhatsPinkHealth {
  try {
    Invoke-RestMethod -Method Get -Uri "$PinkBaseUrl/health" -TimeoutSec 5 | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Start-WhatsPinkIfNeeded {
  if (Test-WhatsPinkHealth) {
    Write-Log "Whats-Pink is reachable at $PinkBaseUrl"
    return
  }

  $startScript = Join-Path $N8NRoot "start_whats_pink_server.ps1"
  if (-not (Test-Path -LiteralPath $startScript)) {
    throw "Cannot start Whats-Pink; missing $startScript"
  }

  Write-Log "Whats-Pink is not reachable; starting the local service"
  Start-Process powershell.exe `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $startScript) `
    -WindowStyle Hidden

  for ($attempt = 1; $attempt -le 12; $attempt++) {
    Start-Sleep -Seconds 5
    if (Test-WhatsPinkHealth) {
      Write-Log "Whats-Pink started successfully"
      return
    }
  }

  throw "Whats-Pink did not become reachable after 60 seconds"
}

function Get-InflationStatusLines {
  $inflationPath = Join-Path $ProjectRoot "public\data\inflation_series.csv"
  if (-not (Test-Path -LiteralPath $inflationPath)) {
    return @("Dados locais: arquivo inflation_series.csv indisponivel")
  }

  $rows = @(Import-Csv $inflationPath)
  $suffix = if ($Mode -eq "OfficialEcbSa") { "" } else { "_legacy" }
  $components = [ordered]@{
    Headline = "hicp_headline_qoq_saar$suffix"
    Core = "hicp_core_qoq_saar$suffix"
    Goods = "hicp_goods_qoq_saar$suffix"
    Services = "hicp_services_qoq_saar$suffix"
  }

  $lines = foreach ($entry in $components.GetEnumerator()) {
    $latest = @($rows | Where-Object { $_.series_id -eq $entry.Value } | Sort-Object date)[-1]
    if ($null -eq $latest) {
      "$($entry.Key): indisponivel"
      continue
    }

    $dateLabel = try {
      ([datetime]::ParseExact(
        $latest.date,
        "yyyy-MM-dd",
        [System.Globalization.CultureInfo]::InvariantCulture
      )).ToString("MM/yyyy")
    } catch {
      $latest.date
    }
    "$($entry.Key): $dateLabel"
  }

  return @($lines)
}

function Send-PinkStatus {
  param(
    [ValidateSet("SUCESSO", "FALHA")]
    [string]$Status,
    [int]$DurationSeconds,
    [string]$ErrorMessage = ""
  )

  try {
    $modeLabel = if ($Mode -eq "OfficialEcbSa") { "ECB SA oficial" } else { "Eurostat NSA + X-13/X-11 Legacy" }
    $messageLines = @(
      "Inflation Monitor - $Status",
      "Horario: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') (America/Sao_Paulo)",
      "Processo: $modeLabel",
      "Duracao: ${DurationSeconds}s"
    )
    $messageLines += Get-InflationStatusLines
    if ($ErrorMessage) {
      $messageLines += "Erro: $ErrorMessage"
    }
    $messageLines += "Site: $PublishedUrl"

    Start-WhatsPinkIfNeeded
    $body = @{
      to = $PinkTo
      message = ($messageLines -join "`n")
      label = "Inflation Monitor $Mode $Status"
      dry_run = $false
      metadata = @{
        source = "Europe 2 Inflation Monitor"
        mode = $Mode
        status = $Status
        site = "legacy-europe-monitor"
        timezone = "America/Sao_Paulo"
      }
    } | ConvertTo-Json -Depth 4

    $response = Invoke-RestMethod `
      -Method Post `
      -Uri "$PinkBaseUrl/messages" `
      -ContentType "application/json" `
      -Headers @{ "X-Whats-Pink-Dry-Run" = "false" } `
      -Body $body `
      -TimeoutSec 60
    Write-Log "Pink status sent to +55 31 98838-0196; sent=$($response.sent), failed=$($response.failed)"
  } catch {
    Write-Log "WARNING: Pink status notification failed: $($_.Exception.Message)"
  }
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
    Invoke-Logged -FilePath $Git -Arguments @("commit", "-m", "Update inflation $Mode data $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    Invoke-Logged -FilePath $Git -Arguments @("push")
  } else {
    Write-Log "No $Mode inflation data changes to commit"
  }
}

$RunStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
Write-Log "Starting Europe monitor fast inflation update in $Mode mode"

$MaxAttempts = 2
for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
  try {
    if ($Attempt -gt 1) {
      Write-Log "Retrying $Mode inflation update after previous failure; attempt $Attempt of $MaxAttempts"
    }
    Invoke-FastInflationPipeline
    Write-Log "Europe monitor $Mode inflation update completed"
    $RunStopwatch.Stop()
    Send-PinkStatus -Status "SUCESSO" -DurationSeconds ([int][math]::Round($RunStopwatch.Elapsed.TotalSeconds))
    exit 0
  } catch {
    $FailureRecord = $_
    $Message = $FailureRecord.Exception.Message
    Write-Log "$Mode inflation update attempt $Attempt of $MaxAttempts failed: $Message"
    if ($Attempt -ge $MaxAttempts) {
      Write-Log "Europe monitor $Mode inflation update FAILED after $MaxAttempts attempts"
      $RunStopwatch.Stop()
      Send-PinkStatus `
        -Status "FALHA" `
        -DurationSeconds ([int][math]::Round($RunStopwatch.Elapsed.TotalSeconds)) `
        -ErrorMessage $Message
      throw $FailureRecord
    }
    Start-Sleep -Seconds 30
  }
}
