$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$path = Join-Path $root "reports\inflation_monitor.xlsx"
$tmpPath = Join-Path $env:TEMP "inflation_monitor_energy_indices.xlsx"
$backupPath = Join-Path $root ("reports\inflation_monitor.backup-before-energy-indices." + (Get-Date -Format "yyyyMMdd-HHmmss") + ".xlsx")

$colors = @{
  bg = 0xF5F5F7; paper = 0xFFFFFF; ink = 0x151515; muted = 0x636A6D; line = 0xD2DBDE
  teal = 0x5F6711; blue = 0x643720; amber = 0x207AC4; red = 0x393FA8; green = 0x527F3F; violet = 0x8D5F6C
}

function To-Number($text) {
  $s = ([string]$text).Trim()
  if ($s -eq "" -or $s -eq "--") { return $null }
  $v = 0.0
  if ([double]::TryParse($s, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $v }
  if ([double]::TryParse($s, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::CurrentCulture, [ref]$v)) { return $v }
  return $null
}

function Get-Channel($name, $pathText) {
  $n = $name.ToLowerInvariant()
  $t = (($name + " " + $pathText).ToLowerInvariant())
  if ($n -match "^excluding|non energy|nonenergy") { return "" }
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

function Get-DateColumns($ws) {
  $used = $ws.UsedRange
  $cols = New-Object System.Collections.Generic.List[object]
  for ($c = 2; $c -le $used.Columns.Count; $c++) {
    $label = ([string]$ws.Cells.Item(1,$c).Text).Trim()
    if ($label -eq "") { continue }
    try {
      $dt = [datetime]::ParseExact($label, "MMM yyyy", [Globalization.CultureInfo]::InvariantCulture)
    } catch {
      try { $dt = [datetime]::Parse($label, [Globalization.CultureInfo]::InvariantCulture) } catch { continue }
    }
    $cols.Add([pscustomobject]@{ Col = $c; Label = $label; Date = $dt }) | Out-Null
  }
  return @($cols | Sort-Object Date)
}

function Read-ComponentRows($wsMom, $wsYoy, $wsWeights, $dateCols) {
  $used = $wsMom.UsedRange
  $rows = New-Object System.Collections.Generic.List[object]
  $stack = @{}
  for ($r = 2; $r -le $used.Rows.Count; $r++) {
    $raw = [string]$wsMom.Cells.Item($r,1).Text
    if ($raw.Trim() -eq "") { continue }
    $indent = $raw.Length - $raw.TrimStart().Length
    $level = [int][Math]::Floor($indent / 4)
    $name = $raw.Trim()
    $stack[$level] = $name
    $pathParts = @()
    for ($i = 0; $i -le $level; $i++) { if ($stack.ContainsKey($i)) { $pathParts += $stack[$i] } }
    $pathText = ($pathParts -join " > ")
    $channel = Get-Channel $name $pathText
    $mom = @{}
    $yoy = @{}
    foreach ($dc in $dateCols) {
      $key = $dc.Date.ToString("yyyy-MM")
      $mom[$key] = To-Number $wsMom.Cells.Item($r,$dc.Col).Text
      $yoy[$key] = To-Number $wsYoy.Cells.Item($r,$dc.Col).Text
    }
    $rows.Add([pscustomobject]@{
      Row = $r; Level = $level; Component = $name; Path = $pathText; IsLeaf = $true
      Channel = $channel; Relevance = Get-Relevance $channel
      Weight = To-Number $wsWeights.Cells.Item($r,2).Text
      Mom = $mom
      Yoy = $yoy
    }) | Out-Null
  }
  for ($i = 0; $i -lt $rows.Count - 1; $i++) {
    if ($rows[$i+1].Level -gt $rows[$i].Level) { $rows[$i].IsLeaf = $false }
  }
  return $rows
}

function WeightedAvg($items, [string]$kind, [string]$key) {
  $valid = @($items | Where-Object { $null -ne $_.Weight -and $null -ne $_.$kind[$key] })
  $sumW = ($valid | Measure-Object -Property Weight -Sum).Sum
  if ($null -eq $sumW -or $sumW -eq 0) { return $null }
  $num = 0.0
  foreach ($item in $valid) { $num += ([double]$item.Weight * [double]$item.$kind[$key]) }
  return [Math]::Round($num / [double]$sumW, 3)
}

function Add-LineChart($ws, [string]$title, [string]$xRange, [string]$yRange, [int]$left, [int]$top, [int]$width, [int]$height, [int]$color) {
  $obj = $ws.ChartObjects().Add($left, $top, $width, $height)
  $chart = $obj.Chart
  $chart.ChartType = 4
  $s = $chart.SeriesCollection().NewSeries()
  $s.Name = $title
  $s.XValues = $ws.Range($xRange)
  $s.Values = $ws.Range($yRange)
  $s.Format.Line.ForeColor.RGB = $color
  $s.Format.Line.Weight = 2.25
  $chart.HasTitle = $true
  $chart.ChartTitle.Text = $title
  $chart.ChartArea.Format.Fill.ForeColor.RGB = $colors.paper
  $chart.ChartArea.Format.Line.ForeColor.RGB = $colors.line
  $chart.PlotArea.Format.Fill.ForeColor.RGB = $colors.paper
  $chart.Legend.Delete()
}

Copy-Item -LiteralPath $path -Destination $backupPath -Force

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$wb = $excel.Workbooks.Open($path)

$wsMom = $wb.Worksheets.Item("Aberturas MoM")
$wsYoy = $wb.Worksheets.Item("Aberturas")
$wsWeights = $wb.Worksheets.Item("Pesos")
$dateCols = Get-DateColumns $wsMom
$rows = Read-ComponentRows $wsMom $wsYoy $wsWeights $dateCols

$baseRows = @($rows | Where-Object { $_.IsLeaf -and $_.Path -notmatch "CORE SERIES & SPECIAL AGGREGATES" -and $_.Component -notmatch "^Excluding" -and $null -ne $_.Weight })
$direct = @($baseRows | Where-Object { $_.Relevance -eq 5 })
$second = @($baseRows | Where-Object { $_.Relevance -eq 4 -or $_.Relevance -eq 3 })

$sheetName = "Indices Energia"
foreach ($ws in @($wb.Worksheets)) {
  if ($ws.Name -eq $sheetName) { $ws.Delete(); break }
}
$ws = $wb.Worksheets.Add()
$ws.Name = $sheetName

$ws.Range("A1:H1").Merge() | Out-Null
$ws.Range("A1").Value2 = "Indices ponderados de energia e segunda ordem"
$ws.Range("A1").Font.Size = 18
$ws.Range("A1").Font.Bold = $true
$ws.Range("A1").Interior.Color = $colors.bg

$headers = @("Date", "Direto energia R5 %MoM", "Direto energia R5 %YoY", "R4+R3 %MoM", "R4+R3 %YoY")
for ($c=0; $c -lt $headers.Count; $c++) {
  $ws.Cells.Item(3,$c+1).Value2 = $headers[$c]
  $ws.Cells.Item(3,$c+1).Font.Bold = $true
  $ws.Cells.Item(3,$c+1).Interior.Color = $colors.bg
}
$dates = @()
foreach ($dc in $dateCols) {
  $key = $dc.Date.ToString("yyyy-MM")
  $dates += @{
    Label = $dc.Date.ToString("MMM-yy", [Globalization.CultureInfo]::InvariantCulture)
    DirectMom = WeightedAvg $direct "Mom" $key
    DirectYoy = WeightedAvg $direct "Yoy" $key
    SecondMom = WeightedAvg $second "Mom" $key
    SecondYoy = WeightedAvg $second "Yoy" $key
  }
}
$lastDate = if ($dateCols.Count -gt 0) { $dateCols[-1].Date } else { [datetime]"2026-05-01" }
$nextDate = $lastDate.AddMonths(1)
$dates += @{
  Label = $nextDate.ToString("MMM-yy", [Globalization.CultureInfo]::InvariantCulture)
  DirectMom = $null; DirectYoy = $null; SecondMom = $null; SecondYoy = $null
}
$r = 4
foreach ($d in $dates) {
  $ws.Cells.Item($r,1).Value2 = $d.Label
  if ($null -ne $d.DirectMom) { $ws.Cells.Item($r,2).Value2 = [double]$d.DirectMom }
  if ($null -ne $d.DirectYoy) { $ws.Cells.Item($r,3).Value2 = [double]$d.DirectYoy }
  if ($null -ne $d.SecondMom) { $ws.Cells.Item($r,4).Value2 = [double]$d.SecondMom }
  if ($null -ne $d.SecondYoy) { $ws.Cells.Item($r,5).Value2 = [double]$d.SecondYoy }
  $r++
}
$lastData = $r - 1
$ws.Range("B4:E$lastData").NumberFormat = "0.0"
$ws.Range("A3:E$lastData").Borders.Color = $colors.line

$notesRow = $lastData + 2
$ws.Cells.Item($notesRow,1).Value2 = "Criterio"
$ws.Cells.Item($notesRow,1).Font.Bold = $true
$ws.Cells.Item($notesRow+1,1).Value2 = "R5: itens folha classificados como Direto energia. R4+R3: itens folha classificados como transporte/frete, turismo/restaurantes e alimentos/processados."
$ws.Cells.Item($notesRow+2,1).Value2 = "Agregacao: media ponderada pelas ponderacoes 2026 da aba Pesos, normalizadas dentro de cada cesta."
$ws.Cells.Item($notesRow+3,1).Value2 = ($nextDate.ToString("MMM-yy", [Globalization.CultureInfo]::InvariantCulture) + " foi deixado em branco para preenchimento/recalculo posterior.")
$ws.Range("A$($notesRow+1):A$($notesRow+3)").Font.Color = $colors.muted

$componentsTitleRow = $notesRow + 5
$componentsHeaderRow = $componentsTitleRow + 1
$ws.Cells.Item($componentsTitleRow,1).Value2 = "Componentes usados"
$ws.Cells.Item($componentsTitleRow,1).Font.Bold = $true
$compHeaders = @("Cesta", "Relevancia", "Canal", "Peso", "Componente", "Hierarquia")
for ($c=0; $c -lt $compHeaders.Count; $c++) {
  $ws.Cells.Item($componentsHeaderRow,$c+1).Value2 = $compHeaders[$c]
  $ws.Cells.Item($componentsHeaderRow,$c+1).Font.Bold = $true
  $ws.Cells.Item($componentsHeaderRow,$c+1).Interior.Color = $colors.bg
}
$r = $componentsHeaderRow + 1
foreach ($item in @($direct + $second | Sort-Object Relevance, Channel, Component)) {
  $ws.Cells.Item($r,1).Value2 = if ($item.Relevance -eq 5) { "Direto energia R5" } else { "R4+R3" }
  $ws.Cells.Item($r,2).Value2 = [double]$item.Relevance
  $ws.Cells.Item($r,3).Value2 = $item.Channel
  $ws.Cells.Item($r,4).Value2 = [double]$item.Weight
  $ws.Cells.Item($r,5).Value2 = $item.Component
  $ws.Cells.Item($r,6).Value2 = $item.Path
  $r++
}
$lastComp = $r - 1
$ws.Range("D$($componentsHeaderRow+1):D$lastComp").NumberFormat = "0.00"
$ws.Range("A$componentsHeaderRow:F$lastComp").Borders.Color = $colors.line

Add-LineChart $ws "Direto energia R5 %MoM" "A4:A$lastData" "B4:B$lastData" 390 55 380 230 $colors.teal
Add-LineChart $ws "Direto energia R5 %YoY" "A4:A$lastData" "C4:C$lastData" 790 55 380 230 $colors.blue
Add-LineChart $ws "R4+R3 %MoM" "A4:A$lastData" "D4:D$lastData" 390 310 380 230 $colors.amber
Add-LineChart $ws "R4+R3 %YoY" "A4:A$lastData" "E4:E$lastData" 790 310 380 230 $colors.red

$ws.Columns.Item(1).ColumnWidth = 22
$ws.Columns.Item(2).ColumnWidth = 18
$ws.Columns.Item(3).ColumnWidth = 18
$ws.Columns.Item(4).ColumnWidth = 14
$ws.Columns.Item(5).ColumnWidth = 48
$ws.Columns.Item(6).ColumnWidth = 90
$ws.Activate()

Remove-Item -LiteralPath $tmpPath -ErrorAction SilentlyContinue
$wb.SaveCopyAs($tmpPath)
$wb.Close($false)
$excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
Copy-Item -LiteralPath $tmpPath -Destination $path -Force

Write-Host "Updated: $path"
Write-Host "Backup: $backupPath"
Write-Host ("Direct components: " + $direct.Count)
Write-Host ("R4+R3 components: " + $second.Count)
