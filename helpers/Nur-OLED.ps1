# ===================================================================
# Nur-OLED.ps1
# Aktiviert NUR den OLED-Monitor. Deaktiviert beide Acer XB271HU.
# Speichert die deaktivierten IDs persistent fuer Alle-Monitore.ps1.
# ===================================================================

$ErrorActionPreference = 'SilentlyContinue'
$TARGET_PATTERN = 'XB271HU'
$MMT_DIR_PRIMARY = 'C:\Tools\MultiMonitorTool'
$MMT_DIR_FALLBACK = Join-Path $env:USERPROFILE 'Tools\MultiMonitorTool'
$STATE_FILE = Join-Path $env:LOCALAPPDATA 'PUBGDiag\disabled-monitors.txt'

function Get-MMTPath {
    foreach ($p in @(
        "$MMT_DIR_PRIMARY\MultiMonitorTool.exe",
        "$MMT_DIR_FALLBACK\MultiMonitorTool.exe"
    )) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Install-MMT {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $target = $MMT_DIR_PRIMARY
    try {
        if (-not (Test-Path $target)) { New-Item -Path $target -ItemType Directory -Force -ErrorAction Stop | Out-Null }
    } catch {
        $target = $MMT_DIR_FALLBACK
        Write-Host "  $MMT_DIR_PRIMARY nicht beschreibbar, fallback auf $target" -ForegroundColor Yellow
        New-Item -Path $target -ItemType Directory -Force | Out-Null
    }
    $zip = Join-Path $env:TEMP 'mmt.zip'
    Write-Host "  Lade MultiMonitorTool (NirSoft)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri 'https://www.nirsoft.net/utils/multimonitortool-x64.zip' -OutFile $zip -UseBasicParsing -ErrorAction Stop
    Expand-Archive -Path $zip -DestinationPath $target -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    $exe = Join-Path $target 'MultiMonitorTool.exe'
    if (Test-Path $exe) { return $exe }
    return $null
}

function Get-MonitorTable {
    param([string]$Mmt)
    $csv = Join-Path $env:TEMP "mmt_$(Get-Random).csv"
    & $Mmt /scomma $csv | Out-Null
    Start-Sleep -Milliseconds 700
    if (Test-Path $csv) {
        $data = Import-Csv $csv
        Remove-Item $csv -Force -ErrorAction SilentlyContinue
        return $data
    }
    return @()
}

# === Main ===
Write-Host ""
Write-Host "  --- NUR OLED ---" -ForegroundColor Cyan
Write-Host "  (deaktiviert beide Acer XB271HU)" -ForegroundColor DarkGray
Write-Host ""

$mmt = Get-MMTPath
if (-not $mmt) {
    Write-Host "  MultiMonitorTool nicht gefunden." -ForegroundColor Yellow
    $mmt = Install-MMT
    if (-not $mmt) {
        Write-Host "  FEHLER: Install fehlgeschlagen." -ForegroundColor Red
        Read-Host "Enter zum Schliessen"; exit 1
    }
    Write-Host "  Installiert: $mmt" -ForegroundColor Green
}
Write-Host "  MMT: $mmt" -ForegroundColor DarkGray

$monitors = Get-MonitorTable -Mmt $mmt
if ($monitors.Count -eq 0) {
    Write-Host "  FEHLER: Keine Monitore aus MMT erhalten" -ForegroundColor Red
    Read-Host "Enter zum Schliessen"; exit 1
}

Write-Host ""
Write-Host "  Aktuelle Monitore:" -ForegroundColor Gray
foreach ($m in $monitors) {
    $stat = if ($m.Active -eq 'Yes') { 'AKTIV' } else { 'inaktiv' }
    $name = if ($m.'Monitor Name') { $m.'Monitor Name' } else { '(kein Name - vermutlich OLED)' }
    Write-Host ("    [{0,-8}] {1,-12} {2}" -f $stat, $m.'Short Monitor ID', $name)
}

$toDisable = @($monitors | Where-Object { $_.'Monitor Name' -match $TARGET_PATTERN -and $_.Active -eq 'Yes' })
$remainingActive = @($monitors | Where-Object { $_.'Monitor Name' -notmatch $TARGET_PATTERN -and $_.Active -eq 'Yes' })

if ($toDisable.Count -eq 0) {
    Write-Host ""
    Write-Host "  Keine aktiven '$TARGET_PATTERN'-Monitore - nichts zu tun." -ForegroundColor Yellow
    Read-Host "Enter zum Schliessen"; exit 0
}

if ($remainingActive.Count -eq 0) {
    Write-Host ""
    Write-Host "  ABBRUCH: wuerde Total-Lockout verursachen!" -ForegroundColor Red
    Read-Host "Enter zum Schliessen"; exit 1
}

# IDs vor dem Deaktivieren persistieren - sonst kann Alle-Monitore.ps1
# die nicht mehr by name finden (MMT listet disabled monitors nicht)
$stateDir = Split-Path $STATE_FILE -Parent
if (-not (Test-Path $stateDir)) { New-Item -Path $stateDir -ItemType Directory -Force | Out-Null }
$idsToDisable = @($toDisable | ForEach-Object { $_.'Short Monitor ID' })
$idsToDisable | Set-Content -Path $STATE_FILE -Encoding UTF8

Write-Host ""
Write-Host "  Deaktiviere: $($idsToDisable -join ', ')" -ForegroundColor Cyan
Write-Host "  Bleibt aktiv: $(($remainingActive | ForEach-Object { if ($_.'Monitor Name') {$_.'Monitor Name'} else {$_.'Short Monitor ID'} }) -join ', ')" -ForegroundColor Green
Write-Host "  IDs gespeichert in: $STATE_FILE" -ForegroundColor DarkGray
Write-Host ""

& $mmt /disable @idsToDisable
Start-Sleep -Seconds 2

# Verify
$nowActive = @(Get-MonitorTable -Mmt $mmt | Where-Object { $_.Active -eq 'Yes' })
Write-Host ""
Write-Host "  =================================" -ForegroundColor Green
Write-Host "    NUR OLED AKTIV" -ForegroundColor Green
Write-Host "  =================================" -ForegroundColor Green
Write-Host "  Aktive Monitore jetzt: $($nowActive.Count)" -ForegroundColor White
foreach ($m in $nowActive) {
    $name = if ($m.'Monitor Name') { $m.'Monitor Name' } else { '(OLED - kein Name)' }
    Write-Host ("    * {0} ({1})" -f $name, $m.'Short Monitor ID') -ForegroundColor White
}
Write-Host ""
Write-Host "  Reaktivieren: Alle-Monitore.bat" -ForegroundColor Yellow
Write-Host ""
