$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Rscript = "C:\Program Files\R\R-4.3.1\bin\Rscript.exe"
$Git = "C:\Users\alice.drumond\AppData\Local\Programs\Git\cmd\git.exe"
$Npm = "C:\Program Files\nodejs\npm.cmd"
$Npx = "C:\Program Files\nodejs\npx.cmd"
$LogDir = Join-Path $ProjectRoot "logs"
$LogPath = Join-Path $LogDir ("speakers-update-" + (Get-Date -Format "yyyy-MM-dd") + ".log")

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

function Test-SpeakersOutput {
  $speakersPath = Join-Path $ProjectRoot "public\data\ecb_speakers.csv"
  if (-not (Test-Path -LiteralPath $speakersPath)) {
    throw "Missing required file: $speakersPath"
  }

  $speakers = @(Import-Csv $speakersPath)
  if ($speakers.Count -lt 10) {
    throw "ECB Speakers has only $($speakers.Count) rows; refusing to publish"
  }
  if (@($speakers | Where-Object { $_.tags -eq "fallback" }).Count -gt 0) {
    throw "ECB Speakers is fallback data; refusing to publish"
  }
  $priorityMembers = @("Lagarde", "Lane", "Nagel")
  $presentPriorityMembers = @($speakers | Where-Object { $_.member -in $priorityMembers } | Select-Object -ExpandProperty member -Unique)
  if ($presentPriorityMembers.Count -lt 1) {
    throw "ECB Speakers is missing all priority members; refusing to publish"
  }
  $missingPriorityMembers = @($priorityMembers | Where-Object { $_ -notin $presentPriorityMembers })
  if ($missingPriorityMembers.Count -gt 0) {
    Write-Log "Warning: ECB Speakers missing priority members in this run: $($missingPriorityMembers -join ', ')"
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

function Invoke-SpeakersPipeline {
  Invoke-Logged -FilePath $Rscript -Arguments @("R\run_speakers_update.R")
  Test-SpeakersOutput

  Invoke-Logged -FilePath $Npm -Arguments @("run", "build")
  Test-SpeakersOutput

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

  $PreviousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $Git add public/data/ecb_speakers.csv data/processed/ecb_speakers.csv R/fetch_ecb_speakers.R R/run_speakers_update.R scripts/update-speakers-and-publish.ps1 2>&1 | ForEach-Object { Write-Log $_ }
    & $Git diff --cached --quiet
    $HasChanges = $LASTEXITCODE -ne 0
  } finally {
    $ErrorActionPreference = $PreviousErrorActionPreference
  }
  if ($HasChanges) {
    Invoke-Logged -FilePath $Git -Arguments @("commit", "-m", "Update ECB speakers $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    Invoke-Logged -FilePath $Git -Arguments @("push")
  } else {
    Write-Log "No ECB speaker changes to commit"
  }
}

Write-Log "Starting Europe monitor speakers-only update"

$MaxAttempts = 3
for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
  try {
    if ($Attempt -gt 1) {
      Write-Log "Retrying speakers-only update after previous failure; attempt $Attempt of $MaxAttempts"
    }
    Invoke-SpeakersPipeline
    Write-Log "Europe monitor speakers-only update completed"
    exit 0
  } catch {
    $Message = $_.Exception.Message
    Write-Log "Speakers-only update attempt $Attempt of $MaxAttempts failed: $Message"
    if ($Attempt -ge $MaxAttempts) {
      Write-Log "Europe monitor speakers-only update FAILED after $MaxAttempts attempts"
      throw
    }
    $DelaySeconds = 60 * $Attempt
    Write-Log "Waiting $DelaySeconds seconds before retrying speakers-only update"
    Start-Sleep -Seconds $DelaySeconds
  }
}
