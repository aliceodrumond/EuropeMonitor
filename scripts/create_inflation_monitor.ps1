$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$out = Join-Path $root "reports\inflation_monitor.xlsx"

$colors = @{
  bg = 0xF5F5F7; paper = 0xFFFFFF; ink = 0x151515; muted = 0x636A6D; line = 0xD2DBDE
  teal = 0x5F6711; blue = 0x643720; amber = 0x207AC4; red = 0x393FA8; green = 0x527F3F; violet = 0x8D5F6C
}

function Set-Header($ws, [string]$title) {
  $ws.Range("A1:H1").Merge() | Out-Null
  $ws.Range("A1").Value2 = $title
  $ws.Range("A1").Font.Size = 18
  $ws.Range("A1").Font.Bold = $true
  $ws.Range("A1").Font.Color = $colors.ink
  $ws.Range("A1").Interior.Color = $colors.bg
}

function Add-LineChart($ws, [string]$name, [string]$title, [int[]]$cols, [int]$left, [int]$top, [int]$width, [int]$height) {
  $obj = $ws.ChartObjects().Add($left, $top, $width, $height)
  $chart = $obj.Chart
  $chart.ChartType = 4
  foreach ($col in $cols) {
    $s = $chart.SeriesCollection().NewSeries()
    $s.Name = $script:chartData.Cells.Item(3,$col).Value2
    $s.XValues = $script:chartData.Range($script:chartData.Cells.Item(4,1), $script:chartData.Cells.Item($script:lastRow,1))
    $s.Values = $script:chartData.Range($script:chartData.Cells.Item(4,$col), $script:chartData.Cells.Item($script:lastRow,$col))
  }
  $chart.HasTitle = $true
  $chart.ChartTitle.Text = $title
  $chart.ChartTitle.Format.TextFrame2.TextRange.Font.Fill.ForeColor.RGB = $colors.ink
  $chart.ChartArea.Format.Fill.ForeColor.RGB = $colors.paper
  $chart.ChartArea.Format.Line.ForeColor.RGB = $colors.line
  $chart.PlotArea.Format.Fill.ForeColor.RGB = $colors.paper
  $chart.Legend.Position = -4107
  $palette = @($colors.teal, $colors.blue, $colors.amber, $colors.red, $colors.green, $colors.violet)
  for ($i = 1; $i -le $chart.SeriesCollection().Count; $i++) {
    $s = $chart.SeriesCollection($i)
    $s.Format.Line.ForeColor.RGB = $palette[($i - 1) % $palette.Count]
    $s.Format.Line.Weight = 2
  }
  return $chart
}

function Add-ColumnChart($ws, [string]$title, [int[]]$cols, [int]$left, [int]$top, [int]$width, [int]$height) {
  $obj = $ws.ChartObjects().Add($left, $top, $width, $height)
  $chart = $obj.Chart
  $chart.ChartType = 52
  foreach ($col in $cols) {
    $s = $chart.SeriesCollection().NewSeries()
    $s.Name = $script:chartData.Cells.Item(3,$col).Value2
    $s.XValues = $script:chartData.Range($script:chartData.Cells.Item(4,1), $script:chartData.Cells.Item($script:lastRow,1))
    $s.Values = $script:chartData.Range($script:chartData.Cells.Item(4,$col), $script:chartData.Cells.Item($script:lastRow,$col))
  }
  $chart.HasTitle = $true
  $chart.ChartTitle.Text = $title
  $chart.ChartArea.Format.Fill.ForeColor.RGB = $colors.paper
  $chart.ChartArea.Format.Line.ForeColor.RGB = $colors.line
  $chart.Legend.Position = -4107
  $palette = @($colors.blue, $colors.amber, $colors.red, $colors.green)
  for ($i = 1; $i -le $chart.SeriesCollection().Count; $i++) {
    $chart.SeriesCollection($i).Format.Fill.ForeColor.RGB = $palette[($i - 1) % $palette.Count]
  }
  return $chart
}

function Read-LocalSeries($seriesId) {
  Import-Csv (Join-Path $root "public\data\inflation_series.csv") |
    Where-Object { $_.series_id -eq $seriesId } |
    Sort-Object date |
    ForEach-Object { [pscustomobject]@{ date = ([datetime]$_.date); value = [double]$_.value } }
}

$headline = Read-LocalSeries "hicp_headline_yoy_nsa"
$goods = Read-LocalSeries "hicp_goods_yoy_nsa"
$byDate = @{}
foreach ($row in $headline) { $byDate[$row.date.ToString("yyyy-MM")] = [ordered]@{ Date = $row.date; Headline = $row.value; Energy = $null; Gas = $null; Electricity = $null; LiquidFuels = $null; Other = $null; Goods = $null; PPIConsumerGoods6mLead = $null; PMIOutputPricesMfg12mLead = $null; GSCI_Agriculture = $null } }
foreach ($row in $goods) { $k = $row.date.ToString("yyyy-MM"); if ($byDate.Contains($k)) { $byDate[$k].Goods = $row.value } }

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$wb = $excel.Workbooks.Add()
while ($wb.Worksheets.Count -lt 4) { $wb.Worksheets.Add() | Out-Null }

$data = $wb.Worksheets.Item(1); $data.Name = "Data"
Set-Header $data "Inflation monitor data"
$headers = @("Date","HICP Headline %YoY","HICP Energy %YoY","Gas contribution","Electricity contribution","Liquid fuels contribution","Other energy contribution","HICP Goods %YoY","PPI Consumer Goods %YoY (6m lead)","PMI Output Prices - Manufacturing (12m lead)","S&P GSCI Agricultural Commodities Index")
for ($c=0; $c -lt $headers.Count; $c++) { $data.Cells.Item(3,$c+1).Value2 = $headers[$c]; $data.Cells.Item(3,$c+1).Font.Bold = $true; $data.Cells.Item(3,$c+1).Interior.Color = $colors.bg }
$r = 4
foreach ($k in ($byDate.Keys | Sort-Object)) {
  $row = $byDate[$k]
  $data.Cells.Item($r,1).Value = $row.Date
  $data.Cells.Item($r,1).NumberFormat = "mmm-yy"
  if ($null -ne $row.Headline) { $data.Cells.Item($r,2).Value2 = [double]$row.Headline }
  if ($null -ne $row.Goods) { $data.Cells.Item($r,8).Value2 = [double]$row.Goods }
  $r++
}
$last = $r - 1
$data.Range("A3:K$last").Borders.Color = $colors.line
$data.Columns.AutoFit() | Out-Null
$data.Range("C4:G$last").Interior.Color = 0xFDFDFD
$data.Range("I4:K$last").Interior.Color = 0xFDFDFD

$charts = $wb.Worksheets.Item(2); $charts.Name = "Charts"
$script:chartData = $data
$script:lastRow = $last
Set-Header $charts "Inflation monitor"
Write-Host "Creating charts..."
Add-LineChart $charts "g1" "HICP Headline %YoY vs HICP Energy %YoY" @(2,3) 20 70 620 300 | Out-Null
Add-ColumnChart $charts "HICP Energy contribution: gas, electricity, liquid fuels, other" @(4,5,6,7) 670 70 620 300 | Out-Null
$g3 = Add-LineChart $charts "g3" "HICP Goods %YoY vs PPI Consumer Goods (6m lead) vs PMI Output Prices - Manufacturing (12m lead)" @(8,9,10) 20 400 620 300
if ($g3.SeriesCollection().Count -ge 3) { $g3.SeriesCollection(3).AxisGroup = 2 }
Add-LineChart $charts "g4" "S&P GSCI Agricultural Commodities Index" @(11) 670 400 620 300 | Out-Null
$charts.Cells.Item(39,1).Value2 = "Blank columns are intentionally editable: fill Energy/components, PPI, PMI, or GSCI if preferred source access is unavailable."
$charts.Cells.Item(39,1).Font.Color = $colors.muted

$src = $wb.Worksheets.Item(3); $src.Name = "Sources"
Set-Header $src "Sources and fill notes"
$sourceRows = @(
  @("HICP Headline %YoY","Local site CSV / Eurostat HICP","public\data\inflation_series.csv; Eurostat teicp000/prc_hicp_manr"),
  @("HICP Energy %YoY","Eurostat HICP Energy","Public source identified: prc_hicp_manr, coicop=NRG. Column left editable for latest/manual update."),
  @("Energy decomposition","Eurostat HICP detailed COICOP + HICP weights","Use CP0451 electricity, CP0452 gas, CP0453 liquid fuels; Other as residual/remaining energy. Columns left editable."),
  @("HICP Goods %YoY","Local site CSV / Eurostat HICP","public\data\inflation_series.csv"),
  @("PPI Consumer Goods","Eurostat industrial producer prices","Public source identified: Eurostat industrial producer prices by MIG consumer goods. Column left editable."),
  @("PMI Output Prices - Manufacturing","S&P Global/HCOB PMI","Usually licensed/manual PMI feed; column left blank."),
  @("S&P GSCI Agriculture","S&P Dow Jones Indices / Yahoo Finance symbol ^SPGSAGP or spot alternatives","Public pages identified; column left editable because downloadable history may require provider access.")
)
$src.Cells.Item(3,1).Value2="Series"; $src.Cells.Item(3,2).Value2="Source"; $src.Cells.Item(3,3).Value2="Note"
for ($i=0; $i -lt $sourceRows.Count; $i++) {
  for ($j=0; $j -lt 3; $j++) { $src.Cells.Item($i+4,$j+1).Value2 = $sourceRows[$i][$j] }
}
$src.Range("A3:C3").Font.Bold = $true
$src.Range("A3:C10").Borders.Color = $colors.line
$src.Columns.AutoFit() | Out-Null

$wb.Worksheets.Item(4).Name = "README"
$readme = $wb.Worksheets.Item(4)
Set-Header $readme "How to use"
$readme.Cells.Item(3,1).Value2 = "Fill blank columns in Data. The charts update automatically because they reference the full visible data range."
$readme.Cells.Item(4,1).Value2 = "Design follows the site palette: ink, teal, blue, amber, red, green, violet on light paper."
$readme.Columns.AutoFit() | Out-Null

$charts.Activate()
Write-Host "Saving workbook..."
$wb.SaveCopyAs($out)
$wb.Close($false)
$excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
Write-Host $out
