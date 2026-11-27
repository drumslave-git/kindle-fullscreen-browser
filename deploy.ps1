<#
  Builds MacroDeck.sh (cover icon + Macro Deck URL baked in, LF line endings)
  and copies it to the Kindle's documents folder, plus xname.lua to <Kindle>\macrodeck\.

  .\deploy.ps1                      # auto-detect this PC's LAN IP, port 8193, Kindle drive
  .\deploy.ps1 -Url http://192.168.1.50:8193/
  .\deploy.ps1 -Drive H             # the Kindle's drive letter, if it is not found by its "Kindle" label
  .\deploy.ps1 -BuildOnly           # just write dist\MacroDeck.sh
#>
param(
    [string]$Url,
    [int]$Port = 8193,
    [string]$Drive,
    [switch]$BuildOnly
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null

# --- Macro Deck URL -----------------------------------------------------------
if (-not $Url) {
    $ifIndex = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1).ifIndex
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $ifIndex | Select-Object -First 1).IPAddress
    if (-not $ip) { throw 'Could not detect this PC''s LAN IP; pass -Url http://<ip>:8193/' }
    $Url = "http://${ip}:$Port/"
}
if ($Url -notmatch '^https?://') { throw "Url must start with http:// or https:// (got '$Url')" }
if ($Url -match '[&\s"''`$]') { throw "Url must not contain spaces, quotes, `$ or & (got '$Url')" }

# --- cover image (shown as the book cover in the library) ---------------------
$cover = Join-Path $root 'cover.png'
if (-not (Test-Path $cover)) {
    Add-Type -AssemblyName System.Drawing
    $w = 600; $h = 900
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([System.Drawing.Color]::White)

    # 3 x 4 grid of deck buttons
    $cols = 3; $rows = 4; $cell = 120; $gap = 24; $r = 22
    $gridW = $cols * $cell + ($cols - 1) * $gap
    $x0 = ($w - $gridW) / 2; $y0 = 90
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), 8
    for ($row = 0; $row -lt $rows; $row++) {
        for ($col = 0; $col -lt $cols; $col++) {
            $x = $x0 + $col * ($cell + $gap); $y = $y0 + $row * ($cell + $gap)
            $path = New-Object System.Drawing.Drawing2D.GraphicsPath
            $d = 2 * $r
            $path.AddArc($x, $y, $d, $d, 180, 90)
            $path.AddArc($x + $cell - $d, $y, $d, $d, 270, 90)
            $path.AddArc($x + $cell - $d, $y + $cell - $d, $d, $d, 0, 90)
            $path.AddArc($x, $y + $cell - $d, $d, $d, 90, 90)
            $path.CloseFigure()
            if (($row + $col) % 3 -eq 0) { $g.FillPath([System.Drawing.Brushes]::Black, $path) }
            else { $g.DrawPath($pen, $path) }
        }
    }

    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'
    $title = New-Object System.Drawing.Font 'Segoe UI', 72, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $g.DrawString('Macro Deck', $title, [System.Drawing.Brushes]::Black, (New-Object System.Drawing.RectangleF 0, 690, $w, 100), $sf)
    $bmp.Save($cover, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Host "Created $cover"
}
$icon = 'data:image/png;base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($cover))

# --- build ---------------------------------------------------------------------
$src = [IO.File]::ReadAllText((Join-Path $root 'MacroDeck.sh'))
$out = $src.Replace('@ICON@', $icon).Replace('@URL@', $Url).Replace("`r`n", "`n")
$built = Join-Path $dist 'MacroDeck.sh'
[IO.File]::WriteAllText($built, $out, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Built $built  (url: $Url)"
if ($BuildOnly) { return }

# --- deploy --------------------------------------------------------------------
if (-not $Drive) {
    $Drive = (Get-Volume | Where-Object { $_.FileSystemLabel -eq 'Kindle' -and $_.DriveLetter } | Select-Object -First 1).DriveLetter
}
if (-not $Drive) { throw 'Kindle not mounted. Connect it over USB (or pass -Drive H).' }
$Drive = $Drive.TrimEnd(':', '\')
$docs = "${Drive}:\documents"
if (-not (Test-Path $docs)) { throw "$docs not found - is ${Drive}: really the Kindle?" }

Copy-Item $built (Join-Path $docs 'MacroDeck.sh') -Force

# Fullscreen helper (run on the Kindle by KOReader's LuaJIT), LF line endings
$helperDir = "${Drive}:\macrodeck"
New-Item -ItemType Directory -Force $helperDir | Out-Null
$lua = [IO.File]::ReadAllText((Join-Path $root 'xname.lua')).Replace("`r`n", "`n")
[IO.File]::WriteAllText((Join-Path $helperDir 'xname.lua'), $lua, (New-Object System.Text.UTF8Encoding $false))
if (-not (Test-Path "${Drive}:\koreader\luajit")) {
    Write-Warning "KOReader's luajit (${Drive}:\koreader\luajit) not found: the deck will open with the Kindle's top bars."
}
Write-Host "Copied to $docs\MacroDeck.sh and $helperDir\xname.lua - eject the Kindle and open 'Macro Deck' from the library."
