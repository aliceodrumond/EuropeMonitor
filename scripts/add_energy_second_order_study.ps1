$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$path = Join-Path $root "reports\inflation_monitor.xlsx"
$tmpPath = Join-Path $env:TEMP "inflation_monitor_energy_study.xlsx"
$backupPath = Join-Path $root ("reports\inflation_monitor.backup-before-energy-study-mom." + (Get-Date -Format "yyyyMMdd-HHmmss") + ".xlsx")

$colors = @{
  bg = 0xF5F5F7; paper = 0xFFFFFF; ink = 0x151515; muted = 0x636A6D; line = 0xD2DBDE
  teal = 0x5F6711; blue = 0x643720; amber = 0x207AC4; red = 0x393FA8; green = 0x527F3F; violet = 0x8D5F6C
  heatRed = 0xDDEEFF; heatWhite = 0xFFFFFF; heatGreen = 0xE4F1E6
}

function To-Number($text) {
  $s = ([string]$text).Trim()
  if ($s -eq "" -or $s -eq "--") { return $null }
  $v = 0.0
  if ([double]::TryParse($s, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $v }
  if ([double]::TryParse($s, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::CurrentCulture, [ref]$v)) { return $v }
  return $null
}

function Set-Title($ws, [string]$range, [string]$title) {
  $ws.Range($range).Merge() | Out-Null
  $cell = $ws.Range(($range -split ":")[0])
  $cell.Value2 = $title
  $cell.Font.Size = 18
  $cell.Font.Bold = $true
  $cell.Font.Color = $colors.ink
  $cell.Interior.Color = $colors.bg
}

function Get-Channel($name, $pathText) {
  $n = $name.ToLowerInvariant()
  $t = (($name + " " + $pathText).ToLowerInvariant())
  if ($n -match "gas|electricity|liquid fuels|solid fuels|heating|cooling|fuels and lubricants|energy") { return "Direto energia" }
  if ($t -match "passenger transport|transport by air|transport by road|transport by sea|transport services|transport equipment|goods transport|maintenance and repair of personal transport") { return "Transporte e frete" }
  if ($t -match "package holidays|accommodation|restaurant|cafes|food and beverage serving") { return "Turismo/restaurantes" }
  if ($t -match "food|cereals|meat|fish|dairy|oils|fruits|vegetables|sugar|ready-made|processed food|alcohol|tobacco") { return "Alimentos/processados" }
  if ($t -match "repair|maintenance|cleaning|hire|rental|services related") { return "Servicos intensivos em custos" }
  if ($t -match "household appliances|glassware|furniture|textiles|clothing|footwear|tools|equipment|non energy industrial goods|newspapers|books|stationery|games|photographic|recreational durables") { return "Bens industriais" }
  return ""
}

function Get-Relevance($channel) {
  switch ($channel) {
    "Direto energia" { return 5 }
    "Transporte e frete" { return 4 }
    "Turismo/restaurantes" { return 3 }
    "Alimentos/processados" { return 3 }
    "Bens industriais" { return 2 }
    "Servicos intensivos em custos" { return 2 }
    default { return 0 }
  }
}

function Get-Block($name, $pathText) {
  $t = (($name + " " + $pathText).ToLowerInvariant())
  if ($t -match "services|service|passenger transport|transport by air|transport by road|transport by sea|package holidays|accommodation|restaurant|cafes|canteens|repair|maintenance|cleaning|hire|rental|insurance|personal care|transport services") {
    return "Services"
  }
  if ($t -match "food|beverages|alcohol|tobacco|electricity|gas|fuel|energy|furniture|appliances|glassware|tools|equipment|clothing|footwear|books|newspapers|software|recording media|games|toys|durables|goods|cereals|meat|fish|dairy|oils|fruits|vegetables|sugar") {
    return "Goods"
  }
  return "Goods"
}

Copy-Item -LiteralPath $path -Destination $backupPath -Force

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$wb = $excel.Workbooks.Open($path)
$ab = $wb.Worksheets.Item("Aberturas MoM")
$used = $ab.UsedRange

$rows = New-Object System.Collections.Generic.List[object]
$stack = @{}
for ($r = 2; $r -le $used.Rows.Count; $r++) {
  $raw = [string]$ab.Cells.Item($r,1).Text
  if ($raw.Trim() -eq "") { continue }
  $indent = $raw.Length - $raw.TrimStart().Length
  $level = [int][Math]::Floor($indent / 4)
  $name = $raw.Trim()
  $may = To-Number $ab.Cells.Item($r,2).Text
  $apr = To-Number $ab.Cells.Item($r,3).Text
  $delta = if ($null -ne $may -and $null -ne $apr) { [Math]::Round($may - $apr, 2) } else { $null }
  $stack[$level] = $name
  $pathParts = @()
  for ($i = 0; $i -le $level; $i++) { if ($stack.ContainsKey($i)) { $pathParts += $stack[$i] } }
  $rows.Add([pscustomobject]@{
    Row = $r; Level = $level; Component = $name; Path = ($pathParts -join " > ")
    Apr = $apr; May = $may; Delta = $delta; IsLeaf = $true; Channel = ""; Relevance = 0
  }) | Out-Null
}

for ($i = 0; $i -lt $rows.Count - 1; $i++) {
  if ($rows[$i+1].Level -gt $rows[$i].Level) { $rows[$i].IsLeaf = $false }
}

foreach ($row in $rows) {
  $row.Channel = Get-Channel $row.Component $row.Path
  $row.Relevance = Get-Relevance $row.Channel
}

$studyName = "Estudo Energia"
foreach ($ws in @($wb.Worksheets)) {
  if ($ws.Name -eq $studyName) { $ws.Delete(); break }
}
$ws = $wb.Worksheets.Add()
$ws.Name = $studyName

Set-Title $ws "A1:H1" "Resumo para reuniao: efeitos de energia em MoM"
$summaryHeaders = @("Canal", "Componente granular", "Mai/26", "Abr/26", "Delta p.p.", "Leitura", "Hierarquia")

foreach ($row in $rows) {
  $row | Add-Member -NotePropertyName Block -NotePropertyValue (Get-Block $row.Component $row.Path)
}

$rOut = 3
foreach ($block in @("Goods", "Services")) {
  $ws.Range("A$rOut:G$rOut").Merge() | Out-Null
  $ws.Cells.Item($rOut,1).Value2 = $block
  $ws.Cells.Item($rOut,1).Font.Bold = $true
  $ws.Cells.Item($rOut,1).Font.Size = 13
  $ws.Cells.Item($rOut,1).Interior.Color = if ($block -eq "Goods") { $colors.bg } else { 0xEFEDE8 }
  $rOut++
  for ($c=0; $c -lt $summaryHeaders.Count; $c++) {
    $ws.Cells.Item($rOut,$c+1).Value2 = $summaryHeaders[$c]
    $ws.Cells.Item($rOut,$c+1).Font.Bold = $true
    $ws.Cells.Item($rOut,$c+1).Interior.Color = $colors.bg
  }
  $rOut++
  $summary = $rows |
    Where-Object { $_.IsLeaf -and $_.Relevance -gt 0 -and $_.Block -eq $block -and $null -ne $_.Delta } |
    Sort-Object @{ Expression = { [Math]::Abs($_.Delta) }; Descending = $true }, @{ Expression = "Relevance"; Descending = $true } |
    Select-Object -First 12
  foreach ($row in $summary) {
    $direction = if ($row.Delta -gt 0) { "Subiu" } elseif ($row.Delta -lt 0) { "Caiu" } else { "Estavel" }
    $read = $direction + " " + ([Math]::Abs($row.Delta)).ToString("0.0", [Globalization.CultureInfo]::InvariantCulture) + " p.p. MoM; canal: " + $row.Channel
    $ws.Cells.Item($rOut,1).Value2 = $row.Channel
    $ws.Cells.Item($rOut,2).Value2 = $row.Component
    $ws.Cells.Item($rOut,3).Value2 = [double]$row.May
    $ws.Cells.Item($rOut,4).Value2 = [double]$row.Apr
    $ws.Cells.Item($rOut,5).Value2 = [double]$row.Delta
    $ws.Cells.Item($rOut,6).Value2 = $read
    $ws.Cells.Item($rOut,7).Value2 = $row.Path
    $rOut++
  }
  $rOut += 2
}
$ws.Range("C3:E$rOut").NumberFormat = "0.0"
$ws.Range("A3:G$($rOut-1)").Borders.Color = $colors.line

$heatStart = $rOut + 2
Set-Title $ws "A$heatStart:J$heatStart" "Heatmap granular MoM: Abril, Maio e espaco para Junho"
$heatHeaders = @("Canal", "Relevancia", "Nivel", "Componente", "Abr/26", "Mai/26", "Delta Mai-Abr", "Jun/26", "Delta Jun-Mai", "Hierarquia")
for ($c=0; $c -lt $heatHeaders.Count; $c++) {
  $ws.Cells.Item($heatStart+2,$c+1).Value2 = $heatHeaders[$c]
  $ws.Cells.Item($heatStart+2,$c+1).Font.Bold = $true
  $ws.Cells.Item($heatStart+2,$c+1).Interior.Color = $colors.bg
}

$heat = $rows |
  Where-Object { $_.IsLeaf -and $_.Relevance -gt 0 } |
  Sort-Object @{ Expression = "Relevance"; Descending = $true }, Channel, Component

$rOut = $heatStart + 3
foreach ($row in $heat) {
  $ws.Cells.Item($rOut,1).Value2 = $row.Channel
  $ws.Cells.Item($rOut,2).Value2 = [double]$row.Relevance
  $ws.Cells.Item($rOut,3).Value2 = [double]$row.Level
  $ws.Cells.Item($rOut,4).Value2 = $row.Component
  if ($null -ne $row.Apr) { $ws.Cells.Item($rOut,5).Value2 = [double]$row.Apr }
  if ($null -ne $row.May) { $ws.Cells.Item($rOut,6).Value2 = [double]$row.May }
  if ($null -ne $row.Delta) { $ws.Cells.Item($rOut,7).Value2 = [double]$row.Delta }
  $ws.Cells.Item($rOut,9).Formula = "=IF(OR(H$rOut="""",F$rOut=""""),"""",H$rOut-F$rOut)"
  $ws.Cells.Item($rOut,10).Value2 = $row.Path
  $rOut++
}
$lastHeat = $rOut - 1
$firstHeatData = $heatStart + 3
$headerHeat = $heatStart + 2
$ws.Range("E$firstHeatData:I$lastHeat").NumberFormat = "0.0"
$ws.Range("A$headerHeat:J$lastHeat").Borders.Color = $colors.line
$ws.Range("G$firstHeatData:G$lastHeat").FormatConditions.AddColorScale(3) | Out-Null
$cs = $ws.Range("G$firstHeatData:G$lastHeat").FormatConditions.Item(1)
$cs.ColorScaleCriteria.Item(1).FormatColor.Color = $colors.heatGreen
$cs.ColorScaleCriteria.Item(2).FormatColor.Color = $colors.heatWhite
$cs.ColorScaleCriteria.Item(3).FormatColor.Color = $colors.heatRed
$ws.Range("I$firstHeatData:I$lastHeat").FormatConditions.AddColorScale(3) | Out-Null
$cs2 = $ws.Range("I$firstHeatData:I$lastHeat").FormatConditions.Item(1)
$cs2.ColorScaleCriteria.Item(1).FormatColor.Color = $colors.heatGreen
$cs2.ColorScaleCriteria.Item(2).FormatColor.Color = $colors.heatWhite
$cs2.ColorScaleCriteria.Item(3).FormatColor.Color = $colors.heatRed

$ws.Cells.Item($heatStart-2,1).Value2 = "Nota: selecao feita sobre folhas da hierarquia da aba Aberturas MoM. Canais indicam sensibilidade potencial a Brent/gas; nao sao atribuicoes causais mecanicas."
$ws.Cells.Item(20,1).Font.Color = $colors.muted
$ws.Columns.Item(1).ColumnWidth = 24
$ws.Columns.Item(2).ColumnWidth = 10
$ws.Columns.Item(3).ColumnWidth = 8
$ws.Columns.Item(4).ColumnWidth = 52
$ws.Columns.Item(5).ColumnWidth = 10
$ws.Columns.Item(6).ColumnWidth = 10
$ws.Columns.Item(7).ColumnWidth = 14
$ws.Columns.Item(8).ColumnWidth = 10
$ws.Columns.Item(9).ColumnWidth = 14
$ws.Columns.Item(10).ColumnWidth = 90
$ws.Range("A$headerHeat:J$headerHeat").AutoFilter() | Out-Null
$ws.Activate()
$ws.Range("A$firstHeatData").Select() | Out-Null
$excel.ActiveWindow.FreezePanes = $true

Remove-Item -LiteralPath $tmpPath -ErrorAction SilentlyContinue
$wb.SaveCopyAs($tmpPath)
$wb.Close($false)
$excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
Copy-Item -LiteralPath $tmpPath -Destination $path -Force

Write-Host "Updated: $path"
Write-Host "Backup: $backupPath"
