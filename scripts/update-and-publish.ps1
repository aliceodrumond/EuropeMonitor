$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Rscript = "C:\Program Files\R\R-4.3.1\bin\Rscript.exe"
$Git = "C:\Users\alice.drumond\AppData\Local\Programs\Git\cmd\git.exe"
$LogDir = Join-Path $ProjectRoot "logs"
$LogPath = Join-Path $LogDir ("daily-update-" + (Get-Date -Format "yyyy-MM-dd") + ".log")

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Set-Location $ProjectRoot

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

Write-Log "Starting Europe monitor update"

Invoke-Logged -FilePath $Rscript -Arguments @("R\run_daily_update.R")

& $Git add public/data data/processed

$PendingChanges = & $Git status --porcelain public/data data/processed
if (-not $PendingChanges) {
  Write-Log "No data changes to publish"
  exit 0
}

$CommitMessage = "Update Europe monitor data $(Get-Date -Format "yyyy-MM-dd")"
Invoke-Logged -FilePath $Git -Arguments @("commit", "-m", $CommitMessage)
Invoke-Logged -FilePath $Git -Arguments @("push")

Write-Log "Europe monitor update published"
