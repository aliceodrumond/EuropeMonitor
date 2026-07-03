$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Rscript = "C:\Program Files\R\R-4.3.1\bin\Rscript.exe"
$Npm = "C:\Program Files\nodejs\npm.cmd"
$Npx = "C:\Program Files\nodejs\npx.cmd"
$PinkBaseUrl = "http://127.0.0.1:8766"
$PinkTo = "5531988380196"
$N8NRoot = "C:\Users\alice.drumond\OneDrive - Legacy Capital Gestora de Recursos Ltda\Documents\N8N"
$LogDir = Join-Path $ProjectRoot "logs"
$LogPath = Join-Path $LogDir ("other-inflation-update-" + (Get-Date -Format "yyyy-MM-dd") + ".log")

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

function Assert-SeriesRows {
  param(
    [object[]]$Rows,
    [string]$SeriesId
  )
  $seriesRows = @($Rows | Where-Object { $_.series_id -eq $SeriesId })
  if ($seriesRows.Count -lt 1) {
    throw "Series $SeriesId has no rows"
  }
  $last = @($seriesRows | Sort-Object date)[-1]
  Write-Log "Validated series ${SeriesId}: $($seriesRows.Count) rows, last=$($last.date), value=$($last.value)"
}

function Assert-ChartRows {
  param(
    [object[]]$Rows,
    [string]$ChartId
  )
  $chartRows = @($Rows | Where-Object { $_.chart_id -eq $ChartId })
  if ($chartRows.Count -lt 1) {
    throw "Chart $ChartId has no rows"
  }
  Write-Log "Validated chart ${ChartId}: $($chartRows.Count) rows"
}

function Test-OtherInflationOutput {
  $inflationPath = Join-Path $ProjectRoot "public\data\inflation_series.csv"
  if (-not (Test-Path -LiteralPath $inflationPath)) {
    throw "Missing required file: $inflationPath"
  }
  $inflation = @(Import-Csv $inflationPath)

  foreach ($chart in @(
    "swiss_cpi_headline_rates",
    "swiss_cpi_core_rates",
    "swiss_cpi_goods_rates",
    "swiss_cpi_services_rates",
    "swiss_cpi_energy_fuels_rates",
    "swiss_cpi_headline_seasonality",
    "swiss_cpi_core_seasonality",
    "swiss_cpi_goods_seasonality",
    "swiss_cpi_services_seasonality",
    "swiss_cpi_energy_fuels_seasonality"
  )) {
    Assert-ChartRows -Rows $inflation -ChartId $chart
  }

  foreach ($series in @(
    "swiss_cpi_headline_yoy_nsa",
    "swiss_cpi_core_yoy_nsa",
    "swiss_cpi_goods_yoy_nsa",
    "swiss_cpi_services_yoy_nsa",
    "swiss_cpi_energy_fuels_yoy_nsa",
    "swiss_cpi_headline_mom_nsa_2026",
    "swiss_cpi_core_mom_nsa_2026",
    "swiss_cpi_goods_mom_nsa_2026",
    "swiss_cpi_services_mom_nsa_2026",
    "swiss_cpi_energy_fuels_mom_nsa_2026"
  )) {
    Assert-SeriesRows -Rows $inflation -SeriesId $series
  }
}

function Get-SeriesLatest {
  param(
    [object[]]$Rows,
    [string]$SeriesId
  )
  @($Rows | Where-Object { $_.series_id -eq $SeriesId } | Sort-Object date)[-1]
}

function Start-WhatsPinkIfNeeded {
  try {
    Invoke-RestMethod -Method Get -Uri "$PinkBaseUrl/sessions" -TimeoutSec 5 | Out-Null
    Write-Log "whats-pink is already reachable at $PinkBaseUrl"
    return
  } catch {
    Write-Log "whats-pink is not reachable at $PinkBaseUrl; trying to start local service"
  }

  $startScript = Join-Path $N8NRoot "start_whats_pink_server.ps1"
  if (-not (Test-Path -LiteralPath $startScript)) {
    throw "Cannot start whats-pink; missing $startScript"
  }

  Start-Process powershell.exe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $startScript) -WindowStyle Hidden
  for ($Attempt = 1; $Attempt -le 12; $Attempt++) {
    Start-Sleep -Seconds 5
    try {
      Invoke-RestMethod -Method Get -Uri "$PinkBaseUrl/sessions" -TimeoutSec 5 | Out-Null
      Write-Log "whats-pink started and is reachable at $PinkBaseUrl"
      return
    } catch {
      Write-Log "Waiting for whats-pink startup attempt $Attempt of 12"
    }
  }
  throw "whats-pink did not become reachable at $PinkBaseUrl"
}

function Send-JuneSuccessPinkNotification {
  $inflationPath = Join-Path $ProjectRoot "public\data\inflation_series.csv"
  $inflation = @(Import-Csv $inflationPath)
  $headline = Get-SeriesLatest -Rows $inflation -SeriesId "swiss_cpi_headline_yoy_nsa"
  if ($null -eq $headline -or $headline.date -ne "2026-06-01") {
    Write-Log "June Swiss CPI data is not available yet; latest headline YoY date is $($headline.date)"
    return
  }

  $markerPath = Join-Path $LogDir "other-inflation-pink-2026-06-01.sent"
  if (Test-Path -LiteralPath $markerPath) {
    Write-Log "June success Pink notification already sent; marker exists at $markerPath"
    return
  }

  $core = Get-SeriesLatest -Rows $inflation -SeriesId "swiss_cpi_core_yoy_nsa"
  $goods = Get-SeriesLatest -Rows $inflation -SeriesId "swiss_cpi_goods_yoy_nsa"
  $services = Get-SeriesLatest -Rows $inflation -SeriesId "swiss_cpi_services_yoy_nsa"
  $energy = Get-SeriesLatest -Rows $inflation -SeriesId "swiss_cpi_energy_fuels_yoy_nsa"
  $headlineMom = Get-SeriesLatest -Rows $inflation -SeriesId "swiss_cpi_headline_mom_nsa_2026"
  $headlineLine = "Headline: $($headline.value)% YoY"
  if ($headlineMom -and $headlineMom.value -ne "") {
    $headlineLine += ", $($headlineMom.value)% MoM NSA"
  }

  $message = @(
    "Other - Inflation Monitor atualizado com sucesso.",
    "Suica CPI junho 2026 publicado no site.",
    $headlineLine,
    "Core: $($core.value)% YoY",
    "Goods: $($goods.value)% YoY",
    "Services: $($services.value)% YoY",
    "Energy & fuels: $($energy.value)% YoY"
  ) -join "`n"

  Start-WhatsPinkIfNeeded
  $body = @{
    to = $PinkTo
    message = $message
    label = "Swiss CPI Jun 2026"
    dry_run = $false
    metadata = @{
      source = "Europe 2 Other Inflation Monitor"
      release_key = "swiss_cpi_2026_06"
      site = "legacy-europe-monitor"
    }
  } | ConvertTo-Json -Depth 4

  $response = Invoke-RestMethod `
    -Method Post `
    -Uri "$PinkBaseUrl/messages" `
    -ContentType "application/json" `
    -Headers @{ "X-Whats-Pink-Dry-Run" = "false" } `
    -Body $body `
    -TimeoutSec 60

  Set-Content -Path $markerPath -Value ("Sent at " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
  Write-Log ("Pink notification sent for June Swiss CPI. Response: " + (($response | ConvertTo-Json -Depth 4) -replace "`r?`n", " "))
}

function Invoke-WranglerPagesDeploy {
  $deployArgs = @("wrangler", "pages", "deploy", "pages-dist/client", "--project-name", "legacy-europe-monitor", "--branch", "main")

  try {
    Invoke-Logged -FilePath $Npx -Arguments $deployArgs
    return
  } catch {
    Write-Log ("Wrangler deploy failed on the first attempt: " + $_.Exception.Message)
    Write-Log "Retrying Wrangler deploy with NODE_TLS_REJECT_UNAUTHORIZED=0 for this process due to local TLS/fetch issues"
  }

  $previousNodeTls = $env:NODE_TLS_REJECT_UNAUTHORIZED
  try {
    $env:NODE_TLS_REJECT_UNAUTHORIZED = "0"
    Invoke-Logged -FilePath $Npx -Arguments $deployArgs
  } finally {
    if ($null -eq $previousNodeTls) {
      Remove-Item Env:NODE_TLS_REJECT_UNAUTHORIZED -ErrorAction SilentlyContinue
    } else {
      $env:NODE_TLS_REJECT_UNAUTHORIZED = $previousNodeTls
    }
  }
}

Write-Log "Starting Other - Inflation Monitor update"
Invoke-Logged -FilePath $Rscript -Arguments @("R\run_other_inflation_update.R")
Test-OtherInflationOutput
Invoke-Logged -FilePath $Npm -Arguments @("run", "build")
Test-OtherInflationOutput
Invoke-WranglerPagesDeploy
Send-JuneSuccessPinkNotification
Write-Log "Other - Inflation Monitor update completed"
