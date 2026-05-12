<#
.SYNOPSIS
    PUBG Performance Suite - Bootstrap Loader
    Downloads, installs, and launches the suite from GitHub.

.DESCRIPTION
    This is the irm | iex entry point. It:
      1. Self-elevates to Administrator (via UAC) if needed
      2. Downloads latest release ZIP from GitHub
      3. Extracts to %LOCALAPPDATA%\PUBGSuite\app\
      4. Creates Desktop shortcut
      5. Launches PUBG-Suite.ps1 from the extracted folder

.NOTES
    Usage from any PowerShell session:
        irm "https://raw.githubusercontent.com/Sotrax/pubg-performance-suite/main/launch.ps1" | iex

    Re-run anytime to update to the latest release.

    To customize the source repo without re-uploading, set $env:PUBGSUITE_REPO
    before running, e.g.:
        $env:PUBGSUITE_REPO = 'username/forkname'
        irm "https://raw.githubusercontent.com/$env:PUBGSUITE_REPO/main/launch.ps1" | iex
#>

$ErrorActionPreference = 'Stop'

# ==================== CONFIG ====================
$RepoSlug    = if ($env:PUBGSUITE_REPO) { $env:PUBGSUITE_REPO } else { 'Sotrax/pubg-performance-suite' }
$Branch      = 'main'
$InstallDir  = Join-Path $env:LOCALAPPDATA 'PUBGSuite\app'
$ShortcutPath= Join-Path ([Environment]::GetFolderPath('Desktop')) 'PUBG Performance Suite.lnk'

# ==================== PRECONDITIONS ====================
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "PowerShell 5.1+ erforderlich. Aktuell: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    pause; exit 1
}

# TLS 1.2 fuer GitHub Downloads (Win10 default ist manchmal noch TLS 1.0)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Self-Elevate via UAC falls noetig
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "  Hole Admin-Rechte fuer Tweak-Apply (Registry/Service-Aenderungen)..." -ForegroundColor Yellow
    $scriptUrl = "https://raw.githubusercontent.com/$RepoSlug/$Branch/launch.ps1"
    $cmd = "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iwr '$scriptUrl' -UseBasicParsing | iex"
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command', $cmd
    exit
}

# ==================== BOOTSTRAP ====================
Clear-Host
Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  PUBG PERFORMANCE SUITE - Bootstrap Installer" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Repository: $RepoSlug ($Branch)" -ForegroundColor Gray
Write-Host "  Install Pfad: $InstallDir" -ForegroundColor Gray
Write-Host ""

# Cleanup alte Installation (Backups/Logs in %LOCALAPPDATA%\PUBGSuite\ bleiben unangetastet)
if (Test-Path $InstallDir) {
    Write-Host "  Loesche alte Version..." -ForegroundColor Gray
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null

# Download Branch ZIP
$zipUrl = "https://github.com/$RepoSlug/archive/refs/heads/$Branch.zip"
$zipPath = Join-Path $env:TEMP "pubg-suite-$Branch.zip"

Write-Host "  Lade Suite von GitHub..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
} catch {
    Write-Host "  FEHLER: Download fehlgeschlagen: $_" -ForegroundColor Red
    Write-Host "  Repository pruefen: https://github.com/$RepoSlug" -ForegroundColor Yellow
    pause; exit 1
}

Write-Host "  Entpacke nach $InstallDir..." -ForegroundColor Gray
$extractTemp = Join-Path $env:TEMP "pubg-suite-extract-$(Get-Random)"
Expand-Archive -Path $zipPath -DestinationPath $extractTemp -Force
$inner = Get-ChildItem -Path $extractTemp -Directory | Select-Object -First 1
if (-not $inner) {
    Write-Host "  FEHLER: ZIP-Struktur unerwartet" -ForegroundColor Red
    pause; exit 1
}
Get-ChildItem -Path $inner.FullName | Move-Item -Destination $InstallDir -Force
Remove-Item $extractTemp -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

# Verify Hauptscript
$mainScript = Join-Path $InstallDir 'PUBG-Suite.ps1'
if (-not (Test-Path $mainScript)) {
    Write-Host "  FEHLER: PUBG-Suite.ps1 nicht im entpackten Inhalt gefunden" -ForegroundColor Red
    pause; exit 1
}

# Desktop-Shortcut
Write-Host "  Erstelle Desktop-Shortcut..." -ForegroundColor Gray
try {
    $wsh = New-Object -ComObject WScript.Shell
    $lnk = $wsh.CreateShortcut($ShortcutPath)
    $lnk.TargetPath = 'powershell.exe'
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$mainScript`""
    $lnk.IconLocation = 'powershell.exe,0'
    $lnk.WorkingDirectory = $InstallDir
    $lnk.Description = 'PUBG Performance Suite'
    $lnk.Save()
} catch {
    Write-Host "  Shortcut konnte nicht erstellt werden (nicht kritisch): $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "    INSTALLATION ERFOLGREICH" -ForegroundColor Green
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "  Installiert nach:  $InstallDir" -ForegroundColor White
Write-Host "  Desktop-Shortcut:  $ShortcutPath" -ForegroundColor White
Write-Host ""
Write-Host "  Suite startet jetzt..." -ForegroundColor Cyan
Write-Host ""

Start-Sleep -Seconds 2

# Launch
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mainScript
