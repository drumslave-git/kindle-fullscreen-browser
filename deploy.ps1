<#
  Builds a library item that opens a web page fullscreen on the Kindle, and copies it there.

  .\deploy.ps1 -Url http://192.168.1.50:8123/ -Name "Home Assistant"
  .\deploy.ps1 -Port 8193 -Name "Macro Deck" -Cover examples\macro-deck-cover.png
                                          # -Port alone: a server on this PC (its LAN IP is detected)
  .\deploy.ps1 -Url ... -StayOpen         # the page stays open across sleep (power button just sleeps)
  .\deploy.ps1 -Url ... -Drive H          # the Kindle's drive letter, if it is not found by its label
  .\deploy.ps1 -Url ... -BuildOnly        # just write dist\<Name>.sh

  Each -Name is its own library item (documents\<Name without spaces>.sh), so several pages can
  be installed side by side. Deploying the same name again replaces it.
#>
param(
    [string]$Url,
    [int]$Port,
    [string]$Name = 'Fullscreen Browser',
    [string]$Cover,
    [switch]$StayOpen,
    [string]$Drive,
    [switch]$BuildOnly
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null

# --- page URL -----------------------------------------------------------------
if (-not $Url) {
    if (-not $Port) { throw 'Pass -Url http://host:port/path, or -Port N for a server on this PC.' }
    $ifIndex = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1).ifIndex
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $ifIndex | Select-Object -First 1).IPAddress
    if (-not $ip) { throw 'Could not detect this PC''s LAN IP; pass -Url http://<ip>:<port>/' }
    $Url = "http://${ip}:$Port/"
}
if ($Url -notmatch '^https?://') { throw "Url must start with http:// or https:// (got '$Url')" }
# & would end the browser's view= parameter; the others would break the shell script.
if ($Url -match '[&\s"''`$\\]') { throw "Url must not contain spaces, quotes, \, `$ or & (got '$Url')" }

# --- name and file name ---------------------------------------------------------
if (-not $Name.Trim() -or $Name -match '["`$\\\r\n]') { throw "Name must not be empty or contain quotes, \ or `$ (got '$Name')" }
$fileBase = $Name -replace '[^A-Za-z0-9_-]', ''
if (-not $fileBase) { $fileBase = 'FullscreenBrowser' }

# --- cover image (shown as the book cover in the library) -----------------------
function New-Cover([string]$Path, [string]$Text) {
    Add-Type -AssemblyName System.Drawing
    $w = 600; $h = 900
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([System.Drawing.Color]::White)
    $black = [System.Drawing.Brushes]::Black
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), 12

    # A browser window...
    $x = 80; $y = 110; $ww = 440; $wh = 400; $r = 36; $d = 2 * $r
    $frame = New-Object System.Drawing.Drawing2D.GraphicsPath
    $frame.AddArc($x, $y, $d, $d, 180, 90)
    $frame.AddArc($x + $ww - $d, $y, $d, $d, 270, 90)
    $frame.AddArc($x + $ww - $d, $y + $wh - $d, $d, $d, 0, 90)
    $frame.AddArc($x, $y + $wh - $d, $d, $d, 90, 90)
    $frame.CloseFigure()
    $g.DrawPath($pen, $frame)
    $g.DrawLine($pen, $x, $y + 80, $x + $ww, $y + 80)
    for ($i = 0; $i -lt 3; $i++) { $g.FillEllipse($black, $x + 34 + $i * 40, $y + 28, 24, 24) }

    # ...with "fullscreen" corner brackets inside it
    $cx = $x + $ww / 2; $cy = $y + 80 + ($wh - 80) / 2; $half = 100; $arm = 50
    foreach ($sx in -1, 1) {
        foreach ($sy in -1, 1) {
            $px = $cx + $sx * $half; $py = $cy + $sy * $half
            $g.DrawLine($pen, $px, $py, $px - $sx * $arm, $py)
            $g.DrawLine($pen, $px, $py, $px, $py - $sy * $arm)
        }
    }

    # The name, as large as fits below the window
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $box = New-Object System.Drawing.RectangleF 30, 560, ($w - 60), 300
    for ($size = 84; $size -gt 24; $size -= 4) {
        $font = New-Object System.Drawing.Font 'Segoe UI', $size, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
        $m = $g.MeasureString($Text, $font, [int]$box.Width)
        if ($m.Height -le $box.Height -and $m.Width -le $box.Width) { break }
        $font.Dispose()
    }
    $g.DrawString($Text, $font, $black, $box, $sf)
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $font.Dispose(); $pen.Dispose(); $g.Dispose(); $bmp.Dispose()
}

if ($Cover) {
    $Cover = (Resolve-Path $Cover).Path
    if ([IO.Path]::GetExtension($Cover) -ne '.png') { throw "Cover must be a .png file (got '$Cover')" }
} else {
    $Cover = Join-Path $dist "$fileBase.png"
    New-Cover $Cover $Name
}
$coverBytes = [IO.File]::ReadAllBytes($Cover)
if ($coverBytes.Length -gt 200KB) { Write-Warning "The cover is $([int]($coverBytes.Length / 1KB)) KB; it is stored inside the script, so smaller is better." }
$icon = 'data:image/png;base64,' + [Convert]::ToBase64String($coverBytes)

# --- build ---------------------------------------------------------------------
$src = [IO.File]::ReadAllText((Join-Path $root 'launcher.sh'))
$out = $src.Replace('@NAME@', $Name).Replace('@URL@', $Url).Replace('@ICON@', $icon).Replace("`r`n", "`n")
if ($StayOpen) { $out = $out -replace '(?m)^EXIT_ON_SLEEP=1', 'EXIT_ON_SLEEP=0' }
$built = Join-Path $dist "$fileBase.sh"
[IO.File]::WriteAllText($built, $out, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Built $built  ($Name -> $Url)"
if ($BuildOnly) { return }

# --- deploy --------------------------------------------------------------------
if (-not $Drive) {
    $Drive = (Get-Volume | Where-Object { $_.FileSystemLabel -eq 'Kindle' -and $_.DriveLetter } | Select-Object -First 1).DriveLetter
}
if (-not $Drive) { throw 'Kindle not mounted. Connect it over USB (or pass -Drive H).' }
$Drive = "$Drive".TrimEnd(':', '\')
$docs = "${Drive}:\documents"
if (-not (Test-Path $docs)) { throw "$docs not found - is ${Drive}: really the Kindle?" }

$target = Join-Path $docs "$fileBase.sh"
Copy-Item $built $target -Force

# Fullscreen helper (run on the Kindle by KOReader's LuaJIT), LF line endings
$helperDir = "${Drive}:\fullscreen-browser"
New-Item -ItemType Directory -Force $helperDir | Out-Null
$lua = [IO.File]::ReadAllText((Join-Path $root 'xname.lua')).Replace("`r`n", "`n")
[IO.File]::WriteAllText((Join-Path $helperDir 'xname.lua'), $lua, (New-Object System.Text.UTF8Encoding $false))
if (-not (Test-Path "${Drive}:\koreader\luajit")) {
    Write-Warning "KOReader's luajit (${Drive}:\koreader\luajit) not found: the page will open with the Kindle's top bars."
}
Write-Host "Copied to $target and $helperDir\xname.lua - eject the Kindle and open '$Name' from the library."
