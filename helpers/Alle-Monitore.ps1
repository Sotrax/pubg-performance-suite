# ===================================================================
# Alle-Monitore.ps1
# Reaktiviert ALLE Monitore (= deaktivierte aus Nur-OLED.ps1 zurueck).
# Liest die gespeicherten IDs aus dem State-File.
# Fallback: DisplaySwitch /extend reaktiviert alle physisch verbundenen.
# ===================================================================

$ErrorActionPreference = 'SilentlyContinue'
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
Write-Host "  --- ALLE MONITORE ---" -ForegroundColor Cyan
Write-Host ""

$mmt = Get-MMTPath
$enabledViaMmt = $false

if ($mmt -and (Test-Path $STATE_FILE)) {
    $ids = @(Get-Content $STATE_FILE -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
    if ($ids.Count -gt 0) {
        Write-Host "  Lese gespeicherte IDs: $($ids -join ', ')" -ForegroundColor Gray
        Write-Host "  Aktiviere via MMT..." -ForegroundColor Cyan
        & $mmt /enable @ids
        Start-Sleep -Seconds 2
        $enabledViaMmt = $true
        Remove-Item $STATE_FILE -Force -ErrorAction SilentlyContinue
    }
}

if (-not $enabledViaMmt) {
    Write-Host "  Kein State-File - nutze Fallback DisplaySwitch /extend" -ForegroundColor Yellow
    & "$env:windir\System32\DisplaySwitch.exe" /extend
    Start-Sleep -Seconds 2
}

# Doppelter Safety-Net: DisplaySwitch /extend immer am Ende falls Monitore noch fehlen
$activeNow = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue | Where-Object { $_.Active -eq $true })
if ($activeNow.Count -lt 2) {
    Write-Host "  Nur $($activeNow.Count) Monitor aktiv - rufe DisplaySwitch /extend nach" -ForegroundColor Yellow
    & "$env:windir\System32\DisplaySwitch.exe" /extend
    Start-Sleep -Seconds 2
}

# Endzustand
$nowActive = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue | Where-Object { $_.Active -eq $true })

Write-Host ""
Write-Host "  =================================" -ForegroundColor Cyan
Write-Host "    ALLE MONITORE AKTIV" -ForegroundColor Cyan
Write-Host "  =================================" -ForegroundColor Cyan
Write-Host "  Aktive Monitore jetzt: $($nowActive.Count)" -ForegroundColor White
foreach ($m in $nowActive) {
    $manu = ($m.ManufacturerName | Where-Object {$_ -ne 0} | ForEach-Object {[char]$_}) -join ''
    $model = ($m.UserFriendlyName | Where-Object {$_ -ne 0} | ForEach-Object {[char]$_}) -join ''
    Write-Host ("    * {0} {1}" -f $manu, $model) -ForegroundColor White
}
Write-Host ""
