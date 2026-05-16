<#
.SYNOPSIS
    PUBG Performance Suite - WPF-GUI fuer Diagnose, Tweaks, Grafikprofil,
    Performance-Capture und Game-Mode-Workflow.

.DESCRIPTION
    Windows-PowerShell-5.1-/WPF-Tool zum Diagnostizieren und Tunen von PUBG
    fuer den kompetitiven Einsatz. Sechs Tabs:
      - Dashboard:  Live-Status aller relevanten Settings + Empfehlungen
      - Tweaks:     System-/PUBG-Tweaks aus der Tweak-Registry anwenden/zuruecknehmen
      - Game Mode:  One-Click pre-/post-game prep (Monitore solo, RTSS aus ...)
      - Capture:    60s-Frametime-Messung via Intel PresentMon, Trend + Vergleich
      - Diagnose:   ruft PUBG-Diagnose-v7.ps1 auf, oeffnet den HTML-Report
      - Settings:   Hardware-Erkennung, Monitor-Pattern, Logs/Backups

    Single Source of Truth in config\: PUBGProfile.psd1 (Grafikprofil) und
    PUBGTweakRegistry.psm1 (Tweak-Registry) - Suite UND Diagnose lesen beides.

    Externe Tools werden bei Bedarf nach C:\Tools\ auto-installiert
    (MultiMonitorTool, nvidiaProfileInspector, PresentMon).

    Die Version steht zentral in $Global:Suite.Version.

.NOTES
    Start: PUBG-Suite.bat (Doppelklick) oder
           powershell -ExecutionPolicy Bypass -File PUBG-Suite.ps1
#>

$ErrorActionPreference = 'SilentlyContinue'

# ==================== KONFIGURATION ====================
$Global:Suite = @{
    # Fallback - die echte Version steht in der VERSION-Datei (Single Source of
    # Truth, wird direkt unter diesem Block geladen und ueberschreibt diesen Wert).
    Version    = '0.28.0-beta'
    StateDir   = "$env:LOCALAPPDATA\PUBGSuite"
    StateFile  = "$env:LOCALAPPDATA\PUBGSuite\state.json"
    ConfigFile = "$env:LOCALAPPDATA\PUBGSuite\config.json"
    HistoryFile= "$env:LOCALAPPDATA\PUBGSuite\history.json"
    LogDir     = "$env:LOCALAPPDATA\PUBGSuite\logs"
    BackupDir  = "$env:LOCALAPPDATA\PUBGSuite\backups"
    CaptureDir = "$env:LOCALAPPDATA\PUBGSuite\captures"
    CapturesFile = "$env:LOCALAPPDATA\PUBGSuite\captures.json"
    MonitorIDs = "$env:LOCALAPPDATA\PUBGSuite\disabled-monitors.txt"
    NPIStamp   = "$env:LOCALAPPDATA\PUBGDiag\npi-applied.stamp"
    # Diag-Script liegt fest neben der Suite (Repo: diagnose\PUBG-Diagnose-v7.ps1,
    # Bootstrap-Install: %LOCALAPPDATA%\PUBGSuite\app\diagnose\PUBG-Diagnose-v7.ps1).
    # $PSScriptRoot zeigt in beiden Faellen auf den richtigen Folder.
    DiagScript = (Join-Path $PSScriptRoot 'diagnose\PUBG-Diagnose-v7.ps1')
    # Geteilte Konfiguration: Grafikprofil + Tweak-Registry. Suite UND Diagnose
    # lesen ausschliesslich aus diesen beiden Dateien (Single Source of Truth).
    ProfilePath  = (Join-Path $PSScriptRoot 'config\PUBGProfile.psd1')
    RegistryPath = (Join-Path $PSScriptRoot 'config\PUBGTweakRegistry.psm1')
    Tools = @{
        MMT  = 'C:\Tools\MultiMonitorTool\MultiMonitorTool.exe'
        NPI  = 'C:\Tools\nvidiaProfileInspector\nvidiaProfileInspector.exe'
        PM   = 'C:\Tools\PresentMon'
    }
    MonitorPattern = ''   # leer = Solo-Setup, kein Monitor wird im Game-Mode deaktiviert. Per 'Detect & Fill' befuellbar.
    PUBGSteamURI   = 'steam://run/578080'
    RepoSlug       = 'Sotrax/pubg-performance-suite'  # fuer den Update-Check
}

# Version aus der VERSION-Datei laden (Single Source of Truth). Der Update-Check
# vergleicht dieselbe Datei aus dem main-Branch - so kann es keine Drift geben.
# Fehlt die Datei, bleibt der Fallback-Wert aus $Global:Suite oben gueltig.
$versionFile = Join-Path $PSScriptRoot 'VERSION'
if (Test-Path $versionFile) {
    $vRaw = (Get-Content $versionFile -Raw -ErrorAction SilentlyContinue)
    if ($vRaw) {
        $vTrim = $vRaw.Trim()
        if ($vTrim) { $Global:Suite.Version = $vTrim }
    }
}

# ==================== FARBPALETTE ====================
# Single Source of Truth fuer ALLE Farben - UI wie dynamische Status-Farben.
# Im XAML referenziert ueber @@Token@@-Platzhalter (werden beim XAML-Build
# aufgeloest), im PowerShell-Code direkt via $Global:SuiteColors.<Token>.
# Dunkles Schema nach WCAG-AA: kein reines Schwarz, Tiefe ueber progressiv
# hellere Flaechen-Ebenen statt Schatten, entsaettigte Status-Farben.
# Alle Text-auf-Flaeche-Paare gegen #1A1D23 auf >=4.5:1 geprueft.
$Global:SuiteColors = [ordered]@{
    BgBase           = '#14171C'   # App-Hintergrund, eingelassene Kacheln
    Surface1         = '#1A1D23'   # Karten, Tabs, Header/Footer, Tabellenzeilen
    Surface2         = '#22262E'   # Hover, Popups, Menues
    BorderSubtle     = '#2E333D'   # Trennlinien, Karten-Rahmen
    BorderStrong     = '#3C424E'   # Eingabefelder, neutrale Badges, inaktive Buttons
    TextPrimary      = '#E6E8EB'   # Ueberschriften, Werte, Fliesstext (87% Weiss)
    TextSecondary    = '#A2A8B4'   # Labels, Captions, Beschreibungen (60%)
    TextDisabled     = '#6B7280'   # Deaktiviert, Mini-Sublabels, Footer (38%)
    Accent           = '#4DA3FF'   # Primaer-Aktion, aktiver Tab, Links, Sektions-Header
    AccentHover      = '#6FB6FF'   # Hover/Pressed des Akzents
    StatusBest       = '#74D98C'   # Bestnote (heller als OK)
    StatusOK         = '#56C271'   # OK / optimiert / Erfolg-Buttons
    StatusOKHover    = '#6FCF86'   # Hover der Erfolg-Buttons
    StatusWarn       = '#E0A33E'   # Warnung / suboptimal
    StatusError      = '#E5645B'   # Fehler / Risiko / Danger-Buttons
    StatusErrorHover = '#ED7E76'   # Hover der Danger-Buttons
    OkBg             = '#1E2A22'   # gruen getoenter Badge-Hintergrund
    WarnBg           = '#2C2519'   # amber getoenter Badge-Hintergrund
    InfoBg           = '#1B2731'   # blau getoenter Badge-Hintergrund
}

# ==================== STORAGE LAYER (Config / Log / History) ====================
function Initialize-SuiteStorage {
    foreach ($d in $Global:Suite.StateDir, $Global:Suite.LogDir, $Global:Suite.BackupDir, $Global:Suite.CaptureDir) {
        if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
    }
}
Initialize-SuiteStorage

function Write-SuiteLog {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO')
    try {
        $logFile = Join-Path $Global:Suite.LogDir "$(Get-Date -Format 'yyyy-MM-dd').log"
        $ts = Get-Date -Format 'HH:mm:ss.fff'
        "[$ts] [$Level] $Message" | Add-Content -Path $logFile -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}  # Logging selbst darf nie werfen - sonst Endlosrekursion
}

function Get-SuiteConfig {
    if (Test-Path $Global:Suite.ConfigFile) {
        try { return Get-Content $Global:Suite.ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { Write-SuiteLog "Get-SuiteConfig: Config unlesbar oder ungueltiges JSON - nutze Defaults ($($_.Exception.Message))" 'WARN' }
    }
    return [PSCustomObject]@{
        MonitorPattern = ''   # Default Solo-Setup - per 'Detect & Fill' aus Sekundaer-Monitoren befuellbar
        Theme = 'Dark'
        LastSeen = (Get-Date).ToString('o')
    }
}

function Save-SuiteConfig {
    param($Config)
    try {
        $Config | ConvertTo-Json -Depth 8 | Set-Content -Path $Global:Suite.ConfigFile -Encoding UTF8
        Write-SuiteLog "Config gespeichert"
    } catch {
        Write-SuiteLog "Config-Save Fehler: $($_.Exception.Message)" 'ERROR'
    }
}

# Vergleicht die lokale Version mit der VERSION-Datei im main-Branch auf GitHub.
# Passt zum Auslieferungsmodell der Suite: verteilt wird der main-Branch (via
# launch.ps1 / irm|iex), nicht getaggte Releases - also wird auch gegen main
# geprueft. Die VERSION-Datei ist winzig (ein paar Bytes), daher kein spuerbarer
# Start-Overhead. Bewusst fehler-tolerant: bei Netzfehler einfach kein Hinweis
# (Rueckgabe $null) - der Update-Check darf den Start nie stoeren.
# Verglichen wird nur der numerische Versionsteil (0.21.0-beta -> 0.21.0).
function Test-SuiteUpdate {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $url = "https://raw.githubusercontent.com/$($Global:Suite.RepoSlug)/main/VERSION"
        $remoteRaw = Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = 'PUBG-Suite' } -TimeoutSec 4
        $remoteVer = ([string]$remoteRaw).Trim()
        if (-not $remoteVer) { return $null }
        # Numerischen Teil isolieren: "0.21.0-beta" -> "0.21.0"
        $remoteNum = $remoteVer -replace '^v','' -replace '-.*$',''
        $localNum  = $Global:Suite.Version -replace '^v','' -replace '-.*$',''
        $rv = $null; $lv = $null
        if (-not [version]::TryParse($remoteNum, [ref]$rv)) { return $null }
        if (-not [version]::TryParse($localNum,  [ref]$lv)) { return $null }
        if ($rv -gt $lv) {
            Write-SuiteLog "Update verfuegbar: $remoteVer (lokal $($Global:Suite.Version))" 'INFO'
            return [PSCustomObject]@{ Version = $remoteVer }
        }
        Write-SuiteLog "Update-Check: aktuell (lokal $($Global:Suite.Version), main $remoteVer)"
        return $null
    } catch {
        Write-SuiteLog "Update-Check fehlgeschlagen (unkritisch): $($_.Exception.Message)" 'WARN'
        return $null
    }
}

function _Flatten-HistoryEntries {
    # PS 5.1 ConvertTo-Json/ConvertFrom-Json verschachtelt bei Pipeline-Saves:
    # [{value: [{value: [...], Count: N}, ...], Count: N}]
    # Diese Helper unwrappt rekursiv alle {value: ...; Count: ...} Wrapper.
    param($Items)
    $out = @()
    foreach ($it in @($Items)) {
        if ($null -eq $it) { continue }
        # Wenn das Item ein {value, Count} Wrapper ist -> rekursiv unwrappen
        if ($it.PSObject.Properties.Name -contains 'value' -and $it.PSObject.Properties.Name -contains 'Count' -and
            -not ($it.PSObject.Properties.Name -contains 'TweakId')) {
            $inner = $it.value
            if ($null -ne $inner) {
                # Skip String-Pad-Wrapper wie {value: " ", Count: 2}
                if ($inner -is [string]) { continue }
                $out += (_Flatten-HistoryEntries $inner)
            }
            continue
        }
        # Echter Eintrag mit TweakId
        if ($it.PSObject.Properties.Name -contains 'TweakId') {
            $out += $it
        }
    }
    return $out
}

function Get-HistoryEntries {
    if (Test-Path $Global:Suite.HistoryFile) {
        try {
            $raw = Get-Content $Global:Suite.HistoryFile -Raw -Encoding UTF8 | ConvertFrom-Json
            return @(_Flatten-HistoryEntries $raw)
        } catch { return @() }
    }
    return @()
}

function Add-HistoryEntry {
    param(
        [string]$Action,
        [string]$TweakId,
        $Snapshot = $null,
        [bool]$Success = $true,
        [string]$ErrorMsg = ''
    )
    try {
        $entries = @(Get-HistoryEntries)
        $entries += [PSCustomObject]@{
            Time = (Get-Date).ToString('o')
            Action = $Action
            TweakId = $TweakId
            Snapshot = $Snapshot
            Success = $Success
            ErrorMsg = $ErrorMsg
        }
        # Cap auf letzte 500 Entries damit das File nicht endlos waechst
        if ($entries.Count -gt 500) { $entries = $entries[-500..-1] }
        # KEIN Pipeline-Save (PS 5.1 unwrappt size=1 zu Object): -InputObject + manual array-wrap
        $json = ConvertTo-Json -InputObject $entries -Depth 8
        if ($entries.Count -eq 1 -and -not $json.TrimStart().StartsWith('[')) {
            $json = "[`r`n$json`r`n]"
        }
        Set-Content -Path $Global:Suite.HistoryFile -Value $json -Encoding UTF8
    } catch {
        Write-SuiteLog "History-Save Fehler: $($_.Exception.Message)" 'ERROR'
    }
}

function Get-LastSnapshot {
    param([string]$TweakId)
    $entries = Get-HistoryEntries
    $last = $entries | Where-Object { $_.TweakId -eq $TweakId -and $_.Action -eq 'Apply' -and $_.Success } | Select-Object -Last 1
    if ($last) { return $last.Snapshot }
    return $null
}

# ==================== SNAPSHOT HELPERS ====================
function Copy-FileToBackup {
    param([string]$SourcePath)
    if (-not (Test-Path $SourcePath)) { return $null }
    $name = [System.IO.Path]::GetFileName($SourcePath)
    $ts = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $dest = Join-Path $Global:Suite.BackupDir "$name.bak_$ts"
    Copy-Item -Path $SourcePath -Destination $dest -Force -ErrorAction SilentlyContinue
    return $dest
}

function Restore-FileFromBackup {
    param([string]$BackupPath, [string]$TargetPath)
    if (-not (Test-Path $BackupPath)) { return $false }
    try {
        Copy-Item -Path $BackupPath -Destination $TargetPath -Force -ErrorAction Stop
        return $true
    } catch { return $false }
}

# ==================== STATUS DETECTION ====================
function Get-LiveStatus {
    $s = [ordered]@{}

    # VBS + HVCI (zusammen) - korrekte Hierarchie:
    # - SecurityServicesRunning enthaelt 2 = HVCI aktiv (kostet 5-10% FPS) -> BAD
    # - SecurityServicesRunning enthaelt 1 = Credential Guard aktiv -> BAD
    # - VirtualizationBasedSecurityStatus=2 aber keine Services = nur Hypervisor-Stack laeuft (~1-3% SLAT) -> WARN
    # - alles aus -> OK
    try {
        $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
        $running = @($dg.SecurityServicesRunning)
        $hvciOn = $running -contains 2
        $credGuardOn = $running -contains 1
        $hyperVUp = ($dg.VirtualizationBasedSecurityStatus -eq 2)
        if ($hvciOn -and $credGuardOn) {
            $s['HVCI'] = @{ Value='HVCI + CredGuard aktiv'; Status='BAD' }
        } elseif ($hvciOn) {
            $s['HVCI'] = @{ Value='HVCI aktiv'; Status='BAD' }
        } elseif ($credGuardOn) {
            $s['HVCI'] = @{ Value='CredGuard aktiv'; Status='BAD' }
        } elseif ($hyperVUp) {
            # Services aus, aber Hypervisor noch geladen - kleinerer Performance-Impact
            $s['HVCI'] = @{ Value='Hypervisor an (Services aus)'; Status='WARN' }
        } else {
            $s['HVCI'] = @{ Value='AUS'; Status='OK' }
        }
    } catch { $s['HVCI'] = @{ Value='?'; Status='SKIP' } }

    # Energieplan
    $active = powercfg /getactivescheme 2>$null
    if ($active -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
        $guid = $matches[1].ToLower()
        $highGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        $ultGuid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
        if ($guid -eq $highGuid -or $guid -eq $ultGuid) {
            $s['Energieplan'] = @{ Value='Hoechstleistung'; Status='OK' }
        } else {
            $s['Energieplan'] = @{ Value='nicht Max'; Status='WARN' }
        }
    } else { $s['Energieplan'] = @{ Value='?'; Status='SKIP' } }

    # Game DVR
    $dvr = (Get-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -ErrorAction SilentlyContinue).GameDVR_Enabled
    $s['GameDVR'] = if ($dvr -eq 0) { @{ Value='AUS'; Status='OK' } } else { @{ Value='AN'; Status='BAD' } }

    # Multi-Monitor - via System.Windows.Forms.Screen (zeigt nur aktuell vom DWM genutzte Displays,
    # nicht WMI-cached Werte die auch deaktivierte Monitore listen)
    try {
        $monCount = [System.Windows.Forms.Screen]::AllScreens.Count
    } catch { $monCount = 0 }
    $s['Monitore'] = if ($monCount -eq 1) { @{ Value="$monCount (Solo)"; Status='OK' } } elseif ($monCount -gt 1) { @{ Value="$monCount aktiv"; Status='WARN' } } else { @{ Value='?'; Status='SKIP' } }

    # RTSS - @() Wrapper damit .Count auch bei einzelnem Prozess funktioniert
    $rtss = @(Get-Process -Name 'RTSS','RTSSHooksLoader64' -ErrorAction SilentlyContinue)
    $s['RTSS'] = if ($rtss.Count -gt 0) { @{ Value="laeuft (PID $($rtss[0].Id))"; Status='WARN' } } else { @{ Value='nicht aktiv'; Status='OK' } }

    # Engine.ini Tweaks (+ ReadOnly-Flag fuer PUBG-Overwrite-Schutz)
    $eng = "$env:LOCALAPPDATA\TslGame\Saved\Config\WindowsNoEditor\Engine.ini"
    if (Test-Path $eng) {
        $c = Get-Content $eng -Raw
        $hasSharpen = $c -match 'r\.Tonemapper\.Sharpen\s*=\s*0\.7'
        $hasStreaming = $c -match 'r\.Streaming\.PoolSize\s*=\s*4096'
        $isReadOnly = $false
        try { $isReadOnly = ((Get-Item $eng -Force).Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0 } catch {}  # best-effort: bleibt $false wenn nicht ermittelbar
        if ($hasSharpen -and $hasStreaming) {
            $lbl = if ($isReadOnly) { 'Tweaks drin (geschuetzt)' } else { 'Tweaks drin' }
            $s['Engine.ini'] = @{ Value=$lbl; Status='OK' }
        } else {
            $s['Engine.ini'] = @{ Value='Tweaks fehlen'; Status='WARN' }
        }
    } else { $s['Engine.ini'] = @{ Value='nicht gefunden'; Status='SKIP' } }

    # FPS-Cap: In-Game-FrameRateLimit soll = Monitor-Hz (Display-Based) sein,
    # der scharfe Competitive-Cap (Hz-3) kommt vom NVIDIA-Treiber-Limiter.
    $gusFps = "$env:LOCALAPPDATA\TslGame\Saved\Config\WindowsNoEditor\GameUserSettings.ini"
    if (Test-Path $gusFps) {
        $hzFps = Get-PrimaryMonitorHz
        $gcFps = Get-Content $gusFps -Raw -ErrorAction SilentlyContinue
        $npiOk = Test-Path $Global:Suite.NPIStamp
        if ($gcFps -and ($gcFps -match '(?m)^\s*FrameRateLimit\s*=\s*([\d.]+)')) {
            $frl = [int][math]::Floor([double]$matches[1])
            if ($frl -eq $hzFps -and $npiOk) {
                $s['FPS-Cap'] = @{ Value="In-Game $frl + Treiber $($hzFps - 3)"; Status='OK' }
            } elseif ($frl -eq $hzFps) {
                $s['FPS-Cap'] = @{ Value="In-Game $frl, Treiber-Cap fehlt"; Status='WARN' }
            } else {
                $s['FPS-Cap'] = @{ Value="$frl FPS (nicht Display-Based)"; Status='WARN' }
            }
        } else {
            $s['FPS-Cap'] = @{ Value='kein Cap gesetzt'; Status='WARN' }
        }
    } else {
        $s['FPS-Cap'] = @{ Value='GameUserSettings.ini fehlt'; Status='SKIP' }
    }

    # G-Sync: VRR ist die Voraussetzung fuer tearing-freies Spielen ohne
    # V-Sync-Latenz. Stamp wird vom 'gsync'-Tweak gesetzt. Ob VRR im Monitor-OSD
    # aktiv ist, kann die Suite nicht pruefen - daher der OSD-Hinweis.
    $gsyncStamp = "$env:LOCALAPPDATA\PUBGDiag\gsync-applied.stamp"
    if (Test-Path $gsyncStamp) {
        $s['G-Sync'] = @{ Value='aktiviert (VRR im Monitor-OSD pruefen)'; Status='OK' }
    } else {
        $s['G-Sync'] = @{ Value='nicht aktiviert'; Status='WARN' }
    }

    # NPI Stamp
    if (Test-Path $Global:Suite.NPIStamp) {
        $age = (Get-Date) - (Get-Item $Global:Suite.NPIStamp).LastWriteTime
        $s['NV Profil'] = @{ Value="applied vor $([int]$age.TotalDays)d"; Status='OK' }
    } else {
        $s['NV Profil'] = @{ Value='nicht applied'; Status='WARN' }
    }

    # Defender Exclusion - non-Admin sieht ExclusionPath nicht zuverlaessig
    $isAdminShell = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    try {
        $defPref = Get-MpPreference -ErrorAction Stop
        $excl = @($defPref.ExclusionPath)
        $hasPubg = ($excl -and ($excl -match 'PUBG|TslGame'))

        if ($hasPubg) {
            $s['Defender'] = @{ Value='PUBG exkludiert'; Status='OK' }
        } elseif (-not $isAdminShell) {
            # Ohne Admin koennen wir nicht sicher sagen ob die Exclusion existiert
            $s['Defender'] = @{ Value='nicht auslesbar (Admin)'; Status='SKIP' }
        } else {
            # Admin sieht alles - wenn keine PUBG-Exclusion, dann fehlt sie wirklich
            $s['Defender'] = @{ Value='keine Exclusion'; Status='WARN' }
        }
    } catch { $s['Defender'] = @{ Value='Fehler'; Status='SKIP' } }

    # PUBG laeuft?
    $pubg = @(Get-Process -Name 'TslGame' -ErrorAction SilentlyContinue)
    $s['PUBG'] = if ($pubg.Count -gt 0) { @{ Value="laeuft (PID $($pubg[0].Id))"; Status='INFO' } } else { @{ Value='nicht aktiv'; Status='INFO' } }

    # GPU (dedicated, ohne iGPU)
    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'NVIDIA|GeForce|RTX|GTX|Quadro|Radeon RX|Radeon Pro' -and $_.Name -notmatch 'Vega.*Graphics|Radeon.*Graphics$|UHD|Iris|HD Graphics' } |
            Select-Object -First 1
        $s['GPU'] = if ($gpu) { @{ Value=($gpu.Name -replace 'NVIDIA GeForce ','' -replace 'AMD ',''); Status='INFO' } } else { @{ Value='?'; Status='SKIP' } }
    } catch { $s['GPU'] = @{ Value='?'; Status='SKIP' } }

    # GPU-Treiber: Version (via nvidia-smi, sonst Win32) + Alter. Ein echter
    # "neueste Version?"-Online-Abgleich ist nicht zuverlaessig moeglich (keine
    # offizielle API) - daher altersbasiert: WARN ab 90 Tagen.
    try {
        $drvVer = $null; $drvDate = $null
        $nvSmiCmd = Get-Command nvidia-smi -ErrorAction SilentlyContinue
        if ($nvSmiCmd) {
            try { $drvVer = (& nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>$null | Select-Object -First 1) } catch {}
            if ($drvVer) { $drvVer = $drvVer.Trim() }
        }
        $vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'NVIDIA|GeForce|RTX|GTX|Radeon RX' } | Select-Object -First 1
        if (-not $drvVer -and $vc -and $vc.DriverVersion) { $drvVer = $vc.DriverVersion }
        if ($vc -and $vc.DriverDate) {
            try { $drvDate = [Management.ManagementDateTimeConverter]::ToDateTime($vc.DriverDate) } catch {}
        }
        if ($drvVer) {
            if ($drvDate) {
                $ageDays = [int]((Get-Date) - $drvDate).TotalDays
                $st = if ($ageDays -gt 90) { 'WARN' } else { 'OK' }
                $s['GPU-Treiber'] = @{ Value="$drvVer ($ageDays d alt)"; Status=$st }
            } else {
                $s['GPU-Treiber'] = @{ Value="$drvVer"; Status='INFO' }
            }
        } else {
            $s['GPU-Treiber'] = @{ Value='nicht auslesbar'; Status='SKIP' }
        }
    } catch { $s['GPU-Treiber'] = @{ Value='?'; Status='SKIP' } }

    # CPU - Marketing-Suffixe abkuerzen damit der Name in die Card passt
    try {
        $cpu = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name
        if ($cpu) {
            $cpuShort = $cpu -replace 'Intel\(R\)\s*Core\(TM\)\s*','' `
                              -replace 'AMD\s+','' `
                              -replace '\s+CPU\s+@.*$','' `
                              -replace '\s+Processor.*$','' `
                              -replace '\s+\d+-Core.*$','' `
                              -replace '\s{2,}',' '
            $cpuShort = $cpuShort.Trim()
            if ($cpuShort.Length -gt 28) { $cpuShort = $cpuShort.Substring(0,28) + '...' }
            $s['CPU'] = @{ Value=$cpuShort; Status='INFO' }
        } else {
            $s['CPU'] = @{ Value='?'; Status='SKIP' }
        }
    } catch { $s['CPU'] = @{ Value='?'; Status='SKIP' } }

    # Display: hoechste aktive Refresh-Rate als Headline
    try {
        $hz = (Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
            Where-Object { $_.CurrentRefreshRate -gt 0 } |
            Sort-Object -Property CurrentRefreshRate -Descending |
            Select-Object -First 1).CurrentRefreshRate
        $s['Display'] = if ($hz -and $hz -gt 0) { @{ Value="$hz Hz"; Status='INFO' } } else { @{ Value='?'; Status='SKIP' } }
    } catch { $s['Display'] = @{ Value='?'; Status='SKIP' } }

    return $s
}

# ==================== PUBG-PFAD- & INI-HELFER ====================
# Die System-Tweaks selbst kommen aus config\PUBGTweakRegistry.psm1 (siehe
# unten "GETEILTE KONFIGURATION"). Hier nur noch geteilte Helfer, die auch
# das esportgfx-Grafikprofil und die Live-Status-Anzeige nutzen.

function Get-PUBGEnginePath { "$env:LOCALAPPDATA\TslGame\Saved\Config\WindowsNoEditor\Engine.ini" }
function Get-PUBGGameUserPath { "$env:LOCALAPPDATA\TslGame\Saved\Config\WindowsNoEditor\GameUserSettings.ini" }

function Get-PrimaryMonitorHz {
    # Hoechste aktuell aktive Refresh-Rate (= Gaming-Monitor wenn mehrere vorhanden)
    try {
        $hz = (Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
            Where-Object { $_.CurrentRefreshRate -gt 0 } |
            Sort-Object -Property CurrentRefreshRate -Descending |
            Select-Object -First 1).CurrentRefreshRate
        if ($hz -and $hz -gt 0) { return [int]$hz }
    } catch {}  # CIM-Abfrage fehlgeschlagen -> Fallback unten greift
    return 240  # Fallback
}

function Get-OptimalFpsCap {
    # Competitive-Cap = Monitor-Hz minus FpsCapOffset (aus PUBGProfile.psd1),
    # harte Untergrenze 60 FPS - identische Rechnung wie der Tweak 'fpscap'.
    $hz = Get-PrimaryMonitorHz
    $offset = if ($Global:EsportGfxProfileMeta -and $null -ne $Global:EsportGfxProfileMeta.FpsCapOffset) {
        [int]$Global:EsportGfxProfileMeta.FpsCapOffset
    } else { 3 }
    return [Math]::Max(60, $hz - $offset)
}

function Update-IniValue {
    param([string]$Path, [string]$Section, [string]$Key, [string]$Value)
    if (-not (Test-Path $Path)) {
        Write-SuiteLog "Update-IniValue: Datei nicht gefunden: $Path" 'WARN'
        return $false
    }
    # KRITISCH: Wenn Read fehlschlaegt (Permission/Lock), NICHT schreiben - sonst $null overwrite!
    try {
        $content = Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-SuiteLog "Update-IniValue: Read-Fehler $($_.Exception.Message)" 'ERROR'
        return $false
    }
    if ($null -eq $content) {
        Write-SuiteLog "Update-IniValue: Datei leer/null: $Path - kein Write" 'WARN'
        return $false
    }
    # Backup mit eindeutigem Sub-Sekunden-Timestamp (verhindert Overwrite bei mehreren Calls/Session)
    $bakTs = Get-Date -Format 'yyyy-MM-dd_HHmmss_fff'
    $bak = "$Path.bak_$bakTs"
    try {
        Copy-Item $Path $bak -Force -ErrorAction Stop
    } catch {
        Write-SuiteLog "Update-IniValue: Backup-Fehler $($_.Exception.Message)" 'WARN'
        # Wir machen weiter, aber Backup fehlt
    }
    $secPattern = "(?ms)^\[" + [regex]::Escape($Section) + "\]\s*\r?\n(.*?)(?=^\[|\z)"
    $keyPattern = "(?m)^\s*" + [regex]::Escape($Key) + "\s*=.*$"
    if ($content -match $secPattern) {
        $body = $matches[1]
        if ($body -match $keyPattern) {
            $body = $body -replace $keyPattern, "$Key=$Value"
        } else {
            $body = $body.TrimEnd() + "`r`n$Key=$Value`r`n"
        }
        $content = $content -replace $secPattern, "[$Section]`r`n$body"
    } else {
        $content = $content.TrimEnd() + "`r`n`r`n[$Section]`r`n$Key=$Value`r`n"
    }
    # Sicherheits-Check: Content muss substantiell sein vor Write
    if ([string]::IsNullOrWhiteSpace($content) -or $content.Length -lt 5) {
        Write-SuiteLog "Update-IniValue: Berechnetes Content zu klein/leer - kein Write" 'ERROR'
        return $false
    }
    # Falls Datei read-only ist (z.B. nach vorherigem Apply): kurz writable machen
    $wasReadOnly = $false
    try {
        $fi = Get-Item $Path -Force
        if (($fi.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
            $fi.Attributes = $fi.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
            $wasReadOnly = $true
        }
    } catch {
        Write-SuiteLog "Update-IniValue: ReadOnly-Flag konnte nicht entfernt werden ($($_.Exception.Message)) - Write koennte scheitern" 'WARN'
    }
    try {
        Set-Content -Path $Path -Value $content -NoNewline -Encoding UTF8 -ErrorAction Stop
        # Wenn die Datei vorher schon ReadOnly war (Apply re-run), Flag wiederherstellen
        if ($wasReadOnly) {
            try {
                $fi2 = Get-Item $Path -Force
                $fi2.Attributes = $fi2.Attributes -bor [System.IO.FileAttributes]::ReadOnly
            } catch {
                Write-SuiteLog "Update-IniValue: ReadOnly-Flag konnte nicht wiederhergestellt werden ($($_.Exception.Message))" 'WARN'
            }
        }
        return $true
    } catch {
        Write-SuiteLog "Update-IniValue: Write-Fehler $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

# ==================== GETEILTE KONFIGURATION (PROFIL + TWEAK-REGISTRY) ========
# Single Source of Truth: das PUBG-Grafikprofil und die Tweak-Registry liegen
# in config\ und werden von Suite UND Diagnose-Skript gemeinsam genutzt. Kein
# Hardcoding der Werte mehr in der Suite.

# --- PUBG-Grafikprofil aus config\PUBGProfile.psd1 laden ----------------------
# $Global:EsportGfxProfile bekommt exakt die alte Struktur (Sektion -> Keys),
# damit der Grafik-Tab und die Apply-Logik unveraendert damit arbeiten koennen.
$Global:EsportGfxProfileMeta = @{ Version = '?'; Path = $Global:Suite.ProfilePath; FpsCapOffset = 3 }
$Global:EsportGfxProfile = $null
try {
    if (-not (Test-Path $Global:Suite.ProfilePath)) {
        throw "Profil-Datei nicht gefunden: $($Global:Suite.ProfilePath)"
    }
    $profileData = Import-PowerShellDataFile -Path $Global:Suite.ProfilePath -ErrorAction Stop
    $Global:EsportGfxProfile = $profileData.Sections
    $Global:EsportGfxProfileMeta.Version = "$($profileData.ProfileVersion)"
    if ($null -ne $profileData.FpsCapOffset) {
        $Global:EsportGfxProfileMeta.FpsCapOffset = [int]$profileData.FpsCapOffset
    }
    Write-SuiteLog "Grafikprofil geladen: v$($profileData.ProfileVersion) ($($Global:Suite.ProfilePath))" 'INFO'
} catch {
    Write-SuiteLog "FEHLER beim Laden des Grafikprofils: $($_.Exception.Message)" 'ERROR'
}

# --- Tweak-Registry-Modul importieren -----------------------------------------
try {
    if (-not (Test-Path $Global:Suite.RegistryPath)) {
        throw "Registry-Modul nicht gefunden: $($Global:Suite.RegistryPath)"
    }
    Import-Module $Global:Suite.RegistryPath -Force -ErrorAction Stop
    Write-SuiteLog "Tweak-Registry geladen: $($Global:Suite.RegistryPath)" 'INFO'
} catch {
    Write-SuiteLog "FEHLER beim Laden der Tweak-Registry: $($_.Exception.Message)" 'ERROR'
}

# --- $Global:Tweaks aus der Registry aufbauen (Adapter) -----------------------
# Die Registry liefert Id/Category/Label/Description/Impact/RequiresAdmin/
# Changes + die Scriptbloecke Check/Apply/Revert. Die Suite-UI erwartet
# historisch die Feldnamen Cat/Name/Desc/Admin und einen StatusFn, der einen
# Alt-Status (OK/WARN/BAD/SKIP) liefert. ConvertTo-SuiteTweak baut diese
# Bruecke; StatusFn ist eine Closure (GetNewClosure) pro Tweak, damit jeder
# Eintrag seinen eigenen Check referenziert.
function ConvertTo-SuiteTweak {
    param($RegTweak)
    $regCheck = $RegTweak.Check
    $statusFn = {
        try { $r = & $regCheck } catch { return 'SKIP' }
        switch ("$($r.Status)") { 'TWEAK' { 'WARN' } 'ISSUE' { 'BAD' } 'OK' { 'OK' } 'SKIP' { 'SKIP' } default { 'SKIP' } }
    }.GetNewClosure()
    [PSCustomObject]@{
        Id           = $RegTweak.Id
        Cat          = $RegTweak.Category
        Name         = $RegTweak.Label
        Desc         = $RegTweak.Description
        Admin        = [bool]$RegTweak.RequiresAdmin
        Impact       = $RegTweak.Impact
        ImpactDetail = $RegTweak.ImpactDetail
        Changes      = $RegTweak.Changes
        Check        = $RegTweak.Check
        Apply        = $RegTweak.Apply
        Revert       = $RegTweak.Revert
        StatusFn     = $statusFn
    }
}

$Global:Tweaks = @()
if (Get-Command Get-PUBGTweakRegistry -ErrorAction SilentlyContinue) {
    $Global:Tweaks = @(Get-PUBGTweakRegistry | ForEach-Object { ConvertTo-SuiteTweak -RegTweak $_ })
    Write-SuiteLog "Tweaks aus Registry uebernommen: $($Global:Tweaks.Count)" 'INFO'
} else {
    Write-SuiteLog 'Get-PUBGTweakRegistry nicht verfuegbar - Tweaks-Tab bleibt leer' 'ERROR'
}

# ==================== ESPORT-GRAFIK-PROFIL (eigener Grafik-Tab) ===============
# esportgfx ist KEIN Registry-Tweak: es bekommt einen eigenen Tab mit separatem
# Apply/Revert und wird nie von "Apply All" erfasst. Es schreibt das aus
# PUBGProfile.psd1 geladene Profil in PUBGs GameUserSettings.ini.

# Prueft GameUserSettings.ini gegen das geladene Profil.
# Rueckgabe: @{ Status='OK'|'TWEAK'|'SKIP'; CurrentValue; Detail }
function Test-EsportGfxProfile {
    $gus = Get-PUBGGameUserPath
    if (-not (Test-Path $gus)) {
        return @{ Status='SKIP'; CurrentValue='GameUserSettings.ini nicht gefunden'
                  Detail='PUBG mind. einmal starten und beenden' }
    }
    if (-not $Global:EsportGfxProfile) {
        return @{ Status='SKIP'; CurrentValue='Profil nicht geladen'
                  Detail='PUBGProfile.psd1 fehlt oder ist fehlerhaft' }
    }
    $c = Get-Content $gus -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($c)) {
        return @{ Status='SKIP'; CurrentValue='GameUserSettings.ini leer'; Detail='' }
    }
    $mismatch = @()
    foreach ($section in $Global:EsportGfxProfile.Keys) {
        foreach ($key in $Global:EsportGfxProfile[$section].Keys) {
            $want = [string]$Global:EsportGfxProfile[$section][$key]
            $rx   = '(?m)^\s*' + [regex]::Escape($key) + '\s*=\s*(.+?)\s*$'
            if ($c -match $rx) { $have = $matches[1] } else { $have = $null }
            if ($null -eq $have) { $mismatch += $key; continue }
            # Float-tolerant: '100.000000' == '100', PowerShell-[double]-Cast ist
            # kultur-invariant (Dezimalpunkt). Bools wie 'False' werfen -> String-Vergleich.
            $wantNum = $null; $haveNum = $null
            try { $wantNum = [double]$want } catch {}  # nicht-numerisch (z.B. 'False') -> bleibt $null, String-Vergleich greift
            try { $haveNum = [double]$have } catch {}  # dito
            if ($null -ne $wantNum -and $null -ne $haveNum) {
                if ([math]::Floor($wantNum) -ne [math]::Floor($haveNum)) { $mismatch += $key }
            } elseif ($want -ne $have) {
                $mismatch += $key
            }
        }
    }
    if ($mismatch.Count -eq 0) {
        return @{ Status='OK'; CurrentValue='alle Profil-Werte gesetzt'; Detail='' }
    }
    $preview = ($mismatch | Select-Object -First 4) -join ', '
    return @{ Status='TWEAK'
              CurrentValue="$($mismatch.Count) Wert(e) abweichend: $preview"
              Detail='Grafik-Profil ueber den Grafik-Tab anwenden' }
}

# Schreibt das Profil in GameUserSettings.ini.
# Rueckgabe: @{ Success; Message; Snapshot }
function Invoke-EsportGfxApply {
    try {
        $gus = Get-PUBGGameUserPath
        if (-not (Test-Path $gus)) {
            return @{ Success=$false; Message='GameUserSettings.ini nicht gefunden - PUBG einmal starten/beenden'; Snapshot=$null }
        }
        if (-not $Global:EsportGfxProfile) {
            return @{ Success=$false; Message='Grafikprofil nicht geladen (PUBGProfile.psd1)'; Snapshot=$null }
        }
        # PUBG darf nicht laufen - es ueberschreibt GameUserSettings.ini beim Beenden.
        if (@(Get-Process -Name 'TslGame' -ErrorAction SilentlyContinue).Count -gt 0) {
            return @{ Success=$false; Message='PUBG laeuft - bitte erst komplett beenden, dann Apply'; Snapshot=$null }
        }
        $bak  = Copy-FileToBackup -SourcePath $gus
        $snap = @{ BackupPath=$bak; OriginalPath=$gus }
        foreach ($section in $Global:EsportGfxProfile.Keys) {
            foreach ($key in $Global:EsportGfxProfile[$section].Keys) {
                $val = [string]$Global:EsportGfxProfile[$section][$key]
                if (-not (Update-IniValue -Path $gus -Section $section -Key $key -Value $val)) {
                    Write-SuiteLog "esportgfx: Update fehlgeschlagen bei [$section] $key" 'ERROR'
                    return @{ Success=$false; Message="Schreiben fehlgeschlagen bei [$section] $key"; Snapshot=$snap }
                }
            }
        }
        # Aufloesung bleibt unveraendert, ABER LastUserConfirmedResolutionSizeX/Y
        # werden mit der aktuellen Aufloesung synchronisiert. Zusammen mit den im
        # Profil enthaltenen FullscreenMode/LastConfirmedFullscreenMode/Preferred-
        # FullscreenMode akzeptiert PUBG die Werte beim Start als "zuletzt
        # bestaetigt" und setzt das Profil nicht zurueck.
        $cNow = Get-Content $gus -Raw -ErrorAction SilentlyContinue
        $resSection = '/Script/TslGame.TslGameUserSettings'
        foreach ($axis in 'X','Y') {
            if ($cNow -and ($cNow -match "(?m)^\s*ResolutionSize$axis\s*=\s*(\d+)")) {
                $null = Update-IniValue -Path $gus -Section $resSection -Key "LastUserConfirmedResolutionSize$axis" -Value $matches[1]
            }
        }
        # FPS-Cap menuekonform setzen = In-Game "Display Based" (FrameRateLimit auf
        # die Monitor-Hz). FrameRateLimit liegt in [/Script/TslGame.TslGameUserSettings].
        # Ein krummer Wert wie 237 ist ueber das Spiel-Menue NICHT erzeugbar und wird
        # von PUBG beim Start zurueckgesetzt - der scharfe Competitive-Cap (Hz minus 3)
        # laeuft daher ueber den NVIDIA Frame Rate Limiter (Tweak 'nvprofile').
        $capHz = Get-PrimaryMonitorHz
        $capWritten = Update-IniValue -Path $gus -Section $resSection -Key 'FrameRateLimit' -Value ('{0}.000000' -f $capHz)
        # Post-Apply-Verifikation: FrameRateLimit zuruecklesen
        $vNow = Get-Content $gus -Raw -ErrorAction SilentlyContinue
        $capOk = $capWritten -and ($vNow -match '(?m)^\s*FrameRateLimit\s*=\s*([\d.]+)') `
                 -and ([int][math]::Floor([double]$matches[1]) -eq $capHz)
        $capMsg = if ($capOk) {
            "FPS-Cap: In-Game Display-Based ($capHz) - scharfer Cap $($capHz - 3) via NVIDIA-Profil (Tweak 'nvprofile' anwenden)"
        } else {
            'WARN: FrameRateLimit (FPS-Cap) konnte nicht verifiziert werden'
        }
        Write-SuiteLog "esportgfx: Competitive-Grafik-Profil + LastUserConfirmed + FrameRateLimit geschrieben - $capMsg" 'INFO'
        return @{ Success=$true; Message="Competitive-Grafik-Profil angewendet. $capMsg"; Snapshot=$snap }
    } catch {
        Write-SuiteLog "esportgfx Apply Exception: $($_.Exception.Message)" 'ERROR'
        return @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null }
    }
}

# Stellt GameUserSettings.ini aus dem Backup wieder her.
function Invoke-EsportGfxRevert {
    param($Snapshot)
    if ($Snapshot -and $Snapshot.BackupPath -and $Snapshot.OriginalPath) {
        if (Restore-FileFromBackup -BackupPath $Snapshot.BackupPath -TargetPath $Snapshot.OriginalPath) {
            return @{ Success=$true; Message='GameUserSettings.ini aus Backup wiederhergestellt' }
        }
        return @{ Success=$false; Message='Restore aus Backup fehlgeschlagen' }
    }
    return @{ Success=$false; Message='Kein Backup-Snapshot vorhanden' }
}

# Schreibt eine im Grafik-Tab frei zusammengestellte Werte-Auswahl in
# GameUserSettings.ini. Gleiche Schutzmechanismen wie Invoke-EsportGfxApply
# (PUBG-Prozess-Check, Update-IniValue sichert vor jeder Aenderung selbst),
# aber mit den vom Nutzer gewaehlten Werten statt dem Profil. FullscreenMode
# wird mit LastConfirmed/Preferred synchronisiert, damit PUBG die Auswahl
# nicht beim Start zuruecksetzt.
#   $Values = @{ '<INI-Sektion>' = @{ '<Key>' = '<Wert>' } }
# Rueckgabe: @{ Success; Message }
function Invoke-EsportGfxApplyCustom {
    param([hashtable]$Values)
    try {
        $gus = Get-PUBGGameUserPath
        if (-not (Test-Path $gus)) {
            return @{ Success=$false; Message='GameUserSettings.ini nicht gefunden - PUBG einmal starten/beenden' }
        }
        if (@(Get-Process -Name 'TslGame' -ErrorAction SilentlyContinue).Count -gt 0) {
            return @{ Success=$false; Message='PUBG laeuft - bitte erst komplett beenden, dann Apply' }
        }
        foreach ($section in $Values.Keys) {
            foreach ($key in $Values[$section].Keys) {
                $val = [string]$Values[$section][$key]
                if (-not (Update-IniValue -Path $gus -Section $section -Key $key -Value $val)) {
                    Write-SuiteLog "esportgfx (custom): Update fehlgeschlagen bei [$section] $key" 'ERROR'
                    return @{ Success=$false; Message="Schreiben fehlgeschlagen bei [$section] $key" }
                }
            }
        }
        # FullscreenMode konsistent halten (sonst Confirm-Dialog/Reset beim Start)
        $resSection = '/Script/TslGame.TslGameUserSettings'
        if ($Values[$resSection] -and $Values[$resSection].ContainsKey('FullscreenMode')) {
            $fm = [string]$Values[$resSection]['FullscreenMode']
            $null = Update-IniValue -Path $gus -Section $resSection -Key 'LastConfirmedFullscreenMode' -Value $fm
            $null = Update-IniValue -Path $gus -Section $resSection -Key 'PreferredFullscreenMode' -Value $fm
        }
        # LastUserConfirmedResolutionSizeX/Y mit aktueller Aufloesung synchron halten
        $cNow = Get-Content $gus -Raw -ErrorAction SilentlyContinue
        foreach ($axis in 'X','Y') {
            if ($cNow -and ($cNow -match "(?m)^\s*ResolutionSize$axis\s*=\s*(\d+)")) {
                $null = Update-IniValue -Path $gus -Section $resSection -Key "LastUserConfirmedResolutionSize$axis" -Value $matches[1]
            }
        }
        Write-SuiteLog 'esportgfx: Einzel-Grafikwerte geschrieben' 'INFO'
        return @{ Success=$true; Message='Einzel-Einstellungen angewendet' }
    } catch {
        Write-SuiteLog "esportgfx ApplyCustom Exception: $($_.Exception.Message)" 'ERROR'
        return @{ Success=$false; Message="Fehler: $($_.Exception.Message)" }
    }
}

$Global:EsportGfxTweak = [PSCustomObject]@{
    Id           = 'esportgfx'
    Cat          = 'PUBG'
    Name         = 'PUBG Esport-Grafik (Competitive-Profil)'
    Desc         = 'Schreibt PUBGs In-Game-Grafik aufs Competitive-Profil aus PUBGProfile.psd1. Alle Werte menue-konform (BattlEye-safe).'
    Admin        = $false
    Impact       = 'MITTEL'
    ImpactDetail = 'Aendert dein In-Game-Grafikmenue (geringere Detailstufe). PUBG muss beim Apply GESCHLOSSEN sein. Aufloesung bleibt unveraendert. Voll reversibel via Datei-Backup.'
    Changes      = @(
        'Datei: %LOCALAPPDATA%\TslGame\Saved\Config\WindowsNoEditor\GameUserSettings.ini',
        'Soll-Werte stammen aus config\PUBGProfile.psd1 (gemeinsame Quelle mit der Diagnose)',
        'Backup vor Aenderung als .bak_<timestamp> (Revert stellt es wieder her)',
        'WICHTIG: PUBG muss beim Apply geschlossen sein',
        'Aufloesung wird NICHT veraendert - LastUserConfirmedResolutionSizeX/Y werden nur synchron gehalten',
        'FullscreenMode + LastConfirmedFullscreenMode + PreferredFullscreenMode = 0 (Exklusiv-Vollbild)',
        '[ScalabilityGroups] sg.* sowie [TslGameUserSettings] Bool-/Skalierungs-Werte laut Profil'
    )
    Check    = { Test-EsportGfxProfile }
    Apply    = { Invoke-EsportGfxApply }
    Revert   = { param($Snapshot) Invoke-EsportGfxRevert $Snapshot }
    StatusFn = {
        $s = (Test-EsportGfxProfile).Status
        switch ("$s") { 'TWEAK' { 'WARN' } 'ISSUE' { 'BAD' } 'OK' { 'OK' } default { 'SKIP' } }
    }
}

# ==================== TOOL-DETECTION & INSTALL ====================
function Get-MMTPath {
    foreach ($p in @($Global:Suite.Tools.MMT, "$env:USERPROFILE\Tools\MultiMonitorTool\MultiMonitorTool.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Install-MMT {
    param([scriptblock]$LogCallback)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $target = Split-Path $Global:Suite.Tools.MMT -Parent
        try {
            if (-not (Test-Path $target)) { New-Item -Path $target -ItemType Directory -Force -ErrorAction Stop | Out-Null }
        } catch {
            $target = Join-Path $env:USERPROFILE 'Tools\MultiMonitorTool'
            if (-not (Test-Path $target)) { New-Item -Path $target -ItemType Directory -Force | Out-Null }
            & $LogCallback "  C:\Tools nicht beschreibbar - fallback: $target"
        }
        $zip = Join-Path $env:TEMP "mmt_$(Get-Random).zip"
        & $LogCallback "  Lade MultiMonitorTool von NirSoft..."
        try {
            Invoke-WebRequest -Uri 'https://www.nirsoft.net/utils/multimonitortool-x64.zip' -OutFile $zip -UseBasicParsing -ErrorAction Stop
            Expand-Archive -Path $zip -DestinationPath $target -Force -ErrorAction Stop
        } finally {
            if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
        }
        $exe = Join-Path $target 'MultiMonitorTool.exe'
        if (Test-Path $exe) {
            & $LogCallback "  Installiert: $exe"
            Write-SuiteLog "MMT installiert: $exe" 'INFO'
            return $exe
        } else {
            & $LogCallback "  FEHLER: MultiMonitorTool.exe nicht im entpackten Archiv"
            Write-SuiteLog "MMT-Install: exe nicht im Archiv" 'ERROR'
            return $null
        }
    } catch {
        & $LogCallback "  FEHLER bei MMT-Install: $($_.Exception.Message)"
        Write-SuiteLog "MMT-Install Fehler: $($_.Exception.Message)" 'ERROR'
        return $null
    }
}

# ==================== GAME MODE ACTIONS ====================
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

function Start-GameMode {
    param(
        [bool]$DisableMonitors = $true,
        [bool]$KillRTSS = $true,
        [bool]$KillBackground = $true,
        [bool]$LaunchPUBG = $false,
        [scriptblock]$LogCallback
    )

    & $LogCallback "=== START GAME MODE ===" 'INFO'

    # 1. Monitore
    if ($DisableMonitors) {
        $mmt = Get-MMTPath
        if (-not $mmt) {
            & $LogCallback "MMT nicht gefunden - installiere..." 'WARN'
            $mmt = Install-MMT -LogCallback $LogCallback
        }
        if ($mmt -and [string]::IsNullOrWhiteSpace($Global:Suite.MonitorPattern)) {
            # Kein Pattern (Solo-Setup) - ein leeres Regex wuerde ALLE Monitore
            # matchen. Daher hier explizit nichts deaktivieren.
            & $LogCallback "Kein Monitor-Pattern gesetzt (Solo-Setup) - kein Monitor wird deaktiviert" 'INFO'
        } elseif ($mmt) {
            $monitors = Get-MonitorTable -Mmt $mmt
            $toDisable = @($monitors | Where-Object { $_.'Monitor Name' -match $Global:Suite.MonitorPattern -and $_.Active -eq 'Yes' })
            $remainingActive = @($monitors | Where-Object { $_.'Monitor Name' -notmatch $Global:Suite.MonitorPattern -and $_.Active -eq 'Yes' })
            if ($toDisable.Count -gt 0 -and $remainingActive.Count -gt 0) {
                $ids = @($toDisable | ForEach-Object { $_.'Short Monitor ID' })
                $ids | Set-Content -Path $Global:Suite.MonitorIDs -Encoding UTF8
                & $LogCallback "Deaktiviere Monitore: $($ids -join ', ')" 'INFO'
                & $mmt /disable @ids
                Start-Sleep -Seconds 2
                & $LogCallback "  -> erledigt" 'OK'
            } elseif ($toDisable.Count -eq 0) {
                & $LogCallback "Keine aktiven '$($Global:Suite.MonitorPattern)' Monitore - skip" 'INFO'
            } else {
                & $LogCallback "Wuerde Total-Lockout verursachen - skip" 'WARN'
            }
        }
    }

    # 2. RTSS killen
    if ($KillRTSS) {
        # @() Wrapper damit .Count auch bei einzelnem Prozess geht
        $rtss = @(Get-Process -Name 'RTSS','RTSSHooksLoader64' -ErrorAction SilentlyContinue)
        if ($rtss.Count -gt 0) {
            $rtss | Stop-Process -Force -ErrorAction SilentlyContinue
            & $LogCallback "RTSS killed ($($rtss.Count) Prozess(e))" 'OK'
        } else {
            & $LogCallback "RTSS lief nicht" 'INFO'
        }
    }

    # 3. Background Apps
    if ($KillBackground) {
        # Discord BEWUSST nicht in der Liste - bleibt fuer Voice waehrend Match aktiv
        $apps = @('chrome','msedge','firefox','Spotify','EpicGamesLauncher','Battle.net','obs64')
        $killed = 0
        foreach ($a in $apps) {
            $p = @(Get-Process -Name $a -ErrorAction SilentlyContinue)
            if ($p.Count -gt 0) {
                $p | Stop-Process -Force -ErrorAction SilentlyContinue
                & $LogCallback "  -> $a beendet ($($p.Count) Prozess(e))" 'OK'
                $killed++
            }
        }
        if ($killed -eq 0) { & $LogCallback "Keine Hintergrund-Apps zu killen" 'INFO' }
    }

    # 4. PUBG launchen
    if ($LaunchPUBG) {
        & $LogCallback "Starte PUBG ueber Steam..." 'INFO'
        Start-Process $Global:Suite.PUBGSteamURI
    }

    # State speichern
    @{ GameMode = $true; Started = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content $Global:Suite.StateFile

    & $LogCallback "=== GAME MODE AKTIV ===" 'OK'
}

function Stop-GameMode {
    param([scriptblock]$LogCallback)

    & $LogCallback "=== EXIT GAME MODE ===" 'INFO'

    # Monitore wieder an
    $mmt = Get-MMTPath
    if ($mmt -and (Test-Path $Global:Suite.MonitorIDs)) {
        $ids = @(Get-Content $Global:Suite.MonitorIDs | Where-Object { $_.Trim() })
        if ($ids.Count -gt 0) {
            & $LogCallback "Reaktiviere Monitore: $($ids -join ', ')" 'INFO'
            & $mmt /enable @ids
            Start-Sleep -Seconds 2
            Remove-Item $Global:Suite.MonitorIDs -Force -ErrorAction SilentlyContinue
            & $LogCallback "  -> erledigt" 'OK'
        }
    } else {
        & $LogCallback "Fallback: DisplaySwitch /extend" 'INFO'
        & "$env:windir\System32\DisplaySwitch.exe" /extend
        Start-Sleep -Seconds 2
    }

    # State löschen
    Remove-Item $Global:Suite.StateFile -Force -ErrorAction SilentlyContinue

    & $LogCallback "=== GAME MODE BEENDET ===" 'OK'
}

# ==================== XAML GUI ====================
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

$xamlTemplate = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PUBG Performance Suite" Height="700" Width="1050"
        Background="@@BgBase@@" WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <Style TargetType="TabItem">
            <Setter Property="Background" Value="@@Surface1@@"/>
            <Setter Property="Foreground" Value="@@TextPrimary@@"/>
            <Setter Property="BorderBrush" Value="@@BorderSubtle@@"/>
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border Name="Border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="0,0,0,2" Padding="{TemplateBinding Padding}">
                            <ContentPresenter ContentSource="Header" RecognizesAccessKey="True" HorizontalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="BorderBrush" Value="@@Accent@@"/>
                                <Setter Property="Foreground" Value="@@Accent@@"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="@@AccentHover@@"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="@@Accent@@"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="12,0"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="MinHeight" Value="32"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="HorizontalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="@@AccentHover@@"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="@@BorderStrong@@"/>
                    <Setter Property="Foreground" Value="@@TextSecondary@@"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="SectionHeader" TargetType="TextBlock">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="@@Accent@@"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
        </Style>
        <!-- ComboBox: vollstaendiges ControlTemplate. Ohne eigenes Template rendert
             WPF die geschlossene Box mit dem OS-Default-Style (heller Hintergrund)
             und ignoriert Background/Foreground -> Werte waren weiss-auf-weiss. -->
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="@@Surface2@@"/>
            <Setter Property="Foreground" Value="@@TextPrimary@@"/>
            <Setter Property="BorderBrush" Value="@@BorderStrong@@"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="6,2"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Height" Value="26"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="ScrollViewer.CanContentScroll" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton x:Name="ToggleButton" Focusable="False" ClickMode="Press"
                                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Border x:Name="Bd" Background="@@Surface2@@"
                                                BorderBrush="@@BorderStrong@@" BorderThickness="1" CornerRadius="3">
                                            <Path x:Name="Arrow" HorizontalAlignment="Right" VerticalAlignment="Center"
                                                  Margin="0,0,8,0" Data="M 0 0 L 4 4 L 8 0 Z" Fill="@@TextSecondary@@"/>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter TargetName="Bd" Property="BorderBrush" Value="@@Accent@@"/>
                                                <Setter TargetName="Arrow" Property="Fill" Value="@@TextPrimary@@"/>
                                            </Trigger>
                                            <Trigger Property="IsChecked" Value="True">
                                                <Setter TargetName="Bd" Property="BorderBrush" Value="@@Accent@@"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                            </ToggleButton>
                            <ContentPresenter x:Name="ContentSite" IsHitTestVisible="False"
                                              Content="{TemplateBinding SelectionBoxItem}"
                                              ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                              TextElement.Foreground="{TemplateBinding Foreground}"
                                              Margin="8,0,26,0" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                            <Popup x:Name="Popup" Placement="Bottom" Focusable="False" AllowsTransparency="True"
                                   IsOpen="{TemplateBinding IsDropDownOpen}" PopupAnimation="Slide">
                                <Border x:Name="DropDownBorder" Background="@@Surface2@@"
                                        BorderBrush="@@BorderStrong@@" BorderThickness="1" CornerRadius="3"
                                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
                                        MaxHeight="{TemplateBinding MaxDropDownHeight}">
                                    <ScrollViewer SnapsToDevicePixels="True">
                                        <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Foreground" Value="@@TextDisabled@@"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="@@Surface1@@"/>
            <Setter Property="Foreground" Value="@@TextPrimary@@"/>
            <Setter Property="Padding" Value="6,4"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="ItemBorder"
                                Background="{TemplateBinding Background}"
                                Padding="{TemplateBinding Padding}"
                                SnapsToDevicePixels="True">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="@@BorderStrong@@"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="@@Accent@@"/>
                                <Setter Property="Foreground" Value="@@BgBase@@"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="@@Surface1@@"/>
            <Setter Property="BorderBrush" Value="@@BorderSubtle@@"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="6"/>
            <Setter Property="Padding" Value="16"/>
            <Setter Property="Margin" Value="0,0,0,14"/>
        </Style>
        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="@@StatusError@@"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="@@StatusErrorHover@@"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="SuccessButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="@@StatusOK@@"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="@@StatusOKHover@@"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="@@Surface1@@" BorderBrush="@@BorderSubtle@@" BorderThickness="0,0,0,1" Padding="20,10">
            <Grid>
                <StackPanel HorizontalAlignment="Left" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="PUBG PERFORMANCE SUITE" FontSize="17" FontWeight="Bold" Foreground="@@Accent@@" VerticalAlignment="Center"/>
                    <Border Background="@@BgBase@@" CornerRadius="3" Padding="6,2" Margin="10,0,0,0" VerticalAlignment="Center">
                        <TextBlock x:Name="lblVersion" Text="v?" FontSize="10" Foreground="@@TextSecondary@@" FontWeight="SemiBold"/>
                    </Border>
                    <Border x:Name="updateBadge" Background="@@Accent@@" CornerRadius="3" Padding="6,2" Margin="8,0,0,0" VerticalAlignment="Center" Visibility="Collapsed" Cursor="Hand" ToolTip="Klick: Update-Anleitung anzeigen">
                        <TextBlock x:Name="lblUpdate" Text="Update verfuegbar" FontSize="10" Foreground="@@BgBase@@" FontWeight="Bold"/>
                    </Border>
                </StackPanel>
                <StackPanel HorizontalAlignment="Right" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border x:Name="adminBadge" Background="@@BorderStrong@@" CornerRadius="3" Padding="8,3" VerticalAlignment="Center" Margin="0,0,8,0">
                        <TextBlock x:Name="lblAdmin" Text="Admin: ?" Foreground="@@TextPrimary@@" FontSize="10" FontWeight="SemiBold"/>
                    </Border>
                    <Border Background="@@BgBase@@" CornerRadius="3" Padding="8,3" VerticalAlignment="Center" Margin="0,0,12,0">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Status: " Foreground="@@TextSecondary@@" FontSize="11" VerticalAlignment="Center"/>
                            <TextBlock x:Name="lblTopStatus" Text="-/-" Foreground="@@TextPrimary@@" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Border>
                    <Button x:Name="btnRefresh" Content="↻ Refresh" Width="100"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Tabs -->
        <TabControl x:Name="mainTabs" Grid.Row="1" Background="@@BgBase@@" BorderThickness="0" Padding="0">
            <!-- TAB 1: DASHBOARD -->
            <TabItem Header="Dashboard">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Background="@@BgBase@@">
                    <StackPanel Margin="20">
                        <Grid Margin="0,0,0,10">
                            <TextBlock Text="Live Status" FontSize="14" FontWeight="Bold" Foreground="@@Accent@@" HorizontalAlignment="Left"/>
                            <TextBlock x:Name="lblStatusSubtitle" Text="" FontSize="11" Foreground="@@TextDisabled@@" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <ItemsControl x:Name="statusItems">
                            <ItemsControl.ItemsPanel>
                                <ItemsPanelTemplate>
                                    <UniformGrid Columns="4"/>
                                </ItemsPanelTemplate>
                            </ItemsControl.ItemsPanel>
                            <ItemsControl.ItemTemplate>
                                <DataTemplate>
                                    <Border Background="@@Surface1@@" BorderBrush="{Binding BorderColor}" BorderThickness="0,0,0,3" Padding="14,10" Margin="6" CornerRadius="3">
                                        <StackPanel>
                                            <TextBlock Text="{Binding Label}" Foreground="@@TextSecondary@@" FontSize="11"/>
                                            <TextBlock Text="{Binding Value}" Foreground="{Binding TextColor}" FontSize="14" FontWeight="SemiBold" Margin="0,4,0,0" TextWrapping="Wrap"/>
                                        </StackPanel>
                                    </Border>
                                </DataTemplate>
                            </ItemsControl.ItemTemplate>
                        </ItemsControl>

                        <TextBlock Text="Schnell-Aktionen" FontSize="14" FontWeight="Bold" Foreground="@@Accent@@" Margin="0,24,0,10"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Button x:Name="btnStartGameMode" Grid.Column="0" Content="🎯 START GAME MODE" Style="{StaticResource SuccessButton}" Height="60" FontSize="15" FontWeight="Bold" Margin="6"/>
                            <Button x:Name="btnExitGameMode" Grid.Column="1" Content="🛑 EXIT GAME MODE" Style="{StaticResource DangerButton}" Height="60" FontSize="15" FontWeight="Bold" Margin="6"/>
                        </Grid>

                        <TextBlock Text="Empfehlungen" FontSize="14" FontWeight="Bold" Foreground="@@Accent@@" Margin="0,24,0,10"/>
                        <StackPanel x:Name="recoList"/>
                        <Border x:Name="recoEmptyState" Background="@@OkBg@@" BorderBrush="@@StatusOK@@" BorderThickness="0,0,0,2" Padding="14,10" CornerRadius="3" Visibility="Collapsed">
                            <TextBlock Text="✓ Alle Live-Checks gruen. Setup ist sauber - viel Erfolg im Match." Foreground="@@StatusOK@@" FontWeight="SemiBold"/>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 2: DIAGNOSE -->
            <TabItem Header="Diagnose">
                <Grid Margin="20">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Full System Diagnose (v6)" FontSize="14" FontWeight="Bold" Foreground="@@Accent@@" Margin="0,0,0,10"/>
                    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,12">
                        <Button x:Name="btnRunDiag" Content="📊 Run Full Diagnose" Width="200" Height="38"/>
                        <Button x:Name="btnOpenHTML" Content="🌐 Open Last Report" Width="200" Height="38" Margin="10,0,0,0"/>
                        <Button x:Name="btnOpenReports" Content="📁 Reports Folder" Width="160" Height="38" Margin="10,0,0,0"/>
                    </StackPanel>
                    <Border Grid.Row="2" Background="@@Surface1@@" BorderBrush="@@BorderSubtle@@" BorderThickness="1" CornerRadius="4">
                        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="10">
                            <TextBlock x:Name="txtDiagOutput" Text="" Foreground="@@TextPrimary@@" FontFamily="Consolas" FontSize="12" TextWrapping="Wrap"/>
                        </ScrollViewer>
                    </Border>
                </Grid>
            </TabItem>

            <!-- TAB CAPTURE -->
            <TabItem Header="Capture">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">

                        <!-- Status Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Performance Capture (60s)" Style="{StaticResource SectionHeader}"/>
                                <TextBlock Foreground="@@TextSecondary@@" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8">
                                    <Run Text="Misst Frametimes via Intel PresentMon - passiv via ETW, kein DLL-Hook, kein RTSS."/>
                                    <LineBreak/>
                                    <Run Text="Voraussetzungen: PUBG laeuft, du bist im Match. Game Mode (Monitore solo + RTSS aus) empfohlen davor."/>
                                </TextBlock>

                                <Grid Margin="0,4,0,0">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="PresentMon: " Foreground="@@TextPrimary@@" FontSize="12" VerticalAlignment="Center"/>
                                    <TextBlock Grid.Column="1" x:Name="lblCapToolStatus" Text="pruefe..." Foreground="@@TextSecondary@@" FontSize="12" VerticalAlignment="Center"/>
                                </Grid>

                                <StackPanel Orientation="Horizontal" Margin="0,12,0,0">
                                    <Button x:Name="btnCapStart" Content="▶ START 60s CAPTURE" Style="{StaticResource SuccessButton}" Width="220" Height="44" FontWeight="Bold"/>
                                    <Button x:Name="btnCapStop" Content="Stop" Style="{StaticResource DangerButton}" Width="100" Height="44" Margin="8,0,0,0" IsEnabled="False"/>
                                </StackPanel>

                                <TextBlock x:Name="lblCapPhase" Text="Bereit." Foreground="@@Accent@@" FontSize="12" FontWeight="SemiBold" Margin="0,12,0,0"/>
                            </StackPanel>
                        </Border>

                        <!-- Last Result Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Letzte Messung" Style="{StaticResource SectionHeader}"/>
                                <TextBlock x:Name="lblCapLastInfo" Text="Noch keine Messung gemacht." Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,8"/>

                                <Grid x:Name="capResultGrid" Visibility="Collapsed">
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>

                                    <!-- Row 0: FPS-Hauptmetriken -->
                                    <Border Grid.Row="0" Grid.Column="0" Background="@@BgBase@@" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="AVG FPS" Foreground="@@TextSecondary@@" FontSize="10"/>
                                            <TextBlock x:Name="lblCapAvg" Text="-" Foreground="@@StatusOK@@" FontSize="22" FontWeight="Bold"/>
                                            <TextBlock Text="Durchschnitt ueber Capture" Foreground="@@TextDisabled@@" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="0" Grid.Column="1" Background="@@BgBase@@" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="1% LOW" Foreground="@@TextSecondary@@" FontSize="10"/>
                                            <TextBlock x:Name="lblCap1Low" Text="-" Foreground="@@StatusWarn@@" FontSize="22" FontWeight="Bold"/>
                                            <TextBlock Text="schlechteste 1% der Frames" Foreground="@@TextDisabled@@" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="0" Grid.Column="2" Background="@@BgBase@@" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="0.1% LOW" Foreground="@@TextSecondary@@" FontSize="10"/>
                                            <TextBlock x:Name="lblCap01Low" Text="-" Foreground="@@StatusError@@" FontSize="22" FontWeight="Bold"/>
                                            <TextBlock Text="worst-case Stutter-Floor" Foreground="@@TextDisabled@@" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="0" Grid.Column="3" Background="@@BgBase@@" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="STDDEV (Frame Pacing)" Foreground="@@TextSecondary@@" FontSize="10"/>
                                            <TextBlock x:Name="lblCapStdDev" Text="-" Foreground="@@Accent@@" FontSize="22" FontWeight="Bold"/>
                                            <TextBlock x:Name="lblCapStability" Text="-" Foreground="@@TextDisabled@@" FontSize="9"/>
                                        </StackPanel>
                                    </Border>

                                    <!-- Row 1: Bottleneck-Analyse -->
                                    <Border Grid.Row="1" Grid.Column="0" Background="@@BgBase@@" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="BOTTLENECK" Foreground="@@TextSecondary@@" FontSize="10"/>
                                            <TextBlock x:Name="lblCapBottleneck" Text="-" Foreground="@@TextPrimary@@" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="wer limitiert?" Foreground="@@TextDisabled@@" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="1" Grid.Column="1" Background="@@BgBase@@" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="CPU BUSY" Foreground="@@TextSecondary@@" FontSize="10"/>
                                            <TextBlock x:Name="lblCapCpuBusy" Text="-" Foreground="@@TextPrimary@@" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="ms CPU pro Frame" Foreground="@@TextDisabled@@" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="1" Grid.Column="2" Background="@@BgBase@@" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="GPU BUSY" Foreground="@@TextSecondary@@" FontSize="10"/>
                                            <TextBlock x:Name="lblCapGpuBusy" Text="-" Foreground="@@TextPrimary@@" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="ms GPU pro Frame" Foreground="@@TextDisabled@@" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="1" Grid.Column="3" Background="@@BgBase@@" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="RENDER LATENCY" Foreground="@@TextSecondary@@" FontSize="10"/>
                                            <TextBlock x:Name="lblCapRenderLat" Text="-" Foreground="@@TextPrimary@@" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="Render -> Present" Foreground="@@TextDisabled@@" FontSize="9"/>
                                        </StackPanel>
                                    </Border>

                                    <!-- Row 2: Latency-Details -->
                                    <Border Grid.Row="2" Grid.Column="0" Background="@@BgBase@@" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="UNTIL DISPLAYED" Foreground="@@TextSecondary@@" FontSize="10"/>
                                            <TextBlock x:Name="lblCapUntilDisp" Text="-" Foreground="@@TextPrimary@@" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="Frame -> Photon" Foreground="@@TextDisabled@@" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="2" Grid.Column="1" Background="@@BgBase@@" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="CLICK->PHOTON" Foreground="@@TextSecondary@@" FontSize="10"/>
                                            <TextBlock x:Name="lblCapClickPhoton" Text="-" Foreground="@@TextPrimary@@" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="nur mit Reflex" Foreground="@@TextDisabled@@" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="2" Grid.Column="2" Background="@@BgBase@@" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="G-SYNC" Foreground="@@TextSecondary@@" FontSize="10"/>
                                            <TextBlock x:Name="lblCapGSync" Text="-" Foreground="@@TextPrimary@@" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="AllowsTearing-Flag" Foreground="@@TextDisabled@@" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="2" Grid.Column="3" Background="@@BgBase@@" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="STUTTER" Foreground="@@TextSecondary@@" FontSize="10"/>
                                            <TextBlock x:Name="lblCapStutter" Text="-" Foreground="@@TextPrimary@@" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="Frames &gt; 2x Avg" Foreground="@@TextDisabled@@" FontSize="9"/>
                                        </StackPanel>
                                    </Border>

                                    <!-- Row 3: Present Mode mit Erklaerung (volle Breite) -->
                                    <Border Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="4" Background="@@BgBase@@" CornerRadius="4" Padding="12,10" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="PRESENT MODE   (Independent / Legacy Flip = OPTIMAL    -    Composed Copy = BAD, ~3-5ms DWM-Overhead)" Foreground="@@TextSecondary@@" FontSize="10"/>
                                            <TextBlock x:Name="lblCapPresentMode" Text="-" Foreground="@@TextPrimary@@" FontSize="15" FontWeight="Bold" TextWrapping="Wrap" Margin="0,3,0,0"/>
                                            <TextBlock x:Name="lblCapPresentExplain" Text="" Foreground="@@TextDisabled@@" FontSize="11" TextWrapping="Wrap" Margin="0,2,0,0"/>
                                        </StackPanel>
                                    </Border>

                                    <!-- Row 4: Metriken-Erklaerung (Expander) -->
                                    <Expander Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="4" Header="Was bedeuten diese Metriken?" Foreground="@@Accent@@" FontSize="11" Margin="4,4,4,0">
                                        <Border Background="@@BgBase@@" CornerRadius="4" Padding="12,10" Margin="0,6,0,0">
                                            <StackPanel>
                                                <TextBlock TextWrapping="Wrap" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="@@StatusOK@@">AVG FPS</Run>
                                                    <Run> - Durchschnittliche Bilder/Sekunde. Hauptkennzahl, aber sagt nichts ueber Konsistenz aus.</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="@@StatusWarn@@">1% LOW</Run>
                                                    <Run> - FPS-Wert den die schlechtesten 1% der Frames erreichen. Wichtiger als AVG fuer Spielgefuehl. Gap zum AVG &gt; 30% = Stutter-Problem.</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="@@StatusError@@">0.1% LOW</Run>
                                                    <Run> - Die schlimmsten 0.1% der Frames - der "Floor" bei dem es richtig haengt. Niedriger Wert = sichtbare Hakler / Shadertompilations / Background-CPU-Spikes.</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="@@Accent@@">STDDEV (ms)</Run>
                                                    <Run> - Standardabweichung der Frametimes in Millisekunden. Misst Frame-Pacing-Konsistenz: niedriger = gleichmaessig fluessig, hoeher = ruckelt selbst bei hoher AVG. Faustregel bei 200+ FPS: &lt; 0.5ms top, 0.5-1.5ms ok, &gt; 2ms unrund.</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="@@TextPrimary@@">BOTTLENECK</Run>
                                                    <Run> - Wer limitiert die FPS: CPU-Bound (CPU rechnet zu lange pro Frame - mehr GPU-Last unkritisch), GPU-Bound (GPU am Limit - Settings reduzieren bringt FPS), Balanced (beide gleich ausgelastet, idealer Zustand fuer competitive).</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="@@TextPrimary@@">CPU/GPU BUSY (ms)</Run>
                                                    <Run> - Wie viele Millisekunden CPU bzw. GPU pro Frame aktiv waren. Bei 200 FPS = 5ms Budget. Wer drueber ist = Bottleneck.</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="@@TextPrimary@@">RENDER LATENCY</Run>
                                                    <Run> - Zeit vom Render-Start bis der Frame "Present"-ed wird. Niedrig = direkte Pipeline. UNTIL DISPLAYED ergaenzt das: Zeit bis Pixel tatsaechlich auf dem Monitor sichtbar sind (Frame-to-Photon).</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="@@TextPrimary@@">CLICK -&gt; PHOTON</Run>
                                                    <Run> - Vollstaendige End-to-End-Latency Maus-Click bis sichtbare Reaktion. Nur verfuegbar bei NVIDIA Reflex (PUBG hat keinen direkten Reflex-Support - daher meist "NA").</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="@@StatusBest@@">PRESENT MODE</Run>
                                                    <Run> - Wie Windows den Frame an den Monitor uebergibt. Hierarchie:</Run>
                                                    <LineBreak/>
                                                    <Run FontWeight="Bold" Foreground="@@StatusBest@@">  - Hardware: Independent Flip  /  Hardware: Legacy Flip  =  OPTIMAL</Run>
                                                    <Run Foreground="@@TextSecondary@@"> (kein DWM-Compositor zwischendrin)</Run>
                                                    <LineBreak/>
                                                    <Run FontWeight="Bold" Foreground="@@StatusOK@@">  - Hardware Composed: Flip  /  Hardware: Legacy Copy  =  OK</Run>
                                                    <Run Foreground="@@TextSecondary@@"> (geringer DWM-Overhead)</Run>
                                                    <LineBreak/>
                                                    <Run FontWeight="Bold" Foreground="@@StatusError@@">  - Composed: Copy with GPU GDI  =  BAD</Run>
                                                    <Run Foreground="@@TextSecondary@@"> (~3-5ms zusaetzliche Latenz - meist durch laufendes RTSS, falsche DPI-Skalierung oder Multi-Monitor-Setup)</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="@@TextPrimary@@">G-SYNC</Run>
                                                    <Run> - "AllowsTearing" Flag in &gt; 50% der Frames. Zeigt ob Variable Refresh Rate (G-Sync/FreeSync) aktiv arbeitet.</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="@@TextSecondary@@" FontSize="11">
                                                    <Run FontWeight="Bold" Foreground="@@TextPrimary@@">STUTTER</Run>
                                                    <Run> - Prozent der Frames die mehr als doppelt so lange dauerten wie der Durchschnitt. &lt; 0.2% = unmerklich, &gt; 0.5% = sichtbar als kurze Hakler.</Run>
                                                </TextBlock>
                                            </StackPanel>
                                        </Border>
                                    </Expander>
                                </Grid>

                                <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                                    <Button x:Name="btnCapOpenCsv" Content="Open last CSV" Width="140" Margin="0,0,8,0"/>
                                    <Button x:Name="btnCapOpenFolder" Content="Open Folder" Width="120" Margin="0,0,8,0"/>
                                    <Button x:Name="btnCapCompare" Content="Compare to previous" Width="180" Margin="0,0,8,0"/>
                                    <Button x:Name="btnCapRebuild" Content="Rebuild from CSVs" Width="160" Margin="0,0,8,0"/>
                                    <Button x:Name="btnCapClearHist" Content="Clear history" Width="140" Style="{StaticResource DangerButton}"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <!-- Vergleich Card (per "Compare to previous" ein-/ausgeblendet) -->
                        <Border x:Name="capCompareCard" Style="{StaticResource Card}" Visibility="Collapsed">
                            <StackPanel>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Vergleich: aktuelle vs. vorherige Messung" Style="{StaticResource SectionHeader}"/>
                                    <Button Grid.Column="1" x:Name="btnCapCompareClose" Content="Schliessen" Width="100" Height="26" VerticalAlignment="Top"/>
                                </Grid>
                                <TextBlock x:Name="lblCapCompareInfo" Text="" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,8"/>
                                <StackPanel x:Name="capCompareList"/>
                            </StackPanel>
                        </Border>

                        <!-- History/Trend Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Trend (letzte Messungen)" Style="{StaticResource SectionHeader}"/>
                                <TextBlock x:Name="lblCapHistInfo" Text="" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,8"/>
                                <StackPanel x:Name="capHistoryList"/>
                            </StackPanel>
                        </Border>

                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 3: GAME MODE -->
            <TabItem Header="Game Mode">
                <Grid Margin="20">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <TextBlock Grid.Row="0" Text="Aktionen die 'Start Game Mode' ausfuehrt" FontSize="14" FontWeight="Bold" Foreground="@@Accent@@" Margin="0,0,0,10"/>

                    <StackPanel Grid.Row="1" Margin="0,0,0,16">
                        <CheckBox x:Name="cbMonitors" Content="Monitore: Sekundaer-Monitore deaktivieren (laut Monitor-Pattern in Settings)" Foreground="@@TextPrimary@@" Margin="0,4" IsChecked="True"/>
                        <CheckBox x:Name="cbRTSS" Content="RTSS Prozesse beenden (kritisch fuer Mode 3/1)" Foreground="@@TextPrimary@@" Margin="0,4" IsChecked="True"/>
                        <CheckBox x:Name="cbBackground" Content="Hintergrund-Apps schliessen (Chrome, Spotify, Battle.net, Epic, OBS - Discord bleibt fuer Voice)" Foreground="@@TextPrimary@@" Margin="0,4" IsChecked="True"/>
                        <CheckBox x:Name="cbLaunch" Content="PUBG via Steam direkt starten" Foreground="@@TextPrimary@@" Margin="0,4" IsChecked="False"/>
                    </StackPanel>

                    <Grid Grid.Row="2" Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button x:Name="btnGMStart" Grid.Column="0" Content="🎯 START GAME MODE" Style="{StaticResource SuccessButton}" Height="44" FontSize="14" FontWeight="Bold" Margin="0,0,6,0"/>
                        <Button x:Name="btnGMExit" Grid.Column="1" Content="🛑 EXIT GAME MODE" Style="{StaticResource DangerButton}" Height="44" FontSize="14" FontWeight="Bold" Margin="6,0,0,0"/>
                    </Grid>

                    <Border Grid.Row="3" Background="@@Surface1@@" BorderBrush="@@BorderSubtle@@" BorderThickness="1" CornerRadius="4">
                        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="10">
                            <TextBlock x:Name="txtGMLog" Text="Log:&#x0a;" Foreground="@@TextPrimary@@" FontFamily="Consolas" FontSize="12"/>
                        </ScrollViewer>
                    </Border>
                </Grid>
            </TabItem>

            <!-- TAB 4: TWEAKS (Interaktiv) -->
            <TabItem Header="Tweaks">
                <Grid Margin="20">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <StackPanel Grid.Row="0" Orientation="Vertical" Margin="0,0,0,12">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                            <Button x:Name="btnApplySelected" Content="Apply Selected" Style="{StaticResource SuccessButton}" Width="160" Height="32" Margin="0,0,8,0"/>
                            <Button x:Name="btnApplyAll" Content="Apply All (auto-Status WARN/BAD)" Width="240" Height="32" Margin="0,0,8,0"/>
                            <Button x:Name="btnRefreshTweaks" Content="Refresh" Width="100" Height="32" Margin="0,0,8,0"/>
                            <Button x:Name="btnSelectAll" Content="Select All" Width="100" Height="32" Margin="0,0,8,0"/>
                            <Button x:Name="btnSelectNone" Content="Clear" Width="80" Height="32" Margin="0,0,8,0"/>
                            <Button x:Name="btnVerifyTimer" Content="Timer-Res. pruefen" Width="160" Height="32"/>
                        </StackPanel>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Filter:" Foreground="@@TextSecondary@@" FontSize="11" VerticalAlignment="Center" Margin="0,0,8,0"/>
                            <Button x:Name="btnFilterAll" Content="Alle" Width="80" Height="26" Margin="0,0,4,0"/>
                            <Button x:Name="btnFilterOpen" Content="Offen" Width="80" Height="26" Margin="0,0,4,0"/>
                            <Button x:Name="btnFilterDone" Content="Angewendet" Width="120" Height="26"/>
                        </StackPanel>
                    </StackPanel>
                    <TextBlock Grid.Row="1" x:Name="lblTweakInfo" Text="" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,4" TextWrapping="Wrap"/>
                    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
                        <StackPanel x:Name="tweakContainer"/>
                    </ScrollViewer>
                </Grid>
            </TabItem>

            <!-- TAB: GRAFIK (PUBG In-Game-Grafik, separat von Apply All) -->
            <TabItem Header="Grafik">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <!-- Profil-Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <Grid>
                                    <TextBlock Text="PUBG Esport-Grafik (Competitive-Profil)" Style="{StaticResource SectionHeader}"/>
                                    <Button x:Name="btnGfxRefresh" Content="Status pruefen" HorizontalAlignment="Right" Width="140" Margin="0,-4,0,0"/>
                                </Grid>
                                <TextBlock Foreground="@@TextSecondary@@" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,10">
                                    <Run Text="Schreibt PUBGs In-Game-Grafikmenue direkt in GameUserSettings.ini: Exklusiv-Vollbild, Sicht-Blocker niedrig, Spotting-Klarheit hoch. Alle Werte sind menue-konform (BattlEye-safe). Die Aufloesung wird NICHT veraendert."/>
                                    <LineBreak/>
                                    <Run Text="Bewusst getrennt von 'Apply All' - diese Einstellung ist zu wichtig fuer eine pauschale Anwendung."/>
                                </TextBlock>

                                <Border Background="@@BgBase@@" CornerRadius="3" Padding="10,8" Margin="0,0,0,4">
                                    <StackPanel>
                                        <TextBlock Text="Status" Foreground="@@TextSecondary@@" FontSize="10" FontWeight="SemiBold"/>
                                        <TextBlock x:Name="lblGfxStatus" Text="..." FontSize="13" FontWeight="Bold" Margin="0,2,0,0"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </Border>

                        <!-- Werte-Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Profil-Werte" Style="{StaticResource SectionHeader}"/>
                                <TextBlock x:Name="lblGfxValues" Foreground="@@TextPrimary@@" FontFamily="Consolas" FontSize="11" TextWrapping="Wrap" LineHeight="18"/>
                            </StackPanel>
                        </Border>

                        <!-- Einzel-Einstellungen-Card (granulare Dropdowns) -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="Einzel-Einstellungen" Style="{StaticResource SectionHeader}"/>
                                    <Border x:Name="gfxMatchBadge" Background="@@BorderStrong@@" CornerRadius="3" Padding="6,1" Margin="10,-2,0,8" VerticalAlignment="Center">
                                        <TextBlock x:Name="lblGfxMatchBadge" Text="Competitive-Match: -" Foreground="@@TextPrimary@@" FontSize="10" FontWeight="SemiBold"/>
                                    </Border>
                                </StackPanel>
                                <TextBlock Foreground="@@TextSecondary@@" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,10"
                                           Text="Jede Grafik-Option einzeln waehlen und mit 'Einzel-Werte anwenden' in GameUserSettings.ini schreiben. Die Dropdowns zeigen die aktuell gesetzten Werte. Das Statusfeld rechts zeigt, ob der Wert dem Competitive-Soll entspricht. Der Knopf 'Competitive-Profil anwenden' unten setzt jederzeit ALLES wieder auf das erarbeitete Esport-Profil zurueck."/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="170"/>
                                        <ColumnDefinition Width="230"/>
                                        <ColumnDefinition Width="90"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>
                                    <TextBlock Grid.Row="0" Grid.Column="0" Text="Anzeigemodus" Foreground="@@TextPrimary@@" FontSize="12" VerticalAlignment="Center" Margin="0,4"/>
                                    <TextBlock Grid.Row="0" Grid.Column="2" x:Name="lblIndFullscreen" Text="" FontSize="11" FontWeight="Bold" VerticalAlignment="Center" Margin="8,4,0,4"/>
                                    <ComboBox Grid.Row="0" Grid.Column="1" x:Name="cmbFullscreen" Margin="0,4">
                                        <ComboBoxItem Tag="0" Content="Exklusiv-Vollbild"/>
                                        <ComboBoxItem Tag="1" Content="Vollbild-Fenster"/>
                                        <ComboBoxItem Tag="2" Content="Fenster"/>
                                    </ComboBox>
                                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Anti-Aliasing" Foreground="@@TextPrimary@@" FontSize="12" VerticalAlignment="Center" Margin="0,4"/>
                                    <TextBlock Grid.Row="1" Grid.Column="2" x:Name="lblIndAA" Text="" FontSize="11" FontWeight="Bold" VerticalAlignment="Center" Margin="8,4,0,4"/>
                                    <ComboBox Grid.Row="1" Grid.Column="1" x:Name="cmbAA" Margin="0,4">
                                        <ComboBoxItem Tag="0" Content="Sehr Niedrig"/>
                                        <ComboBoxItem Tag="1" Content="Niedrig"/>
                                        <ComboBoxItem Tag="2" Content="Mittel"/>
                                        <ComboBoxItem Tag="3" Content="Hoch"/>
                                        <ComboBoxItem Tag="4" Content="Ultra"/>
                                    </ComboBox>
                                    <TextBlock Grid.Row="2" Grid.Column="0" Text="Texturen" Foreground="@@TextPrimary@@" FontSize="12" VerticalAlignment="Center" Margin="0,4"/>
                                    <TextBlock Grid.Row="2" Grid.Column="2" x:Name="lblIndTexture" Text="" FontSize="11" FontWeight="Bold" VerticalAlignment="Center" Margin="8,4,0,4"/>
                                    <ComboBox Grid.Row="2" Grid.Column="1" x:Name="cmbTexture" Margin="0,4">
                                        <ComboBoxItem Tag="0" Content="Sehr Niedrig"/>
                                        <ComboBoxItem Tag="1" Content="Niedrig"/>
                                        <ComboBoxItem Tag="2" Content="Mittel"/>
                                        <ComboBoxItem Tag="3" Content="Hoch"/>
                                        <ComboBoxItem Tag="4" Content="Ultra"/>
                                    </ComboBox>
                                    <TextBlock Grid.Row="3" Grid.Column="0" Text="Sichtweite" Foreground="@@TextPrimary@@" FontSize="12" VerticalAlignment="Center" Margin="0,4"/>
                                    <TextBlock Grid.Row="3" Grid.Column="2" x:Name="lblIndViewDist" Text="" FontSize="11" FontWeight="Bold" VerticalAlignment="Center" Margin="8,4,0,4"/>
                                    <ComboBox Grid.Row="3" Grid.Column="1" x:Name="cmbViewDist" Margin="0,4">
                                        <ComboBoxItem Tag="0" Content="Sehr Niedrig"/>
                                        <ComboBoxItem Tag="1" Content="Niedrig"/>
                                        <ComboBoxItem Tag="2" Content="Mittel"/>
                                        <ComboBoxItem Tag="3" Content="Hoch"/>
                                        <ComboBoxItem Tag="4" Content="Ultra"/>
                                    </ComboBox>
                                    <TextBlock Grid.Row="4" Grid.Column="0" Text="Schatten" Foreground="@@TextPrimary@@" FontSize="12" VerticalAlignment="Center" Margin="0,4"/>
                                    <TextBlock Grid.Row="4" Grid.Column="2" x:Name="lblIndShadow" Text="" FontSize="11" FontWeight="Bold" VerticalAlignment="Center" Margin="8,4,0,4"/>
                                    <ComboBox Grid.Row="4" Grid.Column="1" x:Name="cmbShadow" Margin="0,4">
                                        <ComboBoxItem Tag="0" Content="Sehr Niedrig"/>
                                        <ComboBoxItem Tag="1" Content="Niedrig"/>
                                        <ComboBoxItem Tag="2" Content="Mittel"/>
                                        <ComboBoxItem Tag="3" Content="Hoch"/>
                                        <ComboBoxItem Tag="4" Content="Ultra"/>
                                    </ComboBox>
                                    <TextBlock Grid.Row="5" Grid.Column="0" Text="Post-Processing" Foreground="@@TextPrimary@@" FontSize="12" VerticalAlignment="Center" Margin="0,4"/>
                                    <TextBlock Grid.Row="5" Grid.Column="2" x:Name="lblIndPost" Text="" FontSize="11" FontWeight="Bold" VerticalAlignment="Center" Margin="8,4,0,4"/>
                                    <ComboBox Grid.Row="5" Grid.Column="1" x:Name="cmbPost" Margin="0,4">
                                        <ComboBoxItem Tag="0" Content="Sehr Niedrig"/>
                                        <ComboBoxItem Tag="1" Content="Niedrig"/>
                                        <ComboBoxItem Tag="2" Content="Mittel"/>
                                        <ComboBoxItem Tag="3" Content="Hoch"/>
                                        <ComboBoxItem Tag="4" Content="Ultra"/>
                                    </ComboBox>
                                    <TextBlock Grid.Row="6" Grid.Column="0" Text="Effekte" Foreground="@@TextPrimary@@" FontSize="12" VerticalAlignment="Center" Margin="0,4"/>
                                    <TextBlock Grid.Row="6" Grid.Column="2" x:Name="lblIndEffects" Text="" FontSize="11" FontWeight="Bold" VerticalAlignment="Center" Margin="8,4,0,4"/>
                                    <ComboBox Grid.Row="6" Grid.Column="1" x:Name="cmbEffects" Margin="0,4">
                                        <ComboBoxItem Tag="0" Content="Sehr Niedrig"/>
                                        <ComboBoxItem Tag="1" Content="Niedrig"/>
                                        <ComboBoxItem Tag="2" Content="Mittel"/>
                                        <ComboBoxItem Tag="3" Content="Hoch"/>
                                        <ComboBoxItem Tag="4" Content="Ultra"/>
                                    </ComboBox>
                                    <TextBlock Grid.Row="7" Grid.Column="0" Text="Laub" Foreground="@@TextPrimary@@" FontSize="12" VerticalAlignment="Center" Margin="0,4"/>
                                    <TextBlock Grid.Row="7" Grid.Column="2" x:Name="lblIndFoliage" Text="" FontSize="11" FontWeight="Bold" VerticalAlignment="Center" Margin="8,4,0,4"/>
                                    <ComboBox Grid.Row="7" Grid.Column="1" x:Name="cmbFoliage" Margin="0,4">
                                        <ComboBoxItem Tag="0" Content="Sehr Niedrig"/>
                                        <ComboBoxItem Tag="1" Content="Niedrig"/>
                                        <ComboBoxItem Tag="2" Content="Mittel"/>
                                        <ComboBoxItem Tag="3" Content="Hoch"/>
                                        <ComboBoxItem Tag="4" Content="Ultra"/>
                                    </ComboBox>
                                </Grid>
                                <Button x:Name="btnGfxApplyCustom" Content="Einzel-Werte anwenden" Style="{StaticResource SuccessButton}" Width="220" Height="34" HorizontalAlignment="Left" Margin="0,14,0,0"/>
                                <TextBlock x:Name="lblGfxCustomInfo" Text="" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,8,0,0" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>

                        <!-- Aktions-Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Anwenden / Zuruecksetzen" Style="{StaticResource SectionHeader}"/>
                                <Border Background="@@WarnBg@@" BorderBrush="@@StatusWarn@@" BorderThickness="0,0,0,2" CornerRadius="3" Padding="10,8" Margin="0,0,0,12">
                                    <TextBlock Foreground="@@StatusWarn@@" FontSize="11" TextWrapping="Wrap"
                                               Text="WICHTIG: PUBG muss beim Anwenden komplett geschlossen sein - sonst ueberschreibt es die Datei beim Beenden. Vor jeder Aenderung wird ein Backup erstellt."/>
                                </Border>
                                <StackPanel Orientation="Horizontal">
                                    <Button x:Name="btnGfxApply" Content="Competitive-Profil anwenden" Style="{StaticResource SuccessButton}" Width="240" Height="36" Margin="0,0,8,0"/>
                                    <Button x:Name="btnGfxRevert" Content="Zuruecksetzen (Backup)" Style="{StaticResource DangerButton}" Width="200" Height="36"/>
                                </StackPanel>
                                <TextBlock x:Name="lblGfxInfo" Text="" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,10,0,0" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 5: SETTINGS -->
            <TabItem Header="Settings">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <!-- System Info Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Erkanntes System" Style="{StaticResource SectionHeader}"/>
                                <TextBlock x:Name="lblDetectedHw" Foreground="@@TextPrimary@@" FontFamily="Consolas" FontSize="11" TextWrapping="Wrap" LineHeight="18"/>
                            </StackPanel>
                        </Border>

                        <!-- Monitor Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <Grid>
                                    <TextBlock Text="Monitor-Setup" Style="{StaticResource SectionHeader}"/>
                                    <Button x:Name="btnDetectMonitors" Content="Erneut scannen" HorizontalAlignment="Right" Width="140" Margin="0,-4,0,0"/>
                                </Grid>
                                <TextBlock Text="Erkannte Displays:" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,4,0,4"/>
                                <StackPanel x:Name="monitorList"/>

                                <TextBlock Text="Monitor-Pattern (Game-Mode)" Foreground="@@TextPrimary@@" FontWeight="SemiBold" FontSize="12" Margin="0,18,0,4"/>
                                <TextBlock Foreground="@@TextSecondary@@" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8">
                                    <Run Text="Regex - matcht Monitor-Namen die im Game Mode deaktiviert werden."/>
                                    <LineBreak/>
                                    <Run Text="Tipp: 'Detect &amp; Fill' generiert den Pattern automatisch aus deinen Sekundaer-Monitoren."/>
                                </TextBlock>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="140"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="tbMonitorPattern" Grid.Column="0" Background="@@BgBase@@" Foreground="@@TextPrimary@@" BorderBrush="@@BorderSubtle@@" Padding="8,6" FontFamily="Consolas" VerticalContentAlignment="Center"/>
                                    <Button x:Name="btnAutoPattern" Grid.Column="1" Content="Detect &amp; Fill" Margin="8,0,0,0"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <!-- VRR / OLED-Empfehlungen Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Monitor-OSD &amp; VRR (OLED) - Empfehlungen" Style="{StaticResource SectionHeader}"/>
                                <TextBlock Foreground="@@TextSecondary@@" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8"
                                           Text="Diese Einstellungen kann die Suite NICHT setzen - sie liegen im Monitor-OSD bzw. der NVIDIA-Systemsteuerung. Ziel: tearing-frei + minimale Latenz + kein OLED-Flicker."/>
                                <TextBlock Foreground="@@TextPrimary@@" FontSize="11" TextWrapping="Wrap" LineHeight="18">
                                    <Run Text="Monitor-OSD:" FontWeight="Bold" Foreground="@@Accent@@"/><LineBreak/>
                                    <Run Text="  - VRR / Adaptive-Sync: EIN  (zwingend fuer G-Sync)"/><LineBreak/>
                                    <Run Text="  - OLED Anti-Flicker: OFF  - NICHT Middle/High: die kappen die VRR-Range (80- bzw. 140-240 Hz); fallen die FPS darunter, gibt es Tearing/Stutter. 'Off' = volle 48-240 Hz + LFC."/><LineBreak/>
                                    <Run Text="  - Uniform Brightness: EIN  - konstante Helligkeit, kein ABL-Pumpen"/><LineBreak/>
                                    <Run Text="  - HDR: AUS (SDR) fuer Competitive - HDR verstaerkt VRR-Flicker"/><LineBreak/>
                                    <Run Text="NVIDIA-Systemsteuerung:" FontWeight="Bold" Foreground="@@Accent@@"/><LineBreak/>
                                    <Run Text="  - 'G-SYNC einrichten': aktivieren, fuer Vollbildmodus + Haekchen 'Einstellungen fuer das ausgewaehlte Anzeigemodell aktivieren'"/><LineBreak/>
                                    <Run Text="  - NVIDIA Smooth Motion (RTX 50): AUS - Frame-Gen kostet Latenz"/><LineBreak/>
                                    <Run Text="  - V-Sync = Ein, FPS-Cap, Low Latency = Aus  (setzt der 'NVIDIA PUBG-Profil'-Tweak bereits)"/><LineBreak/>
                                    <Run Text="In PUBG:" FontWeight="Bold" Foreground="@@Accent@@"/><LineBreak/>
                                    <Run Text="  - Exklusiv-Vollbild, In-Game-V-Sync AUS, FPS-Cap Display-Based"/>
                                </TextBlock>
                            </StackPanel>
                        </Border>

                        <!-- Tools Pfade Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Pfade (Tools &amp; State)" Style="{StaticResource SectionHeader}"/>
                                <TextBlock x:Name="lblPaths" Foreground="@@TextPrimary@@" FontFamily="Consolas" FontSize="10" TextWrapping="Wrap" LineHeight="16"/>
                            </StackPanel>
                        </Border>

                        <!-- Storage & Logs Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Storage / Logs / Backups" Style="{StaticResource SectionHeader}"/>
                                <TextBlock Foreground="@@TextSecondary@@" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8">
                                    <Run Text="Alle Apply/Revert-Aktionen werden geloggt. Snapshots erlauben Revert via Tweak-Button."/>
                                </TextBlock>
                                <StackPanel Orientation="Horizontal">
                                    <Button x:Name="btnOpenLogs" Content="Logs oeffnen" Width="140" Margin="0,0,8,0"/>
                                    <Button x:Name="btnOpenBackups" Content="Backups oeffnen" Width="160" Margin="0,0,8,0"/>
                                    <Button x:Name="btnClearHistory" Content="History loeschen" Width="160" Style="{StaticResource DangerButton}"/>
                                </StackPanel>
                                <TextBlock x:Name="lblHistoryStat" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,8,0,0"/>
                            </StackPanel>
                        </Border>

                        <!-- Backup-Manager Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <Grid>
                                    <TextBlock Text="Backup-Manager" Style="{StaticResource SectionHeader}"/>
                                    <Button x:Name="btnRefreshBackups" Content="Aktualisieren" HorizontalAlignment="Right" Width="140" Margin="0,-4,0,0"/>
                                </Grid>
                                <TextBlock Foreground="@@TextSecondary@@" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8">
                                    <Run Text="Jeder Grafik-/INI-Apply sichert die Originaldatei vorher. Hier laesst sich ein beliebiges Backup wiederherstellen - der aktuelle Stand der Zieldatei wird davor selbst gesichert."/>
                                </TextBlock>
                                <TextBlock x:Name="lblBackupInfo" Foreground="@@TextSecondary@@" FontSize="11" Margin="0,0,0,8"/>
                                <StackPanel x:Name="backupList"/>
                            </StackPanel>
                        </Border>

                        <!-- About Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="About" Style="{StaticResource SectionHeader}"/>
                                <TextBlock Foreground="@@TextPrimary@@" TextWrapping="Wrap" LineHeight="20">
                                    <Run Text="PUBG Performance Suite" FontWeight="SemiBold"/>
                                    <Run x:Name="lblAboutVersion" Text=""/>
                                    <LineBreak/><LineBreak/>
                                    <Run Text="Open Source PowerShell-WPF Tool fuer PUBG-Competitive-Tuning. BattlEye-safe, vollstaendig reversibel, keine externen Dependencies ausser auto-installierten Open-Source-Helpern (PresentMon, MultiMonitorTool, NPI)." Foreground="@@TextSecondary@@"/>
                                    <LineBreak/><LineBreak/>
                                    <Run Text="Repo:" FontWeight="SemiBold" Foreground="@@Accent@@"/>
                                    <Run Text="  github.com/Sotrax/pubg-performance-suite"/>
                                    <LineBreak/>
                                    <Run Text="Update:" FontWeight="SemiBold" Foreground="@@Accent@@"/>
                                    <Run Text='  irm "https://raw.githubusercontent.com/Sotrax/pubg-performance-suite/main/launch.ps1" | iex'/>
                                    <LineBreak/><LineBreak/>
                                    <Run Text="Auto-Detection:" FontWeight="SemiBold" Foreground="@@Accent@@"/>
                                    <Run Text="  Monitor-Hz, PUBG-Steam-Pfad, dedizierte GPU, Energieplan, NPI-Apply-Stamp"/>
                                    <LineBreak/>
                                    <Run Text="Backups:" FontWeight="SemiBold" Foreground="@@Accent@@"/>
                                    <Run Text="  Tweaks legen .bak_&lt;timestamp&gt; neben das Original an, Registry-Snapshots in history.json"/>
                                    <LineBreak/>
                                    <Run Text="Reversibel:" FontWeight="SemiBold" Foreground="@@Accent@@"/>
                                    <Run Text="  15 von 16 Tweaks per Klick rueckgaengig (NV-Profil nutzt NPI-eigene Reset-Funktion)"/>
                                    <LineBreak/>
                                    <Run Text="BattlEye-safe:" FontWeight="SemiBold" Foreground="@@Accent@@"/>
                                    <Run Text="  Kein Special K, kein ReShade, kein DXVK, keine ban-bait Engine.ini CVars, kein Process-Lasso auf BEService"/>
                                </TextBlock>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB: KEY GEN (Retro-Spass-Tab, bewusster Bruch zum cleanen Rest) -->
            <TabItem Header="Key Gen">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <!-- ASCII-Art-Header -->
                        <Border Background="@@BgBase@@" CornerRadius="4" Padding="14,12" Margin="0,0,0,12">
                            <TextBlock x:Name="lblKeygenArt" FontFamily="Consolas" FontSize="13" Foreground="@@StatusBest@@" TextAlignment="Center"/>
                        </Border>

                        <!-- Keygen-Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="PUBG SUITE PRO  -  LIZENZSCHLUESSEL-GENERATOR" Style="{StaticResource SectionHeader}"/>

                                <Border Background="@@BgBase@@" CornerRadius="4" Padding="16,20" Margin="0,4,0,14">
                                    <StackPanel>
                                        <TextBlock Text="- - - -   D E I N   L I Z E N Z S C H L U E S S E L   - - - -" Foreground="@@TextDisabled@@" FontSize="10" FontWeight="SemiBold" TextAlignment="Center"/>
                                        <TextBlock x:Name="lblKeygenCode" Text="XXXXXX-XXXXXX-XXXXXX-XXXXXX" FontFamily="Consolas" FontSize="26" FontWeight="Bold" Foreground="@@Accent@@" TextAlignment="Center" Margin="0,10,0,2"/>
                                        <TextBlock x:Name="lblKeygenStatus" Text="BEREIT  -  KLICK GENERATE" FontFamily="Consolas" Foreground="@@TextSecondary@@" FontSize="11" TextAlignment="Center" Margin="0,10,0,0"/>
                                    </StackPanel>
                                </Border>

                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                                    <Button x:Name="btnKeygenGenerate" Content="*  GENERATE  *" Style="{StaticResource SuccessButton}" Width="260" Height="46" FontWeight="Bold" Margin="0,0,10,0"/>
                                    <Button x:Name="btnKeygenMusic" Content="MUSIK: AUS" Width="160" Height="46"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <!-- Greetz-Scroller -->
                        <Border Background="@@BgBase@@" CornerRadius="4" Padding="10,6" ClipToBounds="True">
                            <TextBlock x:Name="lblKeygenGreetz" FontFamily="Consolas" FontSize="12" Foreground="@@StatusOK@@"/>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- Footer -->
        <Border Grid.Row="2" Background="@@Surface1@@" BorderBrush="@@BorderSubtle@@" BorderThickness="0,1,0,0" Padding="20,8">
            <TextBlock x:Name="lblFooter" Text="Bereit." Foreground="@@TextDisabled@@" FontSize="11"/>
        </Border>
    </Grid>
</Window>
'@

# Farb-Token aufloesen: @@Name@@ -> Hex-Wert aus $Global:SuiteColors.
# Damit ist die Palette die einzige Quelle - XAML und Code teilen sie.
$xamlText = $xamlTemplate
foreach ($k in $Global:SuiteColors.Keys) {
    $xamlText = $xamlText.Replace("@@$k@@", $Global:SuiteColors[$k])
}
$leftoverToken = [regex]::Match($xamlText, '@@\w+@@')
if ($leftoverToken.Success) {
    throw "XAML-Build: unaufgeloestes Farb-Token '$($leftoverToken.Value)' - fehlt in `$Global:SuiteColors"
}
[xml]$xaml = $xamlText

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Control-Refs
$ctrls = @{}
foreach ($name in @('mainTabs','lblVersion','updateBadge','lblUpdate','lblAdmin','adminBadge','lblTopStatus','btnRefresh','statusItems','lblStatusSubtitle','recoList','recoEmptyState','btnStartGameMode','btnExitGameMode',
    'btnApplySelected','btnApplyAll','btnRefreshTweaks','btnSelectAll','btnSelectNone','btnVerifyTimer','lblTweakInfo','tweakContainer',
    'btnFilterAll','btnFilterOpen','btnFilterDone',
    'lblGfxStatus','lblGfxValues','lblGfxInfo','btnGfxApply','btnGfxRevert','btnGfxRefresh',
    'cmbFullscreen','cmbAA','cmbTexture','cmbViewDist','cmbShadow','cmbPost','cmbEffects','cmbFoliage','btnGfxApplyCustom','lblGfxCustomInfo',
    'lblIndFullscreen','lblIndAA','lblIndTexture','lblIndViewDist','lblIndShadow','lblIndPost','lblIndEffects','lblIndFoliage','lblGfxMatchBadge','gfxMatchBadge',
    'lblDetectedHw','monitorList','btnDetectMonitors','btnAutoPattern',
    'btnOpenLogs','btnOpenBackups','btnClearHistory','lblHistoryStat',
    'btnRefreshBackups','lblBackupInfo','backupList',
    'lblCapToolStatus','btnCapStart','btnCapStop','lblCapPhase',
    'lblCapLastInfo','capResultGrid','lblCapAvg','lblCap1Low','lblCap01Low','lblCapStdDev','lblCapStability',
    'lblCapBottleneck','lblCapCpuBusy','lblCapGpuBusy','lblCapRenderLat',
    'lblCapUntilDisp','lblCapClickPhoton','lblCapGSync','lblCapStutter',
    'lblCapPresentMode','lblCapPresentExplain',
    'btnCapOpenCsv','btnCapOpenFolder','btnCapCompare','btnCapRebuild','btnCapClearHist','lblCapHistInfo','capHistoryList',
    'capCompareCard','btnCapCompareClose','lblCapCompareInfo','capCompareList',
    'btnRunDiag','btnOpenHTML','btnOpenReports','txtDiagOutput',
    'cbMonitors','cbRTSS','cbBackground','cbLaunch','btnGMStart','btnGMExit','txtGMLog',
    'lblPaths','tbMonitorPattern','lblFooter','lblAboutVersion',
    'lblKeygenArt','lblKeygenCode','lblKeygenStatus','btnKeygenGenerate','btnKeygenMusic','lblKeygenGreetz')) {
    $ctrls[$name] = $window.FindName($name)
}

# ==================== UI HELPERS ====================
$colorByStatus = @{
    'OK'   = @{ Border=$Global:SuiteColors.StatusOK; Text=$Global:SuiteColors.StatusOK }
    'WARN' = @{ Border=$Global:SuiteColors.StatusWarn; Text=$Global:SuiteColors.StatusWarn }
    'BAD'  = @{ Border=$Global:SuiteColors.StatusError; Text=$Global:SuiteColors.StatusError }
    'INFO' = @{ Border=$Global:SuiteColors.Accent; Text=$Global:SuiteColors.TextPrimary }
    'SKIP' = @{ Border=$Global:SuiteColors.TextSecondary; Text=$Global:SuiteColors.TextSecondary }
}

function Update-StatusGrid {
    $live = Get-LiveStatus
    $items = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($k in $live.Keys) {
        $v = $live[$k]
        $col = $colorByStatus[$v.Status]
        $items.Add([pscustomobject]@{
            Label = $k.ToUpper()
            Value = $v.Value
            BorderColor = $col.Border
            TextColor = $col.Text
        })
    }
    $ctrls.statusItems.ItemsSource = $items

    # Recommendation-Engine: pro Befund eine visuelle Card mit Severity + Tab-Sprung
    # Tab-Index: 0=Dashboard, 1=Tweaks, 2=Game Mode, 3=Capture, 4=Diagnose, 5=Settings (nach Reorder)
    $recos = @()
    if ($live['HVCI'].Status -eq 'BAD')         { $recos += @{ Sev='BAD';  Title='HVCI / Credential Guard ist AN'; Detail='Memory Integrity bzw. CredGuard laeuft - kostet 5-10% FPS in CPU-bound Games (Toms Hardware). Tweak: "Virtualization Security (VBS + HVCI): AUS"'; TabIdx=1 } }
    if ($live['HVCI'].Status -eq 'WARN')        { $recos += @{ Sev='WARN'; Title='Hypervisor-Stack laeuft noch'; Detail='HVCI + CredGuard sind aus (Suite-Tweak hat funktioniert!), aber Win11 24H2 startet den Hypervisor trotzdem (~1-3% SLAT-Overhead). Vollstaendig aus nur via UEFI/BIOS-Setting "Virtualization-based Security" deaktivieren ODER UEFI Secure Boot pruefen. Optional - kostet wenig'; TabIdx=0 } }
    if ($live['Energieplan'].Status -ne 'OK')  { $recos += @{ Sev='WARN'; Title='Energieplan nicht Maximum'; Detail='Auf Hoechstleistung wechseln - haelt CPU-Frequenz auf Vollgas'; TabIdx=1 } }
    if ($live['GameDVR'].Status -ne 'OK')      { $recos += @{ Sev='BAD';  Title='Xbox Game DVR ist AN'; Detail='Game Bar Recording laeuft im Hintergrund mit. Tweak: "Game DVR AUS"'; TabIdx=1 } }
    if ($live['RTSS'].Status -ne 'OK')         { $recos += @{ Sev='WARN'; Title='RTSS laeuft'; Detail='Erzwingt Present-Mode 5 (Composed Copy, ~3-5ms Overhead). Game-Mode-Start killt es automatisch'; TabIdx=2 } }
    if ($live['Monitore'].Status -ne 'OK')     { $recos += @{ Sev='WARN'; Title='Multi-Monitor aktiv'; Detail='Verhindert Hardware Independent Flip. Game Mode deaktiviert Sekundaer-Monitore'; TabIdx=2 } }
    if ($live['Engine.ini'].Status -ne 'OK')   { $recos += @{ Sev='WARN'; Title='Engine.ini Tweaks fehlen'; Detail='Sharpen + Streaming + Pacing nicht gesetzt. Tweak: "Engine.ini Tweaks"'; TabIdx=1 } }
    if ($live['NV Profil'].Status -ne 'OK')    { $recos += @{ Sev='WARN'; Title='NVIDIA Profile nicht applied'; Detail='Reflex + Power Mgmt + Threaded Optim. nicht via NPI gesetzt. Tweak: "NVIDIA Profile"'; TabIdx=1 } }
    if ($live['Defender'].Status -eq 'WARN')   { $recos += @{ Sev='WARN'; Title='Defender ohne PUBG-Exclusion'; Detail='Realtime-Scan auf PUBG-Files kostet I/O. Tweak: "Defender Exclusion"'; TabIdx=1 } }
    if ($live['FPS-Cap'] -and $live['FPS-Cap'].Status -eq 'WARN') { $recos += @{ Sev='WARN'; Title='FPS-Cap nicht vollstaendig'; Detail='In-Game-Cap auf Display-Based (Monitor-Hz) setzen UND das NVIDIA-Profil anwenden - der scharfe Cap (Hz-3) laeuft ueber den Treiber-Limiter. Tweaks: "PUBG In-Game FPS-Cap" + "NVIDIA PUBG-Profil"'; TabIdx=1 } }
    if ($live['G-Sync'] -and $live['G-Sync'].Status -eq 'WARN') { $recos += @{ Sev='WARN'; Title='G-Sync nicht aktiviert'; Detail='G-Sync/VRR ist die Voraussetzung fuer tearing-freies Spielen ohne V-Sync-Latenz. Tweak: "G-Sync aktivieren" - danach im Monitor-OSD VRR/Adaptive-Sync einschalten.'; TabIdx=1 } }
    if ($live['GPU-Treiber'] -and $live['GPU-Treiber'].Status -eq 'WARN') { $recos += @{ Sev='WARN'; Title='GPU-Treiber aelter als 90 Tage'; Detail='Aktuellen NVIDIA-Treiber via NVIDIA App installieren - neuere Treiber bringen oft Game-Ready-Optimierungen und VRR-/Flip-Fixes. (Manuell - die Suite aktualisiert keine Treiber.)'; TabIdx=0 } }

    $ctrls.recoList.Children.Clear()
    if ($recos.Count -eq 0) {
        $ctrls.recoEmptyState.Visibility = 'Visible'
    } else {
        $ctrls.recoEmptyState.Visibility = 'Collapsed'
        foreach ($r in $recos) {
            $border = New-Object System.Windows.Controls.Border
            $border.Background = $Global:SuiteColors.Surface1
            $border.BorderBrush = if ($r.Sev -eq 'BAD') { $Global:SuiteColors.StatusError } else { $Global:SuiteColors.StatusWarn }
            $border.BorderThickness = New-Object System.Windows.Thickness 0,0,0,2
            $border.CornerRadius = New-Object System.Windows.CornerRadius 3
            $border.Padding = New-Object System.Windows.Thickness 12,8,12,8
            $border.Margin = New-Object System.Windows.Thickness 0,0,0,4

            $grid = New-Object System.Windows.Controls.Grid
            $border.Child = $grid
            $colMain = New-Object System.Windows.Controls.ColumnDefinition; $colMain.Width = '*'; $grid.ColumnDefinitions.Add($colMain) | Out-Null
            $colBtn  = New-Object System.Windows.Controls.ColumnDefinition; $colBtn.Width  = 'Auto'; $grid.ColumnDefinitions.Add($colBtn)  | Out-Null

            $sp = New-Object System.Windows.Controls.StackPanel
            [System.Windows.Controls.Grid]::SetColumn($sp, 0)
            $grid.Children.Add($sp) | Out-Null

            $sevIcon = if ($r.Sev -eq 'BAD') { '⚠' } else { '!' }
            $sevColor = if ($r.Sev -eq 'BAD') { $Global:SuiteColors.StatusError } else { $Global:SuiteColors.StatusWarn }

            $titleSp = New-Object System.Windows.Controls.StackPanel
            $titleSp.Orientation = 'Horizontal'
            $tbIcon = New-Object System.Windows.Controls.TextBlock
            $tbIcon.Text = $sevIcon; $tbIcon.Foreground = $sevColor; $tbIcon.FontWeight = 'Bold'; $tbIcon.FontSize = 13
            $tbIcon.Margin = New-Object System.Windows.Thickness 0,0,6,0
            $titleSp.Children.Add($tbIcon) | Out-Null
            $tbTitle = New-Object System.Windows.Controls.TextBlock
            $tbTitle.Text = $r.Title; $tbTitle.Foreground = $Global:SuiteColors.TextPrimary; $tbTitle.FontWeight = 'SemiBold'; $tbTitle.FontSize = 12
            $titleSp.Children.Add($tbTitle) | Out-Null
            $sp.Children.Add($titleSp) | Out-Null

            $tbDetail = New-Object System.Windows.Controls.TextBlock
            $tbDetail.Text = $r.Detail; $tbDetail.Foreground = $Global:SuiteColors.TextSecondary; $tbDetail.FontSize = 11
            $tbDetail.TextWrapping = 'Wrap'; $tbDetail.Margin = New-Object System.Windows.Thickness 18,2,0,0
            $sp.Children.Add($tbDetail) | Out-Null

            $btnGo = New-Object System.Windows.Controls.Button
            $btnGo.Content = 'Fix ->'
            $btnGo.Width = 70; $btnGo.Height = 26; $btnGo.VerticalAlignment = 'Center'
            $btnGo.Tag = $r.TabIdx
            [System.Windows.Controls.Grid]::SetColumn($btnGo, 1)
            $btnGo.Add_Click({
                $targetIdx = [int]$this.Tag
                if ($ctrls.mainTabs.Items.Count -gt $targetIdx) {
                    $ctrls.mainTabs.SelectedIndex = $targetIdx
                }
            })
            $grid.Children.Add($btnGo) | Out-Null

            $ctrls.recoList.Children.Add($border) | Out-Null
        }
    }

    # Top-Status: nur Tweak-relevante Checks zaehlen, nicht INFO (PUBG/GPU/CPU/Display)
    $tweakKeys = @('HVCI','Energieplan','GameDVR','Monitore','RTSS','Engine.ini','NV Profil','Defender','FPS-Cap','G-Sync')
    $okCount = 0; $totalCount = 0
    foreach ($k in $tweakKeys) {
        if ($live[$k]) {
            $totalCount++
            if ($live[$k].Status -eq 'OK') { $okCount++ }
        }
    }
    $ctrls.lblTopStatus.Text = "$okCount / $totalCount OK"
    if ($ctrls.lblStatusSubtitle) {
        $ctrls.lblStatusSubtitle.Text = "Letzte Aktualisierung: $(Get-Date -Format 'HH:mm:ss')"
    }

    # Footer: erweiterte Info-Zeile
    $lastApply = ''
    try {
        $hist = @(Get-HistoryEntries)
        $lastApplyEntry = $hist | Where-Object { $_.Action -eq 'Apply' -and $_.Success } | Select-Object -Last 1
        if ($lastApplyEntry -and $lastApplyEntry.Time) {
            try {
                $dt = [datetime]::Parse($lastApplyEntry.Time)
                $lastApply = "Letzter Apply: $($lastApplyEntry.TweakId) ($($dt.ToString('HH:mm')))"
            } catch { $lastApply = "Letzter Apply: $($lastApplyEntry.TweakId)" }
        }
    } catch {}  # Footer-Info ist rein kosmetisch - History-Lesefehler hier ignorieren
    $footerParts = @("Status: $(Get-Date -Format 'HH:mm:ss')")
    if ($lastApply) { $footerParts += $lastApply }
    $ctrls.lblFooter.Text = ($footerParts -join '   |   ')
}

function Write-GMLog {
    param([string]$Msg, [string]$Level = 'INFO')
    $color = switch ($Level) {
        'OK'   { $Global:SuiteColors.StatusOK }
        'WARN' { $Global:SuiteColors.StatusWarn }
        'BAD'  { $Global:SuiteColors.StatusError }
        default { $Global:SuiteColors.TextPrimary }
    }
    $ts = Get-Date -Format 'HH:mm:ss'
    $line = "[$ts] $Msg`n"
    $ctrls.txtGMLog.Text += $line
    # Auto-scroll (best effort)
    $ctrls.txtGMLog.Parent.ScrollToEnd()
}

function Write-DiagLog {
    param([string]$Msg)
    $ts = Get-Date -Format 'HH:mm:ss'
    $ctrls.txtDiagOutput.Text += "[$ts] $Msg`n"
    $ctrls.txtDiagOutput.Parent.ScrollToEnd()
}

# ==================== EVENT HANDLERS ====================
$ctrls.btnRefresh.Add_Click({ Update-StatusGrid })

$ctrls.btnStartGameMode.Add_Click({
    # Dashboard-Button -> Tab 3 wechseln, dann startet User dort
    ($window.FindName('btnGMStart')).RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Button]::ClickEvent)))
})
$ctrls.btnExitGameMode.Add_Click({
    ($window.FindName('btnGMExit')).RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Button]::ClickEvent)))
})

$ctrls.btnGMStart.Add_Click({
    $cb = { param($m, $l='INFO') Write-GMLog -Msg $m -Level $l }
    Start-GameMode -DisableMonitors $ctrls.cbMonitors.IsChecked -KillRTSS $ctrls.cbRTSS.IsChecked `
                   -KillBackground $ctrls.cbBackground.IsChecked `
                   -LaunchPUBG $ctrls.cbLaunch.IsChecked -LogCallback $cb
    Update-StatusGrid
})

$ctrls.btnGMExit.Add_Click({
    $cb = { param($m, $l='INFO') Write-GMLog -Msg $m -Level $l }
    Stop-GameMode -LogCallback $cb
    Update-StatusGrid
})

$ctrls.btnRunDiag.Add_Click({
    $diag = $Global:Suite.DiagScript
    if (-not (Test-Path $diag)) {
        Write-DiagLog "FEHLER: $diag nicht gefunden"
        Write-DiagLog "Das Script gehoert zur Suite und sollte automatisch dabei sein."
        Write-DiagLog "Fix: 'irm \"https://raw.githubusercontent.com/Sotrax/pubg-performance-suite/main/launch.ps1\" | iex' erneut ausfuehren - der Bootstrap holt das komplette Repo (inkl. diagnose\\-Ordner) neu."
        return
    }
    Write-DiagLog "Starte v6-Diagnose in separatem Fenster (NonInteractive Mode)..."
    Write-DiagLog "Interaktive Fix-Phase wird uebersprungen - Tweaks werden im Tab 'Tweaks' verwaltet"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$diag`" -NonInteractive"
    Write-DiagLog "Fenster sollte aufgegangen sein. Nach Abschluss: 'Open Last Report' klicken."
})

$ctrls.btnOpenHTML.Add_Click({
    $reports = Get-ChildItem "$env:USERPROFILE\Desktop" -Filter 'PUBGSystemReport_*.html' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($reports) {
        Start-Process $reports[0].FullName
        Write-DiagLog "Geoeffnet: $($reports[0].Name)"
    } else {
        Write-DiagLog "Kein Report gefunden. Erst 'Run Full Diagnose' klicken."
    }
})

$ctrls.btnOpenReports.Add_Click({
    Start-Process explorer.exe -ArgumentList "$env:USERPROFILE\Desktop"
})

# ==================== SETTINGS-TAB ====================
function Get-DedicatedGPU {
    # Bevorzugt dGPU vor iGPU (z.B. AMD Radeon iGPU bei 7950X3D wuerde sonst gefunden)
    $allGpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    $dGpu = $allGpus | Where-Object {
        $_.Name -match 'NVIDIA|GeForce|RTX|GTX|Quadro|Radeon RX|Radeon Pro' -and
        $_.Name -notmatch 'Vega.*Graphics|Radeon.*Graphics$|UHD Graphics|Iris|HD Graphics'
    } | Select-Object -First 1
    if (-not $dGpu) {
        # Fallback: groesste GPU nach VRAM
        $dGpu = $allGpus | Sort-Object -Property AdapterRAM -Descending | Select-Object -First 1
    }
    return $dGpu
}

function Update-DetectedHardware {
    $cpu = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name
    $hz = Get-PrimaryMonitorHz
    $cap = Get-OptimalFpsCap
    $ram = [math]::Round(((Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object Capacity -Sum).Sum / 1GB), 0)
    $dGpu = Get-DedicatedGPU
    $gpuName = if ($dGpu) { $dGpu.Name } else { '(nicht erkannt)' }

    # GPU-VRAM via nvidia-smi (genauer als Win32 int32-Overflow)
    $vramTxt = ''
    if ($dGpu -and ($dGpu.Name -match 'NVIDIA|GeForce|RTX|GTX')) {
        $nvSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
        if ($nvSmi) {
            try {
                $out = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1
                if ($out) { $vramTxt = "  ($([math]::Round([int]$out.Trim() / 1024, 1)) GB VRAM)" }
            } catch {}  # nvidia-smi optional -> AdapterRAM-Fallback unten greift
        }
    }
    if (-not $vramTxt -and $dGpu -and $dGpu.AdapterRAM) {
        $vramTxt = "  ($([math]::Round($dGpu.AdapterRAM / 1GB, 1)) GB VRAM)"
    }

    # GPU-Treiber: Version (nvidia-smi) + Datum (Win32) fuer eine Alters-Anzeige
    $drvTxt = '?'
    try {
        $drvVer = $null
        if ($dGpu -and ($dGpu.Name -match 'NVIDIA|GeForce|RTX|GTX')) {
            $nvSmi2 = Get-Command nvidia-smi -ErrorAction SilentlyContinue
            if ($nvSmi2) {
                try { $drvVer = (& nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>$null | Select-Object -First 1) } catch {}
                if ($drvVer) { $drvVer = $drvVer.Trim() }
            }
        }
        if (-not $drvVer -and $dGpu -and $dGpu.DriverVersion) { $drvVer = $dGpu.DriverVersion }
        if ($drvVer) {
            $drvTxt = $drvVer
            if ($dGpu -and $dGpu.DriverDate) {
                try {
                    $dd = [Management.ManagementDateTimeConverter]::ToDateTime($dGpu.DriverDate)
                    $drvTxt += "  (vom $($dd.ToString('yyyy-MM-dd')), $([int]((Get-Date) - $dd).TotalDays) Tage alt)"
                } catch {}
            }
        }
    } catch {}

    $ctrls.lblDetectedHw.Text = @"
CPU:             $cpu
GPU:             $gpuName$vramTxt
GPU-Treiber:     $drvTxt
RAM:             $ram GB
Monitor (Hz):    $hz Hz  (In-Game-Cap: $hz / NVIDIA-Treiber-Cap: $cap)
Aktive Displays: $([System.Windows.Forms.Screen]::AllScreens.Count) (vom DWM genutzt)
"@
}

# EDID-Hersteller-Codes (PNP Vendor IDs) -> Klartext. Wenn ein Monitor keinen
# UserFriendlyName liefert (haeufig bei OLEDs ueber DisplayPort), kommt nur der
# rohe Code wie 'AUS27F5' - die ersten 3 Zeichen sind die Hersteller-ID.
$Global:EdidVendors = @{
    AUS='ASUS'; ASU='ASUS'; ACI='Acer'; ACR='Acer'; SAM='Samsung'; SDC='Samsung'
    GSM='LG'; LGD='LG Display'; DEL='Dell'; BNQ='BenQ'; AOC='AOC'; MSI='MSI'
    GBT='Gigabyte'; HPN='HP'; HWP='HP'; HPQ='HP'; VSC='ViewSonic'; PHL='Philips'
    NEC='NEC'; EIZ='EIZO'; IVM='iiyama'; LEN='Lenovo'; APP='Apple'; HEI='Hisense'
    CMN='ChiMei'; AUO='AU Optronics'; SHP='Sharp'; DGC='Dell'
}

# Loest einen rohen EDID-Code ('AUS27F5') zu 'ASUS 27F5' auf. Gibt bei
# unbekanntem Hersteller den Code unveraendert zurueck, bei leerem Input $null.
function Resolve-EdidName {
    param([string]$Code)
    if ([string]::IsNullOrWhiteSpace($Code)) { return $null }
    $c = $Code.Trim()
    if ($c.Length -lt 4) { return $c }
    $vid  = $c.Substring(0,3).ToUpper()
    $rest = $c.Substring(3).Trim()
    if ($Global:EdidVendors.ContainsKey($vid)) {
        return (("$($Global:EdidVendors[$vid]) $rest").Trim())
    }
    return $c
}

function Update-MonitorList {
    $ctrls.monitorList.Children.Clear()
    $mmt = Get-MMTPath
    $monitors = @()
    if ($mmt) {
        $monitors = Get-MonitorTable -Mmt $mmt
    } else {
        # Fallback ohne MMT - nur via WMI
        $ids = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue
        foreach ($m in $ids) {
            $manu = ($m.ManufacturerName | Where-Object {$_ -ne 0} | ForEach-Object {[char]$_}) -join ''
            $model = ($m.UserFriendlyName | Where-Object {$_ -ne 0} | ForEach-Object {[char]$_}) -join ''
            # 3-Letter-PNP-Code zu Klartext aufloesen (AUS -> ASUS)
            $manuName = if ($manu -and $Global:EdidVendors.ContainsKey($manu.ToUpper())) { $Global:EdidVendors[$manu.ToUpper()] } else { $manu }
            $monitors += [PSCustomObject]@{
                'Monitor Name' = ("$manuName $model").Trim()
                'Short Monitor ID' = ''
                Active = if ($m.Active) {'Yes'} else {'No'}
            }
        }
    }
    # Phantom-Monitore (inaktiv UND ohne Name UND ohne ID) rausfiltern
    $monitors = @($monitors | Where-Object {
        $_.Active -eq 'Yes' -or
        ($_.'Monitor Name' -and $_.'Monitor Name'.Trim()) -or
        ($_.'Short Monitor ID' -and $_.'Short Monitor ID'.Trim())
    })

    if ($monitors.Count -eq 0) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = '(keine Monitore erkannt - MMT nicht installiert?)'
        $tb.Foreground = $Global:SuiteColors.TextSecondary; $tb.FontSize = 11
        $ctrls.monitorList.Children.Add($tb) | Out-Null
        return
    }

    foreach ($m in $monitors) {
        $isActive = ($m.Active -eq 'Yes')
        $isPrimary = ($m.Primary -eq 'Yes')

        $b = New-Object System.Windows.Controls.Border
        $b.Background = $Global:SuiteColors.BgBase
        $b.Padding = (New-Object System.Windows.Thickness 10,6,10,6)
        $b.Margin = (New-Object System.Windows.Thickness 0,3,0,0)
        $b.CornerRadius = (New-Object System.Windows.CornerRadius 4)
        $b.BorderBrush = if ($isPrimary) { $Global:SuiteColors.Accent } elseif ($isActive) { $Global:SuiteColors.StatusOK } else { $Global:SuiteColors.BorderStrong }
        $b.BorderThickness = (New-Object System.Windows.Thickness 0,0,0,2)

        $grid = New-Object System.Windows.Controls.Grid
        $b.Child = $grid
        foreach ($w in 70,140,'*',80) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            if ($w -eq '*') { $cd.Width = '*' } else { $cd.Width = $w }
            $grid.ColumnDefinitions.Add($cd) | Out-Null
        }

        $stTxt = New-Object System.Windows.Controls.TextBlock
        $col = if ($isActive) { $Global:SuiteColors.StatusOK } else { $Global:SuiteColors.TextSecondary }
        $stTxt.Text = if ($isActive) { 'AKTIV' } else { 'inaktiv' }
        $stTxt.Foreground = $col; $stTxt.FontWeight = 'Bold'; $stTxt.FontSize = 10
        $stTxt.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($stTxt, 0)
        $grid.Children.Add($stTxt) | Out-Null

        $idTxt = New-Object System.Windows.Controls.TextBlock
        $id = $m.'Short Monitor ID'; if (-not $id) { $id = '-' }
        $idTxt.Text = $id; $idTxt.Foreground = $Global:SuiteColors.TextSecondary; $idTxt.FontSize = 10
        $idTxt.FontFamily = (New-Object System.Windows.Media.FontFamily 'Consolas')
        $idTxt.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($idTxt, 1)
        $grid.Children.Add($idTxt) | Out-Null

        $nmTxt = New-Object System.Windows.Controls.TextBlock
        $nm = $m.'Monitor Name'
        if (-not $nm) {
            # Falls Name leer - oft bei OLED via DisplayPort - rohen EDID-Code aufloesen
            $resolved = Resolve-EdidName $m.'Monitor Serial Number'
            if ($resolved) { $nm = $resolved }
            else { $nm = '(EDID liefert kein Friendly-Name - vermutlich OLED ueber DP)' }
        } else {
            # MMT-Name kann selbst ein roher EDID-Code sein (z.B. 'AUS27F5')
            if ($nm -match '^[A-Za-z]{3}[A-Za-z0-9]{2,}$') { $nm = Resolve-EdidName $nm }
        }
        $nmTxt.Text = $nm; $nmTxt.Foreground = $Global:SuiteColors.TextPrimary; $nmTxt.FontSize = 11
        $nmTxt.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($nmTxt, 2)
        $grid.Children.Add($nmTxt) | Out-Null

        if ($isPrimary) {
            $pBadge = New-Object System.Windows.Controls.Border
            $pBadge.Background = $Global:SuiteColors.InfoBg; $pBadge.CornerRadius = (New-Object System.Windows.CornerRadius 3)
            $pBadge.Padding = (New-Object System.Windows.Thickness 6,2,6,2)
            $pBadge.VerticalAlignment = 'Center'; $pBadge.HorizontalAlignment = 'Right'
            $pTxt = New-Object System.Windows.Controls.TextBlock
            $pTxt.Text = 'PRIMARY'; $pTxt.Foreground = $Global:SuiteColors.Accent; $pTxt.FontSize = 9; $pTxt.FontWeight = 'Bold'
            $pBadge.Child = $pTxt
            [System.Windows.Controls.Grid]::SetColumn($pBadge, 3)
            $grid.Children.Add($pBadge) | Out-Null
        }

        $ctrls.monitorList.Children.Add($b) | Out-Null
    }
}

$diagStatus = if (Test-Path $Global:Suite.DiagScript) { 'OK' } else { 'FEHLT - irm|iex neu ausfuehren' }
$ctrls.lblPaths.Text = @"
StateDir:    $($Global:Suite.StateDir)
DiagScript:  $($Global:Suite.DiagScript)  [$diagStatus]
MMT:         $($Global:Suite.Tools.MMT)
NPI:         $($Global:Suite.Tools.NPI)
PresentMon:  $($Global:Suite.Tools.PM)
NPI-Stamp:   $($Global:Suite.NPIStamp)
"@
$ctrls.tbMonitorPattern.Text = $Global:Suite.MonitorPattern
$ctrls.tbMonitorPattern.Add_TextChanged({
    $Global:Suite.MonitorPattern = $ctrls.tbMonitorPattern.Text
    # Persistent speichern
    $cfg = Get-SuiteConfig
    $cfg.MonitorPattern = $Global:Suite.MonitorPattern
    Save-SuiteConfig -Config $cfg
})
$ctrls.btnDetectMonitors.Add_Click({ Update-MonitorList; Update-DetectedHardware })

function Update-HistoryStat {
    try {
        $entries = @(Get-HistoryEntries)
        $applies = @($entries | Where-Object { $_.Action -eq 'Apply' -and $_.Success }).Count
        $reverts = @($entries | Where-Object { $_.Action -eq 'Revert' -and $_.Success }).Count
        $errors = @($entries | Where-Object { -not $_.Success }).Count
        $ctrls.lblHistoryStat.Text = "History (Suite-Aktionen): $($entries.Count) Eintraege - $applies Apply, $reverts Revert, $errors Fehler. (Hinweis: Tweaks die schon by-default OK waren brauchten kein Apply und tauchen nicht in der History auf.)"
    } catch { $ctrls.lblHistoryStat.Text = '' }
}

# Mappt einen Backup-Dateinamen auf die Original-Zieldatei. Backups heissen
# "<originalname>.bak_<yyyy-MM-dd_HHmmss>" (siehe Copy-FileToBackup) - bekannte
# Restore-Ziele sind die zwei PUBG-INIs. Unbekannte Basis -> $null (kein Auto-Restore).
function Get-BackupTarget {
    param([string]$BackupFileName)
    $base = $BackupFileName -replace '\.bak_.*$',''
    switch ($base) {
        'GameUserSettings.ini' { return (Get-PUBGGameUserPath) }
        'Engine.ini'           { return (Get-PUBGEnginePath) }
        default                { return $null }
    }
}

# Baut die Backup-Manager-Liste im Settings-Tab: eine Zeile pro Backup-Datei
# mit Wiederherstellen-Button. Stil analog Update-CapHistory.
function Update-BackupList {
    try {
        $ctrls.backupList.Children.Clear()
        Initialize-SuiteStorage
        $files = @(Get-ChildItem -Path $Global:Suite.BackupDir -Filter '*.bak_*' -File -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending)
        if ($files.Count -eq 0) {
            $ctrls.lblBackupInfo.Text = 'Noch keine Backups vorhanden - sie entstehen automatisch beim ersten Grafik-/INI-Apply.'
            return
        }
        $ctrls.lblBackupInfo.Text = "$($files.Count) Backup(s) - neueste zuerst."

        # Spalten: Datei(190) | Zeitpunkt(150) | Groesse(75) | Aktion(150)
        $colWidths = @(190,150,75,150)
        $hdr = New-Object System.Windows.Controls.Border
        $hdr.Background = $Global:SuiteColors.BgBase
        $hdr.Padding = (New-Object System.Windows.Thickness 8,4,8,4)
        $hdr.Margin = (New-Object System.Windows.Thickness 0,0,0,2)
        $hdrGrid = New-Object System.Windows.Controls.Grid
        $hdr.Child = $hdrGrid
        foreach ($w in $colWidths) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            $cd.Width = $w; $hdrGrid.ColumnDefinitions.Add($cd) | Out-Null
        }
        $hdrTexts = @('DATEI','ZEITPUNKT','GROESSE','')
        for ($i = 0; $i -lt $hdrTexts.Count; $i++) {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $hdrTexts[$i]; $tb.Foreground = $Global:SuiteColors.TextSecondary
            $tb.FontSize = 10; $tb.FontWeight = 'SemiBold'
            [System.Windows.Controls.Grid]::SetColumn($tb, $i)
            $hdrGrid.Children.Add($tb) | Out-Null
        }
        $ctrls.backupList.Children.Add($hdr) | Out-Null

        foreach ($f in $files) {
            try {
                $base = $f.Name -replace '\.bak_.*$',''
                # Zeitstempel aus dem Namen ziehen, sonst LastWriteTime
                $tsStr = if ($f.Name -match '\.bak_(\d{4}-\d{2}-\d{2})_(\d{2})(\d{2})(\d{2})$') {
                    "$($matches[1]) $($matches[2]):$($matches[3]):$($matches[4])"
                } else { $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') }
                $sizeKb = [math]::Round($f.Length / 1KB, 1)
                $target = Get-BackupTarget $f.Name

                $row = New-Object System.Windows.Controls.Border
                $row.Background = $Global:SuiteColors.Surface1
                $row.Padding = (New-Object System.Windows.Thickness 8,4,8,4)
                $row.Margin = (New-Object System.Windows.Thickness 0,1,0,0)
                $row.CornerRadius = (New-Object System.Windows.CornerRadius 2)
                $grid = New-Object System.Windows.Controls.Grid
                $row.Child = $grid
                foreach ($w in $colWidths) {
                    $cd = New-Object System.Windows.Controls.ColumnDefinition
                    $cd.Width = $w; $grid.ColumnDefinitions.Add($cd) | Out-Null
                }

                $texts = @($base, $tsStr, "$sizeKb KB")
                for ($i = 0; $i -lt 3; $i++) {
                    $tb = New-Object System.Windows.Controls.TextBlock
                    $tb.Text = "$($texts[$i])"; $tb.Foreground = $Global:SuiteColors.TextPrimary
                    $tb.FontSize = 11; $tb.VerticalAlignment = 'Center'
                    $tb.FontFamily = (New-Object System.Windows.Media.FontFamily 'Consolas')
                    [System.Windows.Controls.Grid]::SetColumn($tb, $i)
                    $grid.Children.Add($tb) | Out-Null
                }

                $btn = New-Object System.Windows.Controls.Button
                $btn.Content = 'Wiederherstellen'
                $btn.FontSize = 11; $btn.Height = 24; $btn.Width = 140
                $btn.HorizontalAlignment = 'Left'
                if ($target) {
                    # Restore-Kontext an den Button haengen (kein Closure ueber Loop-Variable)
                    $btn.Tag = [PSCustomObject]@{ BackupPath = $f.FullName; BackupName = $f.Name; Target = $target }
                    $btn.Add_Click({
                        $info = $this.Tag
                        $confirm = [System.Windows.MessageBox]::Show(
                            "Backup wiederherstellen?`n`nDatei:  $($info.BackupName)`nZiel:   $($info.Target)`n`nDer aktuelle Stand der Zieldatei wird vorher gesichert.`nPUBG muss geschlossen sein.",
                            'Backup wiederherstellen', 'YesNo', 'Warning')
                        if ($confirm -ne 'Yes') { return }
                        if (Test-Path $info.Target) { Copy-FileToBackup -SourcePath $info.Target | Out-Null }
                        $ok = Restore-FileFromBackup -BackupPath $info.BackupPath -TargetPath $info.Target
                        if ($ok) {
                            Write-SuiteLog "Backup wiederhergestellt: $($info.BackupName) -> $($info.Target)" 'INFO'
                            [System.Windows.MessageBox]::Show('Backup wiederhergestellt.', 'OK', 'OK', 'Information') | Out-Null
                            Update-BackupList
                            Update-GraphicsTab
                        } else {
                            [System.Windows.MessageBox]::Show('Wiederherstellung fehlgeschlagen - siehe Log.', 'Fehler', 'OK', 'Error') | Out-Null
                        }
                    })
                } else {
                    $btn.IsEnabled = $false
                    $btn.ToolTip = 'Ziel unbekannt - manuell aus dem Backups-Ordner zuruecksichern'
                }
                [System.Windows.Controls.Grid]::SetColumn($btn, 3)
                $grid.Children.Add($btn) | Out-Null

                $ctrls.backupList.Children.Add($row) | Out-Null
            } catch {
                Write-SuiteLog "Update-BackupList Row-Render Fehler: $($_.Exception.Message)" 'WARN'
            }
        }
    } catch {
        Write-SuiteLog "Update-BackupList Fehler: $($_.Exception.Message)" 'ERROR'
    }
}

$ctrls.btnOpenLogs.Add_Click({
    Initialize-SuiteStorage
    Start-Process explorer.exe -ArgumentList $Global:Suite.LogDir
})
$ctrls.btnOpenBackups.Add_Click({
    Initialize-SuiteStorage
    Start-Process explorer.exe -ArgumentList $Global:Suite.BackupDir
})
$ctrls.btnRefreshBackups.Add_Click({ Update-BackupList })
$ctrls.btnClearHistory.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show("History komplett loeschen?`n`nDanach koennen bisher applizierte Tweaks NICHT mehr per Knopf reverted werden.`n(Backups in $($Global:Suite.BackupDir) bleiben erhalten - manueller Revert weiter moeglich)", 'History loeschen', 'YesNo', 'Warning')
    if ($confirm -eq 'Yes') {
        Remove-Item $Global:Suite.HistoryFile -Force -ErrorAction SilentlyContinue
        Write-SuiteLog "History manuell geloescht" 'INFO'
        Update-HistoryStat
        Update-TweaksTab
        [System.Windows.MessageBox]::Show('History geloescht.', 'OK', 'OK', 'Information') | Out-Null
    }
})
Update-HistoryStat
Update-BackupList
$ctrls.btnAutoPattern.Add_Click({
    $mmt = Get-MMTPath
    if (-not $mmt) {
        [System.Windows.MessageBox]::Show('MultiMonitorTool nicht installiert. Erst Game Mode > Start Game Mode auf einem Monitor mit Acer-Pattern triggern, das installiert MMT.','MMT fehlt','OK','Warning') | Out-Null
        return
    }
    $monitors = Get-MonitorTable -Mmt $mmt
    $primary = ($monitors | Where-Object { $_.Primary -eq 'Yes' } | Select-Object -First 1).'Monitor Name'
    $secondaries = $monitors | Where-Object { $_.Active -eq 'Yes' -and $_.Primary -ne 'Yes' } | ForEach-Object { $_.'Monitor Name' } | Where-Object { $_ }
    if ($secondaries.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Nur 1 aktiver Monitor erkannt ($primary) - keine Sekundaeren zum Filtern.","Detect & Fill",'OK','Information') | Out-Null
        return
    }
    # Pattern = alle sekundaer-Namen mit OR getrennt (nur erste Worte um Versionen wie 'XB271HU A' auch zu treffen)
    $patternParts = $secondaries | ForEach-Object {
        $w = ($_ -split '\s+')[0]
        if ($w) { [regex]::Escape($w) }
    } | Where-Object { $_ } | Sort-Object -Unique
    $newPattern = $patternParts -join '|'
    $ctrls.tbMonitorPattern.Text = $newPattern
    $Global:Suite.MonitorPattern = $newPattern
    [System.Windows.MessageBox]::Show("Pattern gesetzt: $newPattern`n`nPrimary (bleibt aktiv): $primary`nSekundaer (werden im Game Mode deaktiviert):`n  $($secondaries -join "`n  ")","Detect & Fill",'OK','Information') | Out-Null
})
Update-DetectedHardware
Update-MonitorList

# ==================== PRESENTMON CAPTURE ====================
function Get-PresentMonPath {
    foreach ($p in @(
        "$($Global:Suite.Tools.PM)\PresentMon-x64.exe",
        "$($Global:Suite.Tools.PM)\PresentMon-x86.exe"
    )) {
        if (Test-Path $p) { return $p }
    }
    # Glob fuer versionierte Builds
    if (Test-Path $Global:Suite.Tools.PM) {
        $exes = Get-ChildItem -Path $Global:Suite.Tools.PM -Filter 'PresentMon-*.exe' -ErrorAction SilentlyContinue
        $x64 = $exes | Where-Object { $_.Name -match 'x64' } | Select-Object -First 1
        if ($x64) { return $x64.FullName }
        $any = $exes | Select-Object -First 1
        if ($any) { return $any.FullName }
    }
    return $null
}

function Install-PresentMonFromGitHub {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $target = $Global:Suite.Tools.PM
    try {
        if (-not (Test-Path $target)) { New-Item -Path $target -ItemType Directory -Force -ErrorAction Stop | Out-Null }
    } catch {
        $target = Join-Path $env:USERPROFILE 'Tools\PresentMon'
        Write-SuiteLog "PresentMon target fallback to user-profile dir: $target" 'WARN'
        if (-not (Test-Path $target)) { New-Item -Path $target -ItemType Directory -Force | Out-Null }
    }

    Write-SuiteLog "PresentMon Download startet von GitHub..." 'INFO'
    $outFile = $null
    $tempFile = $null
    try {
        $apiUrl = 'https://api.github.com/repos/GameTechDev/PresentMon/releases/latest'
        $headers = @{ 'User-Agent' = 'PUBG-Suite' }
        $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop

        $asset = $release.assets | Where-Object { $_.name -match '^PresentMon-.*-x64\.exe$' } | Select-Object -First 1
        if (-not $asset) {
            $asset = $release.assets | Where-Object { $_.name -match '^PresentMon-.*-x86\.exe$' } | Select-Object -First 1
        }
        if (-not $asset) {
            $asset = $release.assets | Where-Object { $_.name -match '^PresentMon-.*\.exe$' } | Select-Object -First 1
        }
        if (-not $asset) { throw 'Kein PresentMon-Asset im Release gefunden' }

        # Erst nach TEMP laden, validieren, dann ins Target verschieben (verhindert Partial-Download-Verifizierung)
        $tempFile = Join-Path $env:TEMP "presentmon_$(Get-Random)_$($asset.name)"
        $outFile = Join-Path $target $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempFile -UseBasicParsing -ErrorAction Stop

        # Size-Validierung gegen Asset-Metadata
        $downloadedSize = (Get-Item $tempFile).Length
        if ($asset.size -and $downloadedSize -ne $asset.size) {
            throw "Download unvollstaendig: $downloadedSize Bytes statt $($asset.size) Bytes erwartet"
        }
        if ($downloadedSize -lt 100000) {
            throw "Download zu klein ($downloadedSize Bytes) - vermutlich Fehler-HTML"
        }

        # Move ins Target
        Move-Item -Path $tempFile -Destination $outFile -Force -ErrorAction Stop
        $tempFile = $null  # Nicht mehr cleanup-pflichtig

        # Single-File-Renaming-Strategie
        if ($asset.name -match 'x64') {
            $canonical = Join-Path $target 'PresentMon-x64.exe'
            if ($outFile -ne $canonical) { Copy-Item -Path $outFile -Destination $canonical -Force }
        }
        Write-SuiteLog "PresentMon installiert: $outFile ($([math]::Round($downloadedSize / 1KB)) KB, $($release.tag_name))" 'INFO'
        return $outFile
    } catch {
        Write-SuiteLog "PresentMon-Install Fehler: $($_.Exception.Message)" 'ERROR'
        # Cleanup partial download
        if ($tempFile -and (Test-Path $tempFile)) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
        return $null
    }
}

function _Flatten-CaptureEntries {
    # Erkennt + unwrappt das alte verschachtelte 'value/Count' Format aus broken saves
    param($Node, $Out)
    if ($null -eq $Node) { return }
    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        foreach ($x in $Node) { _Flatten-CaptureEntries -Node $x -Out $Out }
        return
    }
    $props = @($Node.PSObject.Properties.Name)
    if ($props -contains 'value' -and $props -contains 'Count') {
        _Flatten-CaptureEntries -Node $Node.value -Out $Out
        return
    }
    if ($props -contains 'AvgFps') {
        $Out.Add($Node) | Out-Null
    }
}

function Get-CaptureHistory {
    if (-not (Test-Path $Global:Suite.CapturesFile)) { return @() }
    try {
        $raw = Get-Content $Global:Suite.CapturesFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-SuiteLog "Get-CaptureHistory parse fehler: $($_.Exception.Message)" 'WARN'
        return @()
    }
    $result = New-Object System.Collections.Generic.List[object]
    _Flatten-CaptureEntries -Node $raw -Out $result
    return @($result.ToArray())
}

function Add-CaptureEntry {
    param($Entry)
    try {
        $existing = @(Get-CaptureHistory)
        # Cap auf letzte 49 (+ neuer Entry = 50 max)
        if ($existing.Count -ge 50) {
            $existing = @($existing[($existing.Count - 49)..($existing.Count - 1)])
        }
        # PS 5.1 Quirk: $list | ConvertTo-Json unwrappt Single-Element-Array zu Object.
        # Loesung: ConvertTo-Json -InputObject (kein Pipeline) + bei size=1 manuell array-wrappen
        $combined = @()
        $combined += $existing
        $combined += $Entry
        if ($combined.Count -eq 1) {
            $itemJson = $combined[0] | ConvertTo-Json -Depth 8
            $json = "[" + $itemJson + "]"
        } else {
            $json = ConvertTo-Json -InputObject $combined -Depth 8
            # Sicherheits-Check: muss mit '[' beginnen
            if ($json -notmatch '^\s*\[') { $json = "[$json]" }
        }
        Set-Content -Path $Global:Suite.CapturesFile -Value $json -Encoding UTF8 -NoNewline
    } catch {
        Write-SuiteLog "Capture-History Save Fehler: $($_.Exception.Message)" 'ERROR'
    }
}

function Rebuild-CaptureHistoryFromCsv {
    # Recovery-Funktion: scannt captures\ Ordner und rebuildet captures.json aus den CSVs
    Initialize-SuiteStorage
    $files = @(Get-ChildItem -Path $Global:Suite.CaptureDir -Filter 'capture_*.csv' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    Write-SuiteLog "Rebuild-CaptureHistory: $($files.Count) CSV-Dateien gefunden" 'INFO'
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($f in $files) {
        $result = Analyze-CaptureCSV -CsvPath $f.FullName
        if ($result -and -not $result.Error) {
            $entries.Add($result) | Out-Null
        }
    }
    if ($entries.Count -eq 0) {
        Set-Content -Path $Global:Suite.CapturesFile -Value '[]' -Encoding UTF8 -NoNewline
        Write-SuiteLog "Rebuild: leeres history-File geschrieben" 'INFO'
        return 0
    }
    $arr = $entries.ToArray()
    if ($arr.Count -eq 1) {
        $json = "[" + ($arr[0] | ConvertTo-Json -Depth 8) + "]"
    } else {
        $json = ConvertTo-Json -InputObject $arr -Depth 8
        if ($json -notmatch '^\s*\[') { $json = "[$json]" }
    }
    Set-Content -Path $Global:Suite.CapturesFile -Value $json -Encoding UTF8 -NoNewline
    Write-SuiteLog "Rebuild: $($entries.Count) Eintraege geschrieben" 'INFO'
    return $entries.Count
}

function Analyze-CaptureCSV {
    param([string]$CsvPath)
    # Kontrakt: IMMER eine Hashtable zurueckgeben - entweder ein Ergebnis oder
    # @{ Error=... }. Frueher kam hier $null zurueck, was der Capture-Timer als
    # Erfolg fehldeutete (Bug: "Fehler: unbekannt" + leere Fertig-Meldung).
    if ([string]::IsNullOrWhiteSpace($CsvPath) -or -not (Test-Path $CsvPath)) {
        return @{ Error = 'PresentMon-CSV nicht gefunden - Capture hat keine Datei erzeugt' }
    }
    try {
        $data = Import-Csv $CsvPath
        if ($data.Count -lt 10) {
            return @{ Error = "Capture abgebrochen: nur $($data.Count) Zeilen erfasst - PUBG lief nicht im Vordergrund oder der Lauf war zu kurz"
                      Aborted = $true; Frames = $data.Count }
        }

        $ft = @($data | ForEach-Object {
            try { [double]$_.MsBetweenPresents } catch { 0 }
        } | Where-Object { $_ -gt 0 })

        if ($ft.Count -lt 10) {
            return @{ Error = "Capture abgebrochen: nur $($ft.Count) gueltige Frametimes erfasst"
                      Aborted = $true; Frames = $ft.Count }
        }

        $sorted = $ft | Sort-Object
        $n = $sorted.Count
        $avgMs = ($ft | Measure-Object -Average).Average
        $avgFps = [math]::Round(1000 / $avgMs, 1)

        $worst1Count = [Math]::Max(1, [int]($n * 0.01))
        $worst01Count = [Math]::Max(1, [int]($n * 0.001))
        $worst1 = $sorted | Select-Object -Last $worst1Count
        $worst01 = $sorted | Select-Object -Last $worst01Count
        $onePct = [math]::Round(1000 / (($worst1 | Measure-Object -Average).Average), 1)
        $zeroOnePct = [math]::Round(1000 / (($worst01 | Measure-Object -Average).Average), 1)

        $variance = ($ft | ForEach-Object { [math]::Pow($_ - $avgMs, 2) } | Measure-Object -Sum).Sum / $n
        $stddev = [math]::Round([math]::Sqrt($variance), 2)
        $stutterCount = ($ft | Where-Object { $_ -gt ($avgMs * 2) }).Count
        $stutterPct = [math]::Round(($stutterCount / $n) * 100, 2)

        # PresentMode - PresentMon v2 schreibt String-Namen wie "Hardware: Legacy Flip" statt Zahl
        $pmTopName = $null
        if ($data[0].PSObject.Properties.Name -contains 'PresentMode') {
            $modeGroups = $data | Group-Object PresentMode | Sort-Object Count -Descending
            if ($modeGroups -and $modeGroups[0]) {
                $pmTopName = $modeGroups[0].Name
            }
        }
        # Quality + Friendly-Label per Wildcard-Match auf String.
        # BEST = optimal (Independent/Legacy Flip - kein DWM-Compose),
        # OK = akzeptabel (Composed Flip/Legacy Copy - geringer DWM-Overhead),
        # WARN = unguenstig, BAD = ~3-5ms Latency-Overhead
        $pmRaw = if ($pmTopName) { [string]$pmTopName } else { '' }
        $modeQuality = switch -Wildcard ($pmRaw) {
            '*Independent Flip*' { 'BEST' }
            '*Legacy Flip*'      { 'BEST' }
            '*Composed Flip*'    { 'OK' }
            '*Legacy Copy*'      { 'OK' }
            '*Composed Copy*'    { 'BAD' }
            '*Composition Atlas*' { 'WARN' }
            ''                   { 'SKIP' }
            default              { 'WARN' }
        }
        $modeLabel = if ($pmRaw) { $pmRaw } else { 'unbekannt' }
        # Konkrete Erklaerung pro Mode
        $modeExplain = switch -Wildcard ($pmRaw) {
            '*Independent Flip*' { 'OPTIMAL - Exclusive Fullscreen, direkter GPU->Display Pfad, niedrigste Latency' }
            '*Legacy Flip*'      { 'OPTIMAL - Hardware Direct Flip, niedrige Latency, KEIN DWM-Compose-Overhead' }
            '*Composed Flip*'    { 'OK - Borderless Flip-Model, modern, gute Latency via DWM' }
            '*Legacy Copy*'      { 'OK - Hardware Copy, akzeptabel' }
            '*Composed Copy*'    { 'BAD - Legacy DWM-Compose, HOECHSTE Latency (~3-5ms Overhead). RTSS / Multi-Monitor / falsche Settings?' }
            '*Composition Atlas*' { 'WARN - ungewoehnlich, eventuell Treiber-Bug oder DWM-Mode-Switch beobachtet' }
            default              { '' }
        }

        # AllowsTearing -> G-Sync aktiv?
        $tearingActive = $false
        if ($data[0].PSObject.Properties.Name -contains 'AllowsTearing') {
            $tearingActive = (($data | Where-Object { $_.AllowsTearing -eq '1' }).Count -gt ($n * 0.5))
        }

        # GPU vs CPU Bottleneck Analyse
        $cpuBusyAvg = $null; $gpuBusyAvg = $null; $bottleneck = 'unbekannt'
        if ($data[0].PSObject.Properties.Name -contains 'MsCPUBusy') {
            $cpuVals = @($data | ForEach-Object {
                if ($_.MsCPUBusy -and $_.MsCPUBusy -ne 'NA') { try { [double]$_.MsCPUBusy } catch { $null } }
            } | Where-Object { $null -ne $_ })
            if ($cpuVals.Count -gt 10) {
                $cpuBusyAvg = [math]::Round(($cpuVals | Measure-Object -Average).Average, 2)
            }
        }
        if ($data[0].PSObject.Properties.Name -contains 'MsGPUBusy') {
            $gpuVals = @($data | ForEach-Object {
                if ($_.MsGPUBusy -and $_.MsGPUBusy -ne 'NA') { try { [double]$_.MsGPUBusy } catch { $null } }
            } | Where-Object { $null -ne $_ })
            if ($gpuVals.Count -gt 10) {
                $gpuBusyAvg = [math]::Round(($gpuVals | Measure-Object -Average).Average, 2)
            }
        }
        if ($null -ne $cpuBusyAvg -and $null -ne $gpuBusyAvg) {
            $diff = $cpuBusyAvg - $gpuBusyAvg
            $bottleneck = if ($diff -gt 0.5) { 'CPU-Bound' } elseif ($diff -lt -0.5) { 'GPU-Bound' } else { 'Balanced' }
        }

        # Render-to-Present Latency
        $renderLatAvg = $null
        if ($data[0].PSObject.Properties.Name -contains 'MsRenderPresentLatency') {
            $rlVals = @($data | ForEach-Object {
                if ($_.MsRenderPresentLatency -and $_.MsRenderPresentLatency -ne 'NA') { try { [double]$_.MsRenderPresentLatency } catch { $null } }
            } | Where-Object { $null -ne $_ })
            if ($rlVals.Count -gt 10) {
                $renderLatAvg = [math]::Round(($rlVals | Measure-Object -Average).Average, 2)
            }
        }

        # MsUntilDisplayed - Render-to-Photon
        $untilDispAvg = $null
        if ($data[0].PSObject.Properties.Name -contains 'MsUntilDisplayed') {
            $udVals = @($data | ForEach-Object {
                if ($_.MsUntilDisplayed -and $_.MsUntilDisplayed -ne 'NA') { try { [double]$_.MsUntilDisplayed } catch { $null } }
            } | Where-Object { $null -ne $_ })
            if ($udVals.Count -gt 10) {
                $untilDispAvg = [math]::Round(($udVals | Measure-Object -Average).Average, 2)
            }
        }

        # Click-to-Photon Latency (Reflex-only - meist NA in PUBG)
        $clickLatAvg = $null
        if ($data[0].PSObject.Properties.Name -contains 'MsClickToPhotonLatency') {
            $clVals = @($data | ForEach-Object {
                if ($_.MsClickToPhotonLatency -and $_.MsClickToPhotonLatency -ne 'NA') { try { [double]$_.MsClickToPhotonLatency } catch { $null } }
            } | Where-Object { $null -ne $_ })
            if ($clVals.Count -gt 5) {
                $clickLatAvg = [math]::Round(($clVals | Measure-Object -Average).Average, 1)
            }
        }

        # FPS-Stabilitaet als Score (StdDev als % vom AvgMs)
        $stabilityScore = if ($avgMs -gt 0) { [math]::Round((1 - ($stddev / $avgMs)) * 100, 1) } else { 0 }

        return @{
            CsvPath = $CsvPath
            FileName = [System.IO.Path]::GetFileName($CsvPath)
            CaptureTime = (Get-Item $CsvPath).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            Frames = $n
            DurationSec = [math]::Round($n / $avgFps, 1)
            AvgFps = $avgFps
            OnePctLow = $onePct
            ZeroOnePctLow = $zeroOnePct
            AvgMs = [math]::Round($avgMs, 2)
            StdDevMs = $stddev
            StabilityScore = $stabilityScore
            StutterPct = $stutterPct
            PresentMode = $pmTopName
            PresentModeLabel = $modeLabel
            PresentModeQuality = $modeQuality
            PresentModeExplain = $modeExplain
            GSyncActive = $tearingActive
            CpuBusyMs = $cpuBusyAvg
            GpuBusyMs = $gpuBusyAvg
            Bottleneck = $bottleneck
            RenderLatencyMs = $renderLatAvg
            UntilDisplayedMs = $untilDispAvg
            ClickToPhotonMs = $clickLatAvg
        }
    } catch {
        return @{ Error = $_.Exception.Message }
    }
}

# ==================== TWEAK APPLY/REVERT WRAPPERS ====================
# Apply/Revert arbeiten mit dem Registry-Modell: Tweak.Apply liefert
# @{ Success; Message; Snapshot }, Tweak.Revert($Snapshot) liefert
# @{ Success; Message }. Der Snapshot wird wie bisher in der history.json
# abgelegt, sodass der bestehende 1-Klick-Revert weiterfunktioniert.
function Get-TweakResult {
    # Holt aus dem (ggf. mehrteiligen) Pipeline-Output das Ergebnis-Hashtable.
    param($Raw)
    $last = @($Raw) | Select-Object -Last 1
    if ($last -is [System.Collections.IDictionary]) { return $last }
    return $null
}

function Invoke-TweakApply {
    param($Tweak)
    Write-SuiteLog "Apply START: $($Tweak.Id) ($($Tweak.Name))"
    try {
        $res = Get-TweakResult (& $Tweak.Apply)
        $success  = $false; $snapshot = $null; $msg = 'Apply lieferte kein gueltiges Ergebnis'
        if ($res) {
            $success  = [bool]$res['Success']
            $snapshot = $res['Snapshot']
            $msg      = "$($res['Message'])"
        }
        Add-HistoryEntry -Action 'Apply' -TweakId $Tweak.Id -Snapshot $snapshot -Success $success -ErrorMsg $(if ($success) { '' } else { $msg })
        $Global:LastTweakMessage = $msg
        if ($success) { Write-SuiteLog "Apply OK: $($Tweak.Id) - $msg" 'INFO' }
        else          { Write-SuiteLog "Apply FAIL: $($Tweak.Id) - $msg" 'ERROR' }
        return $success
    } catch {
        $emsg = $_.Exception.Message
        Add-HistoryEntry -Action 'Apply' -TweakId $Tweak.Id -Success $false -ErrorMsg $emsg
        Write-SuiteLog "Apply EXCEPTION: $($Tweak.Id) - $emsg" 'ERROR'
        $Global:LastTweakMessage = $emsg
        return $false
    }
}

function Invoke-TweakRevert {
    param($Tweak)
    Write-SuiteLog "Revert START: $($Tweak.Id)"
    if (-not $Tweak.Revert) {
        Write-SuiteLog "Revert FAIL: $($Tweak.Id) - keine Revert-Funktion" 'WARN'
        return $false
    }
    $snapshot = Get-LastSnapshot -TweakId $Tweak.Id
    if (-not $snapshot) {
        Write-SuiteLog "Revert FAIL: $($Tweak.Id) - kein Snapshot in History" 'WARN'
        return $false
    }
    try {
        $res = Get-TweakResult (& $Tweak.Revert $snapshot)
        $success = $false; $msg = 'Revert lieferte kein gueltiges Ergebnis'
        if ($res) { $success = [bool]$res['Success']; $msg = "$($res['Message'])" }
        Add-HistoryEntry -Action 'Revert' -TweakId $Tweak.Id -Success $success -ErrorMsg $(if ($success) { '' } else { $msg })
        $Global:LastTweakMessage = $msg
        if ($success) { Write-SuiteLog "Revert OK: $($Tweak.Id) - $msg" 'INFO' }
        else          { Write-SuiteLog "Revert FAIL: $($Tweak.Id) - $msg" 'ERROR' }
        return $success
    } catch {
        $emsg = $_.Exception.Message
        Add-HistoryEntry -Action 'Revert' -TweakId $Tweak.Id -Success $false -ErrorMsg $emsg
        Write-SuiteLog "Revert EXCEPTION: $($Tweak.Id) - $emsg" 'ERROR'
        $Global:LastTweakMessage = $emsg
        return $false
    }
}

function Test-TweakRevertable {
    param($Tweak)
    if (-not $Tweak.Revert) { return $false }
    return ($null -ne (Get-LastSnapshot -TweakId $Tweak.Id))
}

# ==================== TWEAKS TAB UI ====================
$Global:TweakSelection = @{}  # Id -> bool
$Global:TweakFilter = 'open'   # 'all' / 'open' / 'done' - default: zeige nur was zu tun ist

function Build-TweakRow {
    param($Tweak)

    $status = & $Tweak.StatusFn
    $statusColors = @{ 'OK' = $Global:SuiteColors.StatusOK; 'WARN' = $Global:SuiteColors.StatusWarn; 'BAD' = $Global:SuiteColors.StatusError; 'SKIP' = $Global:SuiteColors.TextSecondary }
    $color = $statusColors[$status]; if (-not $color) { $color = $Global:SuiteColors.TextSecondary }

    # Outer Border
    $row = New-Object System.Windows.Controls.Border
    $row.Background = $Global:SuiteColors.Surface1
    $row.BorderBrush = $color
    $row.BorderThickness = (New-Object System.Windows.Thickness 0,0,0,2)
    $row.Padding = (New-Object System.Windows.Thickness 12,8,12,8)
    $row.Margin = (New-Object System.Windows.Thickness 0,0,0,6)
    $row.CornerRadius = (New-Object System.Windows.CornerRadius 3)

    # Vertical StackPanel
    $vsp = New-Object System.Windows.Controls.StackPanel
    $row.Child = $vsp

    # Header row (horizontal)
    $hdr = New-Object System.Windows.Controls.DockPanel
    $hdr.LastChildFill = $true
    $vsp.Children.Add($hdr) | Out-Null

    # Right-side action area (status + apply button) - LastChild=false damit kein Stretch
    $actions = New-Object System.Windows.Controls.StackPanel
    $actions.Orientation = 'Horizontal'
    [System.Windows.Controls.DockPanel]::SetDock($actions, 'Right')

    $stBorder = New-Object System.Windows.Controls.Border
    $stBorder.Background = $Global:SuiteColors.BgBase; $stBorder.CornerRadius = (New-Object System.Windows.CornerRadius 3)
    $stBorder.Padding = (New-Object System.Windows.Thickness 8,3,8,3)
    $stBorder.VerticalAlignment = 'Center'; $stBorder.Margin = (New-Object System.Windows.Thickness 0,0,8,0)
    $stTxt = New-Object System.Windows.Controls.TextBlock
    $stTxt.Text = $status; $stTxt.Foreground = $color; $stTxt.FontWeight = 'Bold'; $stTxt.FontSize = 11
    $stBorder.Child = $stTxt
    $actions.Children.Add($stBorder) | Out-Null

    $btn = New-Object System.Windows.Controls.Button
    $btn.Width = 80; $btn.MinHeight = 28
    $btn.Tag = $Tweak.Id

    $revertable = Test-TweakRevertable -Tweak $Tweak

    if ($status -eq 'OK' -and $revertable) {
        $btn.Content = 'Revert'
        $btn.Background = $Global:SuiteColors.StatusWarn  # orange
        $btn.IsEnabled = $true
        $btn.Tag = "REVERT:$($Tweak.Id)"
    } elseif ($status -eq 'OK') {
        $btn.Content = 'Applied'
        $btn.IsEnabled = $false
    } elseif ($status -eq 'SKIP') {
        $btn.Content = '-'
        $btn.IsEnabled = $false
    } else {
        $btn.Content = 'Apply'
        $btn.IsEnabled = $true
    }

    $btn.Add_Click({
        $tag = $this.Tag
        $isRevert = $tag -match '^REVERT:'
        $id = $tag -replace '^REVERT:',''
        $tw = $Global:Tweaks | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if (-not $tw) { return }
        if ($isRevert) {
            $confirm = [System.Windows.MessageBox]::Show("Tweak zuruecksetzen?`n`n$($tw.Name)`n`nDie Suite stellt den Pre-Apply Zustand wieder her (aus History).", 'Revert', 'YesNo', 'Question')
            if ($confirm -ne 'Yes') { return }
            $ok = Invoke-TweakRevert -Tweak $tw
            if ($ok) {
                [System.Windows.MessageBox]::Show("$($tw.Name)`n`nRevert erfolgreich.", 'Revert OK', 'OK', 'Information') | Out-Null
            } else {
                [System.Windows.MessageBox]::Show("$($tw.Name)`n`nRevert fehlgeschlagen. Siehe Log im Settings-Tab.", 'Revert Fehler', 'OK', 'Warning') | Out-Null
            }
        } else {
            $ok = Invoke-TweakApply -Tweak $tw
            if ($ok) {
                [System.Windows.MessageBox]::Show("$($tw.Name)`n`nErfolgreich angewendet. Snapshot fuer Revert gespeichert.", 'Apply OK', 'OK', 'Information') | Out-Null
            } else {
                [System.Windows.MessageBox]::Show("$($tw.Name)`n`nApply fehlgeschlagen. Siehe Log im Settings-Tab.", 'Apply Fehler', 'OK', 'Warning') | Out-Null
            }
        }
        Update-TweaksTab; Update-StatusGrid
    })
    $actions.Children.Add($btn) | Out-Null
    $hdr.Children.Add($actions) | Out-Null

    # Left side: CheckBox + Cat-Badge + Name
    $leftSp = New-Object System.Windows.Controls.StackPanel
    $leftSp.Orientation = 'Horizontal'
    $leftSp.VerticalAlignment = 'Center'

    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.VerticalAlignment = 'Center'
    $cb.Margin = (New-Object System.Windows.Thickness 0,0,8,0)
    $cb.Tag = $Tweak.Id
    if ($Global:TweakSelection.ContainsKey($Tweak.Id)) { $cb.IsChecked = $Global:TweakSelection[$Tweak.Id] }
    $cb.Add_Checked({ $Global:TweakSelection[$this.Tag] = $true })
    $cb.Add_Unchecked({ $Global:TweakSelection[$this.Tag] = $false })
    $leftSp.Children.Add($cb) | Out-Null

    $catBg = New-Object System.Windows.Controls.Border
    $catBg.Background = $Global:SuiteColors.BorderStrong; $catBg.CornerRadius = (New-Object System.Windows.CornerRadius 3)
    $catBg.Padding = (New-Object System.Windows.Thickness 6,2,6,2)
    $catBg.VerticalAlignment = 'Center'; $catBg.Margin = (New-Object System.Windows.Thickness 0,0,10,0)
    $catTxt = New-Object System.Windows.Controls.TextBlock
    $catTxt.Text = $Tweak.Cat.ToUpper(); $catTxt.Foreground = $Global:SuiteColors.TextPrimary
    $catTxt.FontSize = 9; $catTxt.FontWeight = 'SemiBold'
    $catBg.Child = $catTxt
    $leftSp.Children.Add($catBg) | Out-Null

    $nameTxt = New-Object System.Windows.Controls.TextBlock
    $nameTxt.Text = $Tweak.Name; $nameTxt.Foreground = $Global:SuiteColors.TextPrimary; $nameTxt.FontSize = 12; $nameTxt.FontWeight = 'SemiBold'
    $nameTxt.VerticalAlignment = 'Center'
    $leftSp.Children.Add($nameTxt) | Out-Null

    $hdr.Children.Add($leftSp) | Out-Null

    # Desc + Impact line
    $detailLine = New-Object System.Windows.Controls.TextBlock
    $impTxt = "Alltag: $($Tweak.Impact)"
    if ($Tweak.ImpactDetail) { $impTxt += " - $($Tweak.ImpactDetail)" }
    $detailLine.Text = "$($Tweak.Desc)  |  $impTxt"
    $detailLine.Foreground = $Global:SuiteColors.TextSecondary; $detailLine.FontSize = 10
    $detailLine.TextWrapping = 'Wrap'
    $detailLine.Margin = (New-Object System.Windows.Thickness 30,4,0,0)
    $vsp.Children.Add($detailLine) | Out-Null

    # Expander mit Changes-Details
    if ($Tweak.Changes -and $Tweak.Changes.Count -gt 0) {
        $exp = New-Object System.Windows.Controls.Expander
        $exp.Header = 'Was wird veraendert? (Details anzeigen)'
        $exp.Foreground = $Global:SuiteColors.Accent; $exp.FontSize = 10
        $exp.Margin = (New-Object System.Windows.Thickness 30,4,0,0)

        $chSp = New-Object System.Windows.Controls.StackPanel
        $chSp.Margin = (New-Object System.Windows.Thickness 0,4,0,4)
        foreach ($ch in $Tweak.Changes) {
            $chTxt = New-Object System.Windows.Controls.TextBlock
            $chTxt.Text = "* $ch"
            $chTxt.Foreground = $Global:SuiteColors.TextPrimary; $chTxt.FontSize = 10
            $chTxt.FontFamily = (New-Object System.Windows.Media.FontFamily 'Consolas')
            $chTxt.TextWrapping = 'Wrap'
            $chTxt.Margin = (New-Object System.Windows.Thickness 0,1,0,1)
            $chSp.Children.Add($chTxt) | Out-Null
        }
        $exp.Content = $chSp
        $vsp.Children.Add($exp) | Out-Null
    }

    return $row
}

function Update-FilterButtonStyles {
    # Markiere den aktiven Filter-Button visuell
    $btns = @{
        'all'  = $ctrls.btnFilterAll
        'open' = $ctrls.btnFilterOpen
        'done' = $ctrls.btnFilterDone
    }
    foreach ($key in $btns.Keys) {
        if ($key -eq $Global:TweakFilter) {
            $btns[$key].Background = $Global:SuiteColors.Accent
        } else {
            $btns[$key].Background = $Global:SuiteColors.BorderStrong
        }
    }
}

function Update-TweaksTab {
    if (-not $ctrls.tweakContainer) { return }
    $ctrls.tweakContainer.Children.Clear()

    # Status pro Tweak einmalig sammeln (vermeidet n+1 Eval)
    $tweakStatuses = @{}
    foreach ($t in $Global:Tweaks) {
        try { $tweakStatuses[$t.Id] = & $t.StatusFn } catch { $tweakStatuses[$t.Id] = 'SKIP' }
    }

    # Filter anwenden
    $filteredTweaks = @($Global:Tweaks | Where-Object {
        $st = $tweakStatuses[$_.Id]
        switch ($Global:TweakFilter) {
            'open' { $st -eq 'WARN' -or $st -eq 'BAD' }
            'done' { $st -eq 'OK' }
            default { $true }  # 'all'
        }
    })

    $catOrder = @('Windows','GPU','Network','PUBG')
    $foundCats = $filteredTweaks | ForEach-Object { $_.Cat } | Sort-Object -Unique
    $cats = @($catOrder | Where-Object { $_ -in $foundCats }) + @($foundCats | Where-Object { $_ -notin $catOrder })

    if ($filteredTweaks.Count -eq 0) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = switch ($Global:TweakFilter) {
            'open' { '+ Alle Tweaks angewendet. Nichts mehr zu tun!' }
            'done' { 'Noch keine Tweaks angewendet.' }
            default { 'Keine Tweaks definiert.' }
        }
        $empty.Foreground = if ($Global:TweakFilter -eq 'open') { $Global:SuiteColors.StatusOK } else { $Global:SuiteColors.TextSecondary }
        $empty.FontSize = 14; $empty.FontWeight = 'SemiBold'
        $empty.Margin = (New-Object System.Windows.Thickness 0,40,0,0)
        $empty.HorizontalAlignment = 'Center'
        $ctrls.tweakContainer.Children.Add($empty) | Out-Null
    } else {
        foreach ($catName in $cats) {
            $catTweaks = @($filteredTweaks | Where-Object { $_.Cat -eq $catName })
            if ($catTweaks.Count -eq 0) { continue }

            $header = New-Object System.Windows.Controls.TextBlock
            $header.Text = "$catName ($($catTweaks.Count))"
            $header.Foreground = $Global:SuiteColors.Accent; $header.FontSize = 13; $header.FontWeight = 'Bold'
            $header.Margin = (New-Object System.Windows.Thickness 0,12,0,6)
            $ctrls.tweakContainer.Children.Add($header) | Out-Null

            foreach ($t in $catTweaks) {
                $row = Build-TweakRow -Tweak $t
                $ctrls.tweakContainer.Children.Add($row) | Out-Null
            }
        }
    }

    # Counter-Buckets: jeder Tweak faellt in GENAU einen Bucket, Summe == total.
    #   offen         = Status WARN/BAD (Apply noch noetig)
    #   angewendet    = Status OK + von der Suite angewendet (Revert-Snapshot vorhanden)
    #   by_default_ok = Status OK, war schon ohne Apply korrekt (kein Snapshot,
    #                   grauer 'Applied'-Button) - taucht nicht in der History auf
    #   na            = Status SKIP / nicht ermittelbar
    $total = $Global:Tweaks.Count
    $needCnt = 0; $appliedCnt = 0; $byDefaultCnt = 0; $naCnt = 0
    foreach ($t in $Global:Tweaks) {
        switch ($tweakStatuses[$t.Id]) {
            'OK'    { if (Test-TweakRevertable -Tweak $t) { $appliedCnt++ } else { $byDefaultCnt++ } }
            'WARN'  { $needCnt++ }
            'BAD'   { $needCnt++ }
            default { $naCnt++ }   # SKIP / unbekannt
        }
    }
    $okCnt = $appliedCnt + $byDefaultCnt   # = was die 'Erledigt'-Filteransicht zeigt
    # Invariant: kein Tweak darf durchs Raster fallen (Bug #5).
    $bucketSum = $needCnt + $appliedCnt + $byDefaultCnt + $naCnt
    if ($bucketSum -ne $total) {
        Write-SuiteLog "Tweak-Counter-Invariante verletzt: offen=$needCnt angewendet=$appliedCnt byDefaultOK=$byDefaultCnt na=$naCnt Summe=$bucketSum != total=$total" 'WARN'
    }
    # Fuer das Dashboard (Bug #6) bereitstellen
    $Global:TweakCounts = @{ Total=$total; Open=$needCnt; Applied=$appliedCnt; ByDefaultOk=$byDefaultCnt; Na=$naCnt }
    $sel = @($Global:TweakSelection.GetEnumerator() | Where-Object { $_.Value }).Count

    # Filter-Button-Labels mit Counts
    $ctrls.btnFilterAll.Content = "Alle ($total)"
    $ctrls.btnFilterOpen.Content = "Offen ($needCnt)"
    $ctrls.btnFilterDone.Content = "Erledigt ($okCnt)"

    Update-FilterButtonStyles

    # Info-Zeile (vorhandene Last-Apply-Info aus Global state behalten)
    $base = "$appliedCnt angewendet + $byDefaultCnt by-default OK von $total  |  $needCnt offen"
    if ($naCnt -gt 0) { $base += "  |  $naCnt n/a" }
    $base += "  |  $sel selektiert  |  Filter: $($Global:TweakFilter)"
    if ($Global:LastApplyInfo) {
        $ctrls.lblTweakInfo.Text = "$base`n$($Global:LastApplyInfo)"
    } else {
        $ctrls.lblTweakInfo.Text = $base
    }
}

# ==================== TIMER-RESOLUTION-VERIFIKATION =========================
# Aktiver Probe-Test fuer den 'timerres'-Tweak: ein SEPARATER Prozess fordert
# die feinste Timer-Resolution an und haelt sie kurz. Sieht die Suite (ein
# anderer Prozess!) die Aenderung an ihrer eigenen Timer-Resolution, ist das
# globale Verhalten (GlobalTimerResolutionRequests) nachweislich aktiv. Ein
# Runspace wuerde nichts beweisen - er teilt sich den Prozess mit der Suite.
function Initialize-TimerNative {
    if ('PubgTimerNative' -as [type]) { return }
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PubgTimerNative {
    [DllImport("ntdll.dll", SetLastError=true)]
    public static extern int NtQueryTimerResolution(out uint Minimum, out uint Maximum, out uint Current);
}
'@
}

function Invoke-TimerResolutionVerify {
    try { Initialize-TimerNative }
    catch {
        $ctrls.lblTweakInfo.Text = 'Timer-Verifikation: ntdll-Anbindung fehlgeschlagen.'
        return
    }
    # Baseline: aktuelle Timer-Resolution der Suite messen
    $mn = 0; $mx = 0; $cu = 0
    [void][PubgTimerNative]::NtQueryTimerResolution([ref]$mn, [ref]$mx, [ref]$cu)
    if ($cu -le 0 -or $mx -le 0) {
        $ctrls.lblTweakInfo.Text = 'Timer-Verifikation: Messung nicht moeglich.'
        return
    }
    # Kind-Prozess: fordert in EIGENEM Prozess die feinste Aufloesung an + haelt
    # sie 3 s. -EncodedCommand vermeidet jegliches Quoting-Problem.
    $childSrc = @"
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class T{[DllImport("ntdll.dll")]public static extern int NtSetTimerResolution(uint d,bool s,out uint c);}'
`$c=0
[T]::NtSetTimerResolution($mx,`$true,[ref]`$c)|Out-Null
Start-Sleep -Milliseconds 3000
"@
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childSrc))
    $child = $null
    try {
        $child = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru `
                               -ArgumentList '-NoProfile','-EncodedCommand',$enc
    } catch {
        $ctrls.lblTweakInfo.Text = 'Timer-Verifikation: Probe-Prozess konnte nicht gestartet werden.'
        return
    }
    $ctrls.lblTweakInfo.Text = 'Timer-Resolution-Probe laeuft (~1.5 s) ...'
    # Verzoegerte Zweitmessung via DispatcherTimer - haelt den UI-Thread frei.
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(1500)
    $t.Tag = @{ Child=$child; C0=$cu; Max=$mx }
    $t.Add_Tick({
        $this.Stop()
        $d = $this.Tag
        $m1 = 0; $x1 = 0; $c1 = 0
        [void][PubgTimerNative]::NtQueryTimerResolution([ref]$m1, [ref]$x1, [ref]$c1)
        try { if ($d.Child -and -not $d.Child.HasExited) { $d.Child.Kill() } } catch {}
        # Registry-Status (persistente Konfiguration)
        $regOn = $false
        try {
            $rv = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' -Name 'GlobalTimerResolutionRequests' -ErrorAction SilentlyContinue).GlobalTimerResolutionRequests
            $regOn = ($rv -eq 1)
        } catch {}
        $msC0 = '{0:0.00}' -f ($d.C0  / 10000.0)
        $msC1 = '{0:0.00}' -f ($c1    / 10000.0)
        $msMx = '{0:0.00}' -f ($d.Max / 10000.0)
        $reg  = if ($regOn) { 'Registry-Tweak: gesetzt' } else { 'Registry-Tweak: NICHT gesetzt' }
        if ($c1 -gt 0 -and $c1 -lt ($d.C0 - 100)) {
            $msg = "[OK]  Globale Timer-Requests AKTIV - der Tweak greift. Ein fremder Prozess senkte den Timer der Suite auf $msC1 ms (vorher $msC0 ms). $reg."
        } elseif ($d.C0 -le ($d.Max + 100)) {
            $msg = "[i]  Timer laeuft bereits auf Maximum ($msMx ms) - eine andere App fordert ihn an, eindeutige Probe nicht moeglich. $reg."
        } elseif ($regOn) {
            $msg = "[!]  Timer unveraendert bei $msC0 ms - globaler Effekt noch nicht aktiv. Registry ist gesetzt: Reboot steht aus."
        } else {
            $msg = "[X]  Timer unveraendert bei $msC0 ms - pro-Prozess-Verhalten. Tweak 'timerres' im Tweaks-Tab anwenden, dann Reboot."
        }
        $ctrls.lblTweakInfo.Text = $msg
        try { Write-SuiteLog "Timer-Verify: $msg" 'INFO' } catch {}
    })
    $t.Start()
}

$ctrls.btnRefreshTweaks.Add_Click({ Update-TweaksTab; Update-StatusGrid })
$ctrls.btnVerifyTimer.Add_Click({ Invoke-TimerResolutionVerify })

$ctrls.btnFilterAll.Add_Click({ $Global:TweakFilter = 'all'; Update-TweaksTab })
$ctrls.btnFilterOpen.Add_Click({ $Global:TweakFilter = 'open'; Update-TweaksTab })
$ctrls.btnFilterDone.Add_Click({ $Global:TweakFilter = 'done'; Update-TweaksTab })

$ctrls.btnSelectAll.Add_Click({
    foreach ($t in $Global:Tweaks) {
        $st = & $t.StatusFn
        if ($st -eq 'WARN' -or $st -eq 'BAD') { $Global:TweakSelection[$t.Id] = $true }
    }
    Update-TweaksTab
})

$ctrls.btnSelectNone.Add_Click({
    $Global:TweakSelection.Clear()
    Update-TweaksTab
})

function Show-ApplyResult {
    param([string]$Title, [array]$AppliedNames, [array]$FailedNames)
    $applied = @($AppliedNames).Count
    $failed = @($FailedNames).Count
    $summary = "$applied angewendet, $failed Fehler"

    $msg = $summary
    if ($AppliedNames.Count -gt 0) {
        $msg += "`n`nErfolgreich:`n  + " + ($AppliedNames -join "`n  + ")
    }
    if ($FailedNames.Count -gt 0) {
        $msg += "`n`nFehlgeschlagen:`n  x " + ($FailedNames -join "`n  x ")
        $msg += "`n`nDetails: Logs im Settings-Tab oeffnen"
    }

    # Persistente Info-Zeile
    $ts = Get-Date -Format 'HH:mm:ss'
    $Global:LastApplyInfo = "Letzte Apply-Session ($ts): $summary"
    if ($AppliedNames.Count -gt 0) {
        $shortList = if ($AppliedNames.Count -le 3) { $AppliedNames -join ', ' } else { ($AppliedNames | Select-Object -First 3) -join ', ' + "..." }
        $Global:LastApplyInfo += " | OK: $shortList"
    }
    if ($FailedNames.Count -gt 0) {
        $Global:LastApplyInfo += " | FEHLER: " + ($FailedNames -join ', ')
    }

    $icon = if ($failed -gt 0) { 'Warning' } else { 'Information' }
    [System.Windows.MessageBox]::Show($msg, $Title, 'OK', $icon) | Out-Null
}

$ctrls.btnApplySelected.Add_Click({
    $selectedIds = @($Global:TweakSelection.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key })
    if ($selectedIds.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Nichts ausgewaehlt. Erst Checkboxen setzen oder "Select All" benutzen.', 'Hinweis', 'OK', 'Information') | Out-Null
        return
    }
    $appliedNames = @(); $failedNames = @()
    foreach ($id in $selectedIds) {
        $tw = $Global:Tweaks | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if ($tw) {
            if (Invoke-TweakApply -Tweak $tw) { $appliedNames += $tw.Name } else { $failedNames += $tw.Name }
        }
    }
    Show-ApplyResult -Title 'Apply Selected' -AppliedNames $appliedNames -FailedNames $failedNames
    Update-TweaksTab; Update-StatusGrid
})

$ctrls.btnApplyAll.Add_Click({
    # Zaehle erst die offenen Tweaks fuer aussagekraeftige Bestaetigung
    $openTweaks = @($Global:Tweaks | Where-Object {
        $st = & $_.StatusFn
        $st -eq 'WARN' -or $st -eq 'BAD'
    })
    if ($openTweaks.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Alle Tweaks sind bereits OK. Nichts zu tun.', 'Apply All', 'OK', 'Information') | Out-Null
        return
    }
    $listPreview = ($openTweaks | ForEach-Object { "  - $($_.Name)" }) -join "`n"
    $confirm = [System.Windows.MessageBox]::Show("$($openTweaks.Count) Tweaks werden angewendet:`n`n$listPreview`n`nFuer jeden wird ein Snapshot vor Apply gespeichert (Revert spaeter moeglich).`n`nWeiter?", 'Apply All - Bestaetigung', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }
    $appliedNames = @(); $failedNames = @()
    foreach ($t in $openTweaks) {
        if (Invoke-TweakApply -Tweak $t) { $appliedNames += $t.Name } else { $failedNames += $t.Name }
    }
    Show-ApplyResult -Title 'Apply All' -AppliedNames $appliedNames -FailedNames $failedNames
    Update-TweaksTab; Update-StatusGrid
})

# ==================== GRAFIK TAB ====================
# Eigener Tab fuer das PUBG Esport-Grafik-Profil ($Global:EsportGfxTweak).
# Bewusst getrennt von "Apply All" - separates Apply/Revert.

# Liefert den Tag-Wert des selektierten ComboBoxItem (= INI-Wert), sonst $null.
function Get-CbTag {
    param($ComboBox)
    $item = $ComboBox.SelectedItem
    if ($item -and $null -ne $item.Tag) { return [string]$item.Tag }
    return $null
}

# Selektiert im ComboBox das Item mit passendem Tag; faellt sonst auf Index 0.
function Set-CbByTag {
    param($ComboBox, [string]$Tag)
    foreach ($item in $ComboBox.Items) {
        if ([string]$item.Tag -eq $Tag) { $ComboBox.SelectedItem = $item; return }
    }
    if ($ComboBox.Items.Count -gt 0) { $ComboBox.SelectedIndex = 0 }
}

# Liest die aktuellen GameUserSettings.ini-Werte und stellt die Einzel-Dropdowns
# darauf ein. Fehlt die INI oder ein Key, faellt der Wert aufs Profil zurueck.
function Sync-GraphicsDropdowns {
    if (-not $ctrls.cmbAA) { return }
    $gus = Get-PUBGGameUserPath
    $content = $null
    if (Test-Path $gus) { $content = Get-Content $gus -Raw -ErrorAction SilentlyContinue }

    $getVal = {
        param($section, $key)
        if ($content -and ($content -match ('(?m)^\s*' + [regex]::Escape($key) + '\s*=\s*(.+?)\s*$'))) {
            # Float-Werte ('2.000000') auf den Ganzzahl-Teil reduzieren, damit
            # sie auf die 0..4-Tags der Dropdowns passen.
            $raw = [string]$matches[1]
            $num = $null; try { $num = [double]$raw } catch {}
            if ($null -ne $num) { return ([string][int][math]::Floor($num)) }
            return $raw
        }
        if ($Global:EsportGfxProfile -and $Global:EsportGfxProfile[$section] -and $Global:EsportGfxProfile[$section][$key]) {
            $pv = [string]$Global:EsportGfxProfile[$section][$key]
            $pn = $null; try { $pn = [double]$pv } catch {}
            if ($null -ne $pn) { return ([string][int][math]::Floor($pn)) }
            return $pv
        }
        return '0'
    }
    $sg = 'ScalabilityGroups'; $ts = '/Script/TslGame.TslGameUserSettings'

    # Mapping: UI-Label -> ini-Key. Eine Quelle fuer Dropdown-Befuellung und
    # Status-Indikator. Die Soll-Werte stammen aus $Global:EsportGfxProfile
    # (PUBGProfile.psd1) - dieselbe Quelle, gegen die der Report prueft.
    $map = @(
        @{ Cb=$ctrls.cmbFullscreen; Ind=$ctrls.lblIndFullscreen; Sec=$ts; Key='FullscreenMode' }
        @{ Cb=$ctrls.cmbAA;         Ind=$ctrls.lblIndAA;         Sec=$sg; Key='sg.AntiAliasingQuality' }
        @{ Cb=$ctrls.cmbTexture;    Ind=$ctrls.lblIndTexture;    Sec=$sg; Key='sg.TextureQuality' }
        @{ Cb=$ctrls.cmbViewDist;   Ind=$ctrls.lblIndViewDist;   Sec=$sg; Key='sg.ViewDistanceQuality' }
        @{ Cb=$ctrls.cmbShadow;     Ind=$ctrls.lblIndShadow;     Sec=$sg; Key='sg.ShadowQuality' }
        @{ Cb=$ctrls.cmbPost;       Ind=$ctrls.lblIndPost;       Sec=$sg; Key='sg.PostProcessQuality' }
        @{ Cb=$ctrls.cmbEffects;    Ind=$ctrls.lblIndEffects;    Sec=$sg; Key='sg.EffectsQuality' }
        @{ Cb=$ctrls.cmbFoliage;    Ind=$ctrls.lblIndFoliage;    Sec=$sg; Key='sg.FoliageQuality' }
    )
    # Soll-Wert aus dem Profil (auf Ganzzahl normalisiert, wie $getVal)
    $getTarget = {
        param($section, $key)
        if ($Global:EsportGfxProfile -and $Global:EsportGfxProfile[$section] -and $null -ne $Global:EsportGfxProfile[$section][$key]) {
            $pv = [string]$Global:EsportGfxProfile[$section][$key]
            $pn = $null; try { $pn = [double]$pv } catch {}
            if ($null -ne $pn) { return ([string][int][math]::Floor($pn)) }
            return $pv
        }
        return $null
    }
    $haveIni = [bool]$content
    $okCount = 0
    foreach ($m in $map) {
        $cur = & $getVal $m.Sec $m.Key
        Set-CbByTag $m.Cb $cur
        if (-not $m.Ind) { continue }
        $tgt = & $getTarget $m.Sec $m.Key
        if (-not $haveIni) {
            $m.Ind.Text = '-'
            $m.Ind.Foreground = $Global:SuiteColors.TextDisabled
        } elseif ($null -eq $tgt) {
            $m.Ind.Text = ''
        } elseif ("$cur" -eq "$tgt") {
            $m.Ind.Text = 'OK'
            $m.Ind.Foreground = $Global:SuiteColors.StatusOK
            $okCount++
        } else {
            $m.Ind.Text = 'BAD'
            $m.Ind.Foreground = $Global:SuiteColors.StatusError
            $m.Ind.ToolTip = "Competitive-Soll: $tgt"
        }
    }

    # Globaler Match-Badge
    if ($ctrls.lblGfxMatchBadge -and $ctrls.gfxMatchBadge) {
        if (-not $haveIni) {
            $ctrls.lblGfxMatchBadge.Text = 'Competitive-Match: GameUserSettings.ini fehlt'
            $ctrls.gfxMatchBadge.Background = $Global:SuiteColors.BorderStrong
        } else {
            $total = $map.Count
            $allOk = ($okCount -eq $total)
            $ctrls.lblGfxMatchBadge.Text = "Competitive-Match: $okCount/$total"
            $ctrls.gfxMatchBadge.Background    = if ($allOk) { $Global:SuiteColors.OkBg } else { $Global:SuiteColors.WarnBg }
            $ctrls.lblGfxMatchBadge.Foreground = if ($allOk) { $Global:SuiteColors.StatusOK } else { $Global:SuiteColors.StatusWarn }
        }
    }
}

function Update-GraphicsTab {
    if (-not $ctrls.lblGfxStatus) { return }
    $tw = $Global:EsportGfxTweak
    if (-not $tw) { return }

    # Status
    $status = 'SKIP'
    try { $status = & $tw.StatusFn } catch { $status = 'SKIP' }
    $statusInfo = @{
        'OK'   = @{ Color=$Global:SuiteColors.StatusOK; Text='Profil aktiv - alle Kern-Werte gesetzt' }
        'WARN' = @{ Color=$Global:SuiteColors.StatusWarn; Text='Profil nicht (vollstaendig) aktiv - Werte weichen ab' }
        'BAD'  = @{ Color=$Global:SuiteColors.StatusError; Text='Profil nicht aktiv' }
        'SKIP' = @{ Color=$Global:SuiteColors.TextSecondary; Text='GameUserSettings.ini nicht gefunden - PUBG mind. einmal starten und beenden' }
    }
    $si = $statusInfo[$status]; if (-not $si) { $si = $statusInfo['SKIP'] }
    $ctrls.lblGfxStatus.Text = "[$status]  $($si.Text)"
    $ctrls.lblGfxStatus.Foreground = $si.Color

    # Profil-Werte menschenlesbar darstellen
    if (-not $Global:EsportGfxProfile) {
        $ctrls.lblGfxValues.Text = 'Profil nicht geladen - config\PUBGProfile.psd1 fehlt oder ist fehlerhaft.'
        $ctrls.btnGfxRevert.IsEnabled = $false
        return
    }
    $sgScale = @{ '0'='Sehr Niedrig'; '1'='Niedrig'; '2'='Mittel'; '3'='Hoch'; '4'='Ultra' }
    $sg = $Global:EsportGfxProfile['ScalabilityGroups']
    $tg = $Global:EsportGfxProfile['/Script/TslGame.TslGameUserSettings']
    $fsMode = @{ '0'='Exklusiv-Vollbild'; '1'='Vollbild-Fenster'; '2'='Fenster' }
    $lines = @(
        "Anzeigemodus       : $($fsMode[$tg['FullscreenMode']])"
        "Anti-Aliasing      : $($sgScale[$sg['sg.AntiAliasingQuality']])"
        "Texturen           : $($sgScale[$sg['sg.TextureQuality']])"
        "Sichtweite         : $($sgScale[$sg['sg.ViewDistanceQuality']])"
        "Schatten           : $($sgScale[$sg['sg.ShadowQuality']])"
        "Post-Processing    : $($sgScale[$sg['sg.PostProcessQuality']])"
        "Effekte            : $($sgScale[$sg['sg.EffectsQuality']])"
        "Laub               : $($sgScale[$sg['sg.FoliageQuality']])"
        "Render-Skalierung  : 100 %"
        "V-Sync             : Aus"
        "Bewegungsunschaerfe: Aus"
        "In-Game-Sharpen    : Aus"
        "Aufloesung         : unveraendert (hardware-/monitorspezifisch)"
    )
    $ctrls.lblGfxValues.Text = ($lines -join "`n")

    # Revert nur moeglich, wenn ein Snapshot/Backup existiert
    $revertable = Test-TweakRevertable -Tweak $tw
    $ctrls.btnGfxRevert.IsEnabled = $revertable

    # Apply-Button dynamisch: bei aktivem Profil sekundaer ("Erneut anwenden"),
    # bei Abweichung primaer-gruen ("Competitive-Profil anwenden") - sonst ist
    # unklar, ob der Klick noch etwas bewirkt (Bug #7).
    if ($ctrls.btnGfxApply) {
        if ($status -eq 'OK') {
            $ctrls.btnGfxApply.Content    = 'Profil erneut anwenden'
            $ctrls.btnGfxApply.Background  = $Global:SuiteColors.BorderStrong
            $ctrls.btnGfxApply.Foreground  = $Global:SuiteColors.TextPrimary
        } else {
            $ctrls.btnGfxApply.Content    = 'Competitive-Profil anwenden'
            $ctrls.btnGfxApply.Background  = $Global:SuiteColors.StatusOK
            $ctrls.btnGfxApply.Foreground  = 'White'
        }
    }

    if ($Global:LastGfxInfo) {
        $ctrls.lblGfxInfo.Text = $Global:LastGfxInfo
    } elseif (-not $revertable) {
        $ctrls.lblGfxInfo.Text = 'Noch nicht angewendet - kein Backup zum Zuruecksetzen vorhanden.'
    } else {
        $ctrls.lblGfxInfo.Text = 'Backup vorhanden - Zuruecksetzen moeglich.'
    }

    # Einzel-Dropdowns auf den aktuellen INI-Stand bringen
    Sync-GraphicsDropdowns
}

$ctrls.btnGfxRefresh.Add_Click({ Update-GraphicsTab })

$ctrls.btnGfxApply.Add_Click({
    $tw = $Global:EsportGfxTweak
    if (-not $tw) { return }
    $confirm = [System.Windows.MessageBox]::Show(
        "Das Competitive-Grafik-Profil wird in PUBGs GameUserSettings.ini geschrieben.`n`n" +
        "WICHTIG: PUBG muss JETZT komplett geschlossen sein - sonst ueberschreibt es die Datei beim Beenden.`n`n" +
        "Vor der Aenderung wird ein Backup erstellt (Zuruecksetzen spaeter moeglich).`n`nFortfahren?",
        'Grafik-Profil anwenden', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }
    $ts = Get-Date -Format 'HH:mm:ss'
    if (Invoke-TweakApply -Tweak $tw) {
        $Global:LastGfxInfo = "Profil angewendet ($ts). PUBG starten und im Grafikmenue pruefen."
        [System.Windows.MessageBox]::Show('Competitive-Grafik-Profil angewendet.', 'Grafik', 'OK', 'Information') | Out-Null
    } else {
        $Global:LastGfxInfo = "Apply fehlgeschlagen ($ts) - siehe Logs (Settings-Tab)."
        [System.Windows.MessageBox]::Show(
            "Anwenden fehlgeschlagen.`n`nHaeufigste Ursachen:`n  - PUBG laeuft noch (erst komplett beenden)`n  - GameUserSettings.ini fehlt (PUBG einmal starten und beenden)`n`nDetails: Logs im Settings-Tab.",
            'Grafik', 'OK', 'Warning') | Out-Null
    }
    Update-GraphicsTab
})

$ctrls.btnGfxRevert.Add_Click({
    $tw = $Global:EsportGfxTweak
    if (-not $tw) { return }
    if (-not (Test-TweakRevertable -Tweak $tw)) {
        [System.Windows.MessageBox]::Show('Kein Backup vorhanden - es wurde noch nichts angewendet.', 'Grafik', 'OK', 'Information') | Out-Null
        return
    }
    $confirm = [System.Windows.MessageBox]::Show(
        "GameUserSettings.ini wird aus dem letzten Backup wiederhergestellt.`n`n" +
        "PUBG muss dabei geschlossen sein.`n`nFortfahren?",
        'Grafik-Profil zuruecksetzen', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }
    $ts = Get-Date -Format 'HH:mm:ss'
    if (Invoke-TweakRevert -Tweak $tw) {
        $Global:LastGfxInfo = "Auf Backup zurueckgesetzt ($ts)."
        [System.Windows.MessageBox]::Show('GameUserSettings.ini aus Backup wiederhergestellt.', 'Grafik', 'OK', 'Information') | Out-Null
    } else {
        $Global:LastGfxInfo = "Zuruecksetzen fehlgeschlagen ($ts) - siehe Logs (Settings-Tab)."
        [System.Windows.MessageBox]::Show('Zuruecksetzen fehlgeschlagen. Details: Logs im Settings-Tab.', 'Grafik', 'OK', 'Warning') | Out-Null
    }
    Update-GraphicsTab
})

$ctrls.btnGfxApplyCustom.Add_Click({
    # Werte aus den Dropdowns einsammeln
    $sgSec = 'ScalabilityGroups'
    $tsSec = '/Script/TslGame.TslGameUserSettings'
    $values = @{
        $sgSec = @{
            'sg.AntiAliasingQuality' = (Get-CbTag $ctrls.cmbAA)
            'sg.TextureQuality'      = (Get-CbTag $ctrls.cmbTexture)
            'sg.ViewDistanceQuality' = (Get-CbTag $ctrls.cmbViewDist)
            'sg.ShadowQuality'       = (Get-CbTag $ctrls.cmbShadow)
            'sg.PostProcessQuality'  = (Get-CbTag $ctrls.cmbPost)
            'sg.EffectsQuality'      = (Get-CbTag $ctrls.cmbEffects)
            'sg.FoliageQuality'      = (Get-CbTag $ctrls.cmbFoliage)
        }
        $tsSec = @{
            'FullscreenMode'      = (Get-CbTag $ctrls.cmbFullscreen)
            # Werte als nutzer-gewaehlt markieren -> PUBG setzt sie nicht zurueck
            'bSavedGraphicOption' = 'True'
        }
    }
    # Defensive: keine $null-Werte schreiben (waere der Fall, wenn ein Dropdown
    # leer ist - sollte nie passieren, da Sync immer selektiert).
    foreach ($sec in @($values.Keys)) {
        foreach ($k in @($values[$sec].Keys)) {
            if ($null -eq $values[$sec][$k]) {
                [System.Windows.MessageBox]::Show("Dropdown '$k' hat keinen Wert - Tab neu laden (Status pruefen).", 'Grafik', 'OK', 'Warning') | Out-Null
                return
            }
        }
    }
    $confirm = [System.Windows.MessageBox]::Show(
        "Die in den Dropdowns gewaehlten Einzel-Werte werden in PUBGs GameUserSettings.ini geschrieben.`n`n" +
        "WICHTIG: PUBG muss JETZT komplett geschlossen sein.`n`n" +
        "Vor jeder Aenderung wird ein Backup erstellt (Wiederherstellen ueber den Backup-Manager im Settings-Tab).`n`nFortfahren?",
        'Einzel-Werte anwenden', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }
    $ts = Get-Date -Format 'HH:mm:ss'
    $res = Invoke-EsportGfxApplyCustom -Values $values
    if ($res.Success) {
        $Global:LastGfxInfo = "Einzel-Werte angewendet ($ts). PUBG starten und im Grafikmenue pruefen."
        $ctrls.lblGfxCustomInfo.Text = "Angewendet ($ts) - $($res.Message)."
        $ctrls.lblGfxCustomInfo.Foreground = $Global:SuiteColors.StatusOK
        [System.Windows.MessageBox]::Show('Einzel-Einstellungen angewendet.', 'Grafik', 'OK', 'Information') | Out-Null
    } else {
        $Global:LastGfxInfo = "Einzel-Apply fehlgeschlagen ($ts) - siehe Logs (Settings-Tab)."
        $ctrls.lblGfxCustomInfo.Text = "Fehlgeschlagen ($ts) - $($res.Message)."
        $ctrls.lblGfxCustomInfo.Foreground = $Global:SuiteColors.StatusError
        [System.Windows.MessageBox]::Show("Anwenden fehlgeschlagen:`n`n$($res.Message)`n`nDetails: Logs im Settings-Tab.", 'Grafik', 'OK', 'Warning') | Out-Null
    }
    Update-GraphicsTab
})

# ==================== CAPTURE TAB ====================
$Global:CaptureState = @{
    IsRunning = $false
    Timer = $null
    Process = $null
    OutputCsv = ''
    SecondsRemaining = 0
    Phase = 'idle'    # idle / countdown / capturing / analyzing
    LastResult = $null
}

function Update-CapToolStatus {
    $pm = Get-PresentMonPath
    if ($pm) {
        $ctrls.lblCapToolStatus.Text = "installiert ($([System.IO.Path]::GetFileName($pm)))"
        $ctrls.lblCapToolStatus.Foreground = $Global:SuiteColors.StatusOK
    } else {
        $ctrls.lblCapToolStatus.Text = 'NICHT installiert - wird beim Start automatisch geladen'
        $ctrls.lblCapToolStatus.Foreground = $Global:SuiteColors.StatusWarn
    }
}

function Show-CapResult {
    param($Result)
    if (-not $Result -or $Result.Error) {
        if ($Result -and $Result.Aborted) {
            # Benigner Abbruch (zu wenige Frames) - WARN-Ton, kein roter Fehler.
            $ctrls.lblCapLastInfo.Text = [string]$Result.Error
            $ctrls.lblCapLastInfo.Foreground = $Global:SuiteColors.StatusWarn
        } else {
            $errMsg = if ($Result) { $Result.Error } else { 'unbekannt' }
            $ctrls.lblCapLastInfo.Text = "Fehler: $errMsg"
            $ctrls.lblCapLastInfo.Foreground = $Global:SuiteColors.StatusError
        }
        $ctrls.capResultGrid.Visibility = 'Collapsed'
        return
    }
    $timeStr = if ($Result.CaptureTime -is [datetime]) { $Result.CaptureTime.ToString('yyyy-MM-dd HH:mm:ss') } else { [string]$Result.CaptureTime }
    $ctrls.lblCapLastInfo.Text = "$timeStr  -  $($Result.Frames) Frames in $($Result.DurationSec)s  -  $($Result.FileName)"
    $ctrls.lblCapLastInfo.Foreground = $Global:SuiteColors.TextSecondary
    $ctrls.capResultGrid.Visibility = 'Visible'

    $ctrls.lblCapAvg.Text = $Result.AvgFps
    $ctrls.lblCap1Low.Text = $Result.OnePctLow
    $ctrls.lblCap01Low.Text = $Result.ZeroOnePctLow
    $ctrls.lblCapStdDev.Text = "$($Result.StdDevMs) ms"
    # Stability-Sub-Label (Score-Bewertung)
    if ($null -ne $Result.StabilityScore) {
        $score = [double]$Result.StabilityScore
        $stabTxt = if ($score -ge 95) { "Stability $score% (sehr ruhig)" }
                   elseif ($score -ge 90) { "Stability $score% (ok)" }
                   elseif ($score -ge 80) { "Stability $score% (sichtbare Schwankung)" }
                   else { "Stability $score% (unrund)" }
        $ctrls.lblCapStability.Text = $stabTxt
    } else {
        $ctrls.lblCapStability.Text = ''
    }

    # Present Mode (Hauptzeile - voller Name) + Erklaerung darunter
    # Strip "Mode "-Praefix falls aus alter History (hardcoded vor 0.10.1)
    $modeLbl = if ($Result.PresentModeLabel) { [string]$Result.PresentModeLabel } else { 'unbekannt' }
    $modeLbl = $modeLbl -replace '^Mode\s+',''
    # BEST-Modi bekommen "OPTIMAL"-Praefix visualisiert
    $displayLbl = switch ($Result.PresentModeQuality) {
        'BEST' { "$modeLbl    ✓ OPTIMAL" }
        default { $modeLbl }
    }
    $ctrls.lblCapPresentMode.Text = $displayLbl
    $modeColor = switch ($Result.PresentModeQuality) {
        'BEST' { $Global:SuiteColors.StatusBest }   # knalliges Gruen (Bestnote)
        'OK'   { $Global:SuiteColors.StatusOK }   # normales Gruen
        'WARN' { $Global:SuiteColors.StatusWarn }
        'BAD'  { $Global:SuiteColors.StatusError }
        default{ $Global:SuiteColors.TextPrimary }
    }
    $ctrls.lblCapPresentMode.Foreground = $modeColor
    # Erklaerungstext in passender Severity-Farbe (BEST/OK gruen-ish, sonst normal grau)
    $ctrls.lblCapPresentExplain.Text = if ($Result.PresentModeExplain) { $Result.PresentModeExplain } else { '' }
    $ctrls.lblCapPresentExplain.Foreground = switch ($Result.PresentModeQuality) {
        'BEST' { $Global:SuiteColors.StatusOK }
        'OK'   { $Global:SuiteColors.StatusOK }
        'WARN' { $Global:SuiteColors.StatusWarn }
        'BAD'  { $Global:SuiteColors.StatusError }
        default{ $Global:SuiteColors.TextSecondary }
    }

    # Bottleneck mit Farbcode
    if ($Result.Bottleneck) {
        $ctrls.lblCapBottleneck.Text = $Result.Bottleneck
        $ctrls.lblCapBottleneck.Foreground = switch ($Result.Bottleneck) {
            'Balanced'   { $Global:SuiteColors.StatusOK }
            'GPU-Bound'  { $Global:SuiteColors.StatusWarn }
            'CPU-Bound'  { $Global:SuiteColors.StatusWarn }
            default      { $Global:SuiteColors.TextSecondary }
        }
    } else {
        $ctrls.lblCapBottleneck.Text = '-'
        $ctrls.lblCapBottleneck.Foreground = $Global:SuiteColors.TextSecondary
    }

    # CPU/GPU Busy Werte
    $ctrls.lblCapCpuBusy.Text = if ($null -ne $Result.CpuBusyMs) { "$($Result.CpuBusyMs) ms" } else { 'NA' }
    $ctrls.lblCapGpuBusy.Text = if ($null -ne $Result.GpuBusyMs) { "$($Result.GpuBusyMs) ms" } else { 'NA' }
    # Hoeherer Wert in gelb, anderer neutral
    if ($null -ne $Result.CpuBusyMs -and $null -ne $Result.GpuBusyMs) {
        if ($Result.CpuBusyMs -gt $Result.GpuBusyMs) {
            $ctrls.lblCapCpuBusy.Foreground = $Global:SuiteColors.StatusWarn
            $ctrls.lblCapGpuBusy.Foreground = $Global:SuiteColors.TextPrimary
        } elseif ($Result.GpuBusyMs -gt $Result.CpuBusyMs) {
            $ctrls.lblCapGpuBusy.Foreground = $Global:SuiteColors.StatusWarn
            $ctrls.lblCapCpuBusy.Foreground = $Global:SuiteColors.TextPrimary
        } else {
            $ctrls.lblCapCpuBusy.Foreground = $Global:SuiteColors.TextPrimary
            $ctrls.lblCapGpuBusy.Foreground = $Global:SuiteColors.TextPrimary
        }
    } else {
        $ctrls.lblCapCpuBusy.Foreground = $Global:SuiteColors.TextSecondary
        $ctrls.lblCapGpuBusy.Foreground = $Global:SuiteColors.TextSecondary
    }

    # Render Latency + Until Displayed + Click-to-Photon
    $ctrls.lblCapRenderLat.Text = if ($null -ne $Result.RenderLatencyMs) { "$($Result.RenderLatencyMs) ms" } else { 'NA' }
    $ctrls.lblCapRenderLat.Foreground = if ($null -ne $Result.RenderLatencyMs) {
        if ($Result.RenderLatencyMs -lt 8) { $Global:SuiteColors.StatusOK }
        elseif ($Result.RenderLatencyMs -lt 16) { $Global:SuiteColors.StatusWarn }
        else { $Global:SuiteColors.StatusError }
    } else { $Global:SuiteColors.TextSecondary }

    $ctrls.lblCapUntilDisp.Text = if ($null -ne $Result.UntilDisplayedMs) { "$($Result.UntilDisplayedMs) ms" } else { 'NA' }
    $ctrls.lblCapUntilDisp.Foreground = if ($null -ne $Result.UntilDisplayedMs) { $Global:SuiteColors.TextPrimary } else { $Global:SuiteColors.TextSecondary }

    $ctrls.lblCapClickPhoton.Text = if ($null -ne $Result.ClickToPhotonMs) { "$($Result.ClickToPhotonMs) ms" } else { 'NA' }
    $ctrls.lblCapClickPhoton.Foreground = if ($null -ne $Result.ClickToPhotonMs) { $Global:SuiteColors.TextPrimary } else { $Global:SuiteColors.TextDisabled }

    if ($Result.GSyncActive) {
        $ctrls.lblCapGSync.Text = 'AKTIV'
        $ctrls.lblCapGSync.Foreground = $Global:SuiteColors.StatusOK
    } else {
        $ctrls.lblCapGSync.Text = 'inaktiv'
        $ctrls.lblCapGSync.Foreground = $Global:SuiteColors.TextSecondary
    }

    $ctrls.lblCapStutter.Text = "$($Result.StutterPct)%"
    $ctrls.lblCapStutter.Foreground = if ($Result.StutterPct -lt 0.2) { $Global:SuiteColors.StatusOK } elseif ($Result.StutterPct -lt 0.5) { $Global:SuiteColors.StatusWarn } else { $Global:SuiteColors.StatusError }
}

function Format-CapTimeShort {
    param($Val)
    # Robuste Konvertierung egal ob String oder DateTime (PowerShell-JSON-Quirks)
    if ($null -eq $Val) { return '?' }
    $s = if ($Val -is [datetime]) {
        $Val.ToString('yyyy-MM-dd HH:mm:ss')
    } else {
        [string]$Val
    }
    if ($s.Length -ge 16) {
        return $s.Substring(5, 11)  # "MM-dd HH:mm"
    }
    return $s
}

function Update-CapHistory {
    try {
        $ctrls.capHistoryList.Children.Clear()
        $hist = @(Get-CaptureHistory)
        if ($hist.Count -eq 0) {
            $ctrls.lblCapHistInfo.Text = 'Keine Trend-Daten - mache mind. 2 Messungen zum Vergleich.'
            return
        }
        $ctrls.lblCapHistInfo.Text = "$($hist.Count) Messung(en) gespeichert - Top 8 angezeigt. Klick auf eine Zeile = CSV oeffnen."

        # Header-Row - Spalten: Date(110), Avg(55), 1%(55), 0.1%(55), StdDev(55), Mode(200), Delta(70)
        $colWidths = @(110,55,55,55,55,200,70)
        $hdr = New-Object System.Windows.Controls.Border
        $hdr.Background = $Global:SuiteColors.BgBase; $hdr.Padding = (New-Object System.Windows.Thickness 8,4,8,4)
        $hdr.Margin = (New-Object System.Windows.Thickness 0,0,0,2)
        $hdrGrid = New-Object System.Windows.Controls.Grid
        $hdr.Child = $hdrGrid
        foreach ($w in $colWidths) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            $cd.Width = $w; $hdrGrid.ColumnDefinitions.Add($cd) | Out-Null
        }
        $hdrTexts = @('DATE/TIME','AVG','1%','0.1%','STDEV','MODE','DELTA')
        for ($i = 0; $i -lt $hdrTexts.Count; $i++) {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $hdrTexts[$i]; $tb.Foreground = $Global:SuiteColors.TextSecondary; $tb.FontSize = 10; $tb.FontWeight = 'SemiBold'
            [System.Windows.Controls.Grid]::SetColumn($tb, $i)
            $hdrGrid.Children.Add($tb) | Out-Null
        }
        $ctrls.capHistoryList.Children.Add($hdr) | Out-Null

        # Letzte 8, neueste zuerst (Display)
        $recent = @($hist | Select-Object -Last 8)
        # Sortieren ueber CaptureTime - tolerant gegen String/DateTime
        $recent = @($recent | Sort-Object -Property @{ Expression = {
            try {
                if ($_.CaptureTime -is [datetime]) { $_.CaptureTime } else { [datetime]::Parse($_.CaptureTime) }
            } catch { [datetime]::MinValue }
        }} -Descending)

        # Baseline = aelteste der angezeigten (letzter Eintrag nach Sortierung)
        $baseline = $recent[-1]
        $baselineAvg = if ($baseline -and $null -ne $baseline.AvgFps) { [double]$baseline.AvgFps } else { 0 }

        foreach ($e in $recent) {
            try {
                $row = New-Object System.Windows.Controls.Border
                $row.Background = $Global:SuiteColors.Surface1; $row.Padding = (New-Object System.Windows.Thickness 8,4,8,4)
                $row.Margin = (New-Object System.Windows.Thickness 0,1,0,0)
                $row.CornerRadius = (New-Object System.Windows.CornerRadius 2)
                $row.Cursor = [System.Windows.Input.Cursors]::Hand
                $row.Tag = $e.CsvPath

                $grid = New-Object System.Windows.Controls.Grid
                $row.Child = $grid
                foreach ($w in $colWidths) {
                    $cd = New-Object System.Windows.Controls.ColumnDefinition
                    $cd.Width = $w; $grid.ColumnDefinitions.Add($cd) | Out-Null
                }

                # Delta vs Baseline berechnen
                $delta = ''; $deltaColor = $Global:SuiteColors.TextSecondary
                if ($baselineAvg -gt 0 -and $null -ne $e.AvgFps -and $e -ne $baseline) {
                    $diff = [double]$e.AvgFps - $baselineAvg
                    $sign = if ($diff -ge 0) { '+' } else { '' }
                    $delta = "$sign$([math]::Round($diff, 1))"
                    if ($diff -gt 2) { $deltaColor = $Global:SuiteColors.StatusOK }
                    elseif ($diff -lt -2) { $deltaColor = $Global:SuiteColors.StatusError }
                    else { $deltaColor = $Global:SuiteColors.StatusWarn }
                }

                # Mode-Label: PresentMon v2 schreibt schon Strings wie "Hardware: Legacy Flip".
                # Alte History-Eintraege koennten "Mode " hardcoded davor haben - kuerze das raus.
                $modeStr = if ($e.PresentModeLabel) { [string]$e.PresentModeLabel }
                           elseif ($e.PresentMode) { [string]$e.PresentMode }
                           else { '?' }
                $modeStr = $modeStr -replace '^Mode\s+',''
                # Mode-Farbe nach Quality (BEST=knall-gruen, OK=gruen, WARN=gelb, BAD=rot)
                $modeColor = switch -Wildcard ($modeStr) {
                    '*Independent Flip*'  { $Global:SuiteColors.StatusBest }
                    '*Legacy Flip*'       { $Global:SuiteColors.StatusBest }
                    '*Composed Flip*'     { $Global:SuiteColors.StatusOK }
                    '*Legacy Copy*'       { $Global:SuiteColors.StatusOK }
                    '*Composed Copy*'     { $Global:SuiteColors.StatusError }
                    '*Composition Atlas*' { $Global:SuiteColors.StatusWarn }
                    default               { $Global:SuiteColors.TextPrimary }
                }
                $vals = @(
                    (Format-CapTimeShort $e.CaptureTime),
                    "$($e.AvgFps)",
                    "$($e.OnePctLow)",
                    "$($e.ZeroOnePctLow)",
                    "$($e.StdDevMs)",
                    $modeStr,
                    $delta
                )
                $cols = @($Global:SuiteColors.TextPrimary,$Global:SuiteColors.StatusOK,$Global:SuiteColors.StatusWarn,$Global:SuiteColors.StatusError,$Global:SuiteColors.Accent,$modeColor,$deltaColor)
                for ($i = 0; $i -lt 7; $i++) {
                    $tb = New-Object System.Windows.Controls.TextBlock
                    $tb.Text = "$($vals[$i])"; $tb.Foreground = $cols[$i]; $tb.FontSize = 11
                    $tb.FontFamily = (New-Object System.Windows.Media.FontFamily 'Consolas')
                    [System.Windows.Controls.Grid]::SetColumn($tb, $i)
                    $grid.Children.Add($tb) | Out-Null
                }

                # Click-Handler: oeffnet CSV der Row
                $row.Add_MouseLeftButtonUp({
                    $csvPath = $this.Tag
                    if ($csvPath -and (Test-Path $csvPath)) {
                        Start-Process notepad.exe -ArgumentList $csvPath
                    } else {
                        [System.Windows.MessageBox]::Show("CSV nicht mehr vorhanden:`n$csvPath", 'Info', 'OK', 'Warning') | Out-Null
                    }
                })

                # Hover-Effekt
                $row.Add_MouseEnter({ $this.Background = $Global:SuiteColors.Surface2 })
                $row.Add_MouseLeave({ $this.Background = $Global:SuiteColors.Surface1 })

                $ctrls.capHistoryList.Children.Add($row) | Out-Null
            } catch {
                Write-SuiteLog "Update-CapHistory Row-Render Fehler: $($_.Exception.Message)" 'WARN'
            }
        }
    } catch {
        Write-SuiteLog "Update-CapHistory Fehler: $($_.Exception.Message)" 'ERROR'
    }
}

function Stop-CaptureTimer {
    if ($Global:CaptureState.Timer) {
        try { $Global:CaptureState.Timer.Stop() } catch {}  # Timer evtl. schon gestoppt - unkritisch
        $Global:CaptureState.Timer = $null
    }
}

function Cleanup-CapState {
    Stop-CaptureTimer
    # Process-Null-Guard - HasExited Access auf $null wirft Exception
    if ($Global:CaptureState.Process) {
        try {
            if (-not $Global:CaptureState.Process.HasExited) {
                $Global:CaptureState.Process.Kill()
            }
        } catch {
            Write-SuiteLog "Cleanup-CapState: Process kill fehler $($_.Exception.Message)" 'WARN'
        }
    }
    $Global:CaptureState.Process = $null
    $Global:CaptureState.IsRunning = $false
    $Global:CaptureState.Phase = 'idle'
    if ($ctrls.btnCapStart) { $ctrls.btnCapStart.IsEnabled = $true }
    if ($ctrls.btnCapStop) { $ctrls.btnCapStop.IsEnabled = $false }
}

function Start-PUBGCapture {
    if ($Global:CaptureState.IsRunning) { return }

    # PresentMon vorhanden?
    $pm = Get-PresentMonPath
    if (-not $pm) {
        $ctrls.lblCapPhase.Text = 'PresentMon nicht installiert - lade von GitHub...'
        $ctrls.lblCapPhase.Foreground = $Global:SuiteColors.StatusWarn
        Write-SuiteLog "PresentMon nicht gefunden - starte Auto-Install" 'INFO'
        $pm = Install-PresentMonFromGitHub
        Update-CapToolStatus
        if (-not $pm) {
            $ctrls.lblCapPhase.Text = 'PresentMon-Install fehlgeschlagen - Logs pruefen'
            $ctrls.lblCapPhase.Foreground = $Global:SuiteColors.StatusError
            return
        }
    }

    # PUBG laeuft?
    $pubg = @(Get-Process -Name 'TslGame' -ErrorAction SilentlyContinue)
    if ($pubg.Count -eq 0) {
        $ctrls.lblCapPhase.Text = 'PUBG (TslGame.exe) laeuft nicht - erst Spiel starten + ins Match'
        $ctrls.lblCapPhase.Foreground = $Global:SuiteColors.StatusError
        return
    }

    Initialize-SuiteStorage
    $ts = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $outCsv = Join-Path $Global:Suite.CaptureDir "capture_$ts.csv"
    $Global:CaptureState.OutputCsv = $outCsv
    $Global:CaptureState.IsRunning = $true
    $Global:CaptureState.SecondsRemaining = 10
    $Global:CaptureState.Phase = 'countdown'

    $ctrls.btnCapStart.IsEnabled = $false
    $ctrls.btnCapStop.IsEnabled = $true

    Write-SuiteLog "Capture-Start: PresentMon=$pm, Output=$outCsv" 'INFO'

    # DispatcherTimer (Tick alle 1s) - laeuft im UI-Thread, blockt nichts
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(1)
    $script:capPm = $pm
    $script:capOutCsv = $outCsv

    $timer.Add_Tick({
        try {
            $state = $Global:CaptureState
            if (-not $state -or -not $state.IsRunning) { return }
            if ($state.Phase -eq 'countdown') {
                if ($state.SecondsRemaining -gt 0) {
                    $ctrls.lblCapPhase.Text = "Capture startet in $($state.SecondsRemaining)s - jetzt Alt+Tab zu PUBG!"
                    $ctrls.lblCapPhase.Foreground = $Global:SuiteColors.StatusWarn
                    $state.SecondsRemaining--
                } else {
                    # Switch zu capturing
                    $state.Phase = 'capturing'
                    $state.SecondsRemaining = 60
                    # Rename von $args (PowerShell-Automatic-Variable Shadowing!) zu $pmArgs
                    $pmArgs = @('-process_name','TslGame.exe','-timed','60','-terminate_after_timed','-output_file',$script:capOutCsv)
                    try {
                        $proc = Start-Process -FilePath $script:capPm -ArgumentList $pmArgs -WindowStyle Hidden -PassThru -ErrorAction Stop
                        if (-not $proc) {
                            throw 'Start-Process gab keine Prozess-Referenz zurueck (PassThru fehlgeschlagen)'
                        }
                        $state.Process = $proc
                        $ctrls.lblCapPhase.Text = "Capturing 60s - in PUBG normal spielen"
                        $ctrls.lblCapPhase.Foreground = $Global:SuiteColors.StatusOK
                        Write-SuiteLog "PresentMon gestartet PID $($proc.Id)"
                    } catch {
                        $ctrls.lblCapPhase.Text = "Fehler beim PresentMon-Start: $($_.Exception.Message)"
                        $ctrls.lblCapPhase.Foreground = $Global:SuiteColors.StatusError
                        Write-SuiteLog "PresentMon-Start Fehler: $($_.Exception.Message)" 'ERROR'
                        Cleanup-CapState
                        return
                    }
                }
            } elseif ($state.Phase -eq 'capturing') {
                if ($state.SecondsRemaining -gt 0) {
                    $ctrls.lblCapPhase.Text = "Capturing... verbleibend $($state.SecondsRemaining)s"
                    $state.SecondsRemaining--
                }
                # Pruefen ob Prozess fertig
                if ($state.Process -and $state.Process.HasExited) {
                    $state.Phase = 'analyzing'
                    $ctrls.lblCapPhase.Text = 'Analyse...'
                    $ctrls.lblCapPhase.Foreground = $Global:SuiteColors.Accent
                }
            } elseif ($state.Phase -eq 'analyzing') {
                Stop-CaptureTimer
                # CSV analysieren. -not $result faengt einen unerwarteten $null-
                # Rueckgabewert ab, damit kein null-Ergebnis als Erfolg durchrutscht.
                $result = Analyze-CaptureCSV -CsvPath $state.OutputCsv
                if (-not $result -or $result.Error) {
                    $errTxt = if ($result -and $result.Error) { $result.Error } else { 'Analyse lieferte kein Ergebnis' }
                    $aborted = [bool]($result -and $result.Aborted)
                    Show-CapResult $result   # zeigt die Meldung in 'Letzte Messung'
                    # Bug #5: ein zu kurzer Capture ist ein Abbruch (WARN), kein
                    # Fehler - und wird NICHT in die History geschrieben (kein
                    # Add-CaptureEntry hier), damit kein leerer Slot im Trend landet.
                    if ($aborted) {
                        $ctrls.lblCapPhase.Text = $errTxt
                        $ctrls.lblCapPhase.Foreground = $Global:SuiteColors.StatusWarn
                        Write-SuiteLog "Capture abgebrochen: $errTxt" 'WARN'
                    } else {
                        $ctrls.lblCapPhase.Text = "Analyse-Fehler: $errTxt"
                        $ctrls.lblCapPhase.Foreground = $Global:SuiteColors.StatusError
                        Write-SuiteLog "Capture Analyse Fehler: $errTxt" 'ERROR'
                    }
                } else {
                    Show-CapResult $result
                    Add-CaptureEntry $result
                    Update-CapHistory
                    $ctrls.lblCapPhase.Text = "Fertig - $($result.Frames) Frames erfasst, AvgFps $($result.AvgFps)"
                    $ctrls.lblCapPhase.Foreground = $Global:SuiteColors.StatusOK
                    Write-SuiteLog "Capture fertig: AvgFps=$($result.AvgFps) 1%=$($result.OnePctLow) Mode=$($result.PresentMode)"
                    $Global:CaptureState.LastResult = $result
                }
                Cleanup-CapState
            }
        } catch {
            Write-SuiteLog "Capture-Timer Fehler: $($_.Exception.Message)" 'ERROR'
            $ctrls.lblCapPhase.Text = "Timer-Fehler: $($_.Exception.Message)"
            $ctrls.lblCapPhase.Foreground = $Global:SuiteColors.StatusError
            Cleanup-CapState
        }
    })
    $Global:CaptureState.Timer = $timer
    $timer.Start()
}

$ctrls.btnCapStart.Add_Click({ Start-PUBGCapture })
$ctrls.btnCapStop.Add_Click({
    Write-SuiteLog "Capture manuell abgebrochen" 'WARN'
    $ctrls.lblCapPhase.Text = 'Abgebrochen.'
    $ctrls.lblCapPhase.Foreground = $Global:SuiteColors.StatusWarn
    Cleanup-CapState
})
$ctrls.btnCapOpenCsv.Add_Click({
    if ($Global:CaptureState.LastResult -and (Test-Path $Global:CaptureState.LastResult.CsvPath)) {
        Start-Process notepad.exe -ArgumentList $Global:CaptureState.LastResult.CsvPath
    } else {
        # Letzte CSV aus History
        $hist = @(Get-CaptureHistory)
        if ($hist.Count -gt 0 -and (Test-Path $hist[-1].CsvPath)) {
            Start-Process notepad.exe -ArgumentList $hist[-1].CsvPath
        } else {
            [System.Windows.MessageBox]::Show('Noch keine Capture-Datei vorhanden.','Info','OK','Information') | Out-Null
        }
    }
})
$ctrls.btnCapOpenFolder.Add_Click({
    Initialize-SuiteStorage
    Start-Process explorer.exe -ArgumentList $Global:Suite.CaptureDir
})

function Format-Delta {
    param([double]$Current, [double]$Previous, [string]$Unit = '', [bool]$LowerIsBetter = $false)
    if ($Previous -eq 0) { return '' }
    $diff = $Current - $Previous
    $pct = if ($Previous -ne 0) { ($diff / $Previous) * 100 } else { 0 }
    $sign = if ($diff -ge 0) { '+' } else { '' }
    $diffStr = "$sign$([math]::Round($diff, 1))$Unit"
    $pctStr = "($sign$([math]::Round($pct, 1))%)"
    $isPositive = if ($LowerIsBetter) { $diff -lt 0 } else { $diff -gt 0 }
    $color = if ([math]::Abs($pct) -lt 1) { $Global:SuiteColors.TextSecondary } elseif ($isPositive) { $Global:SuiteColors.StatusOK } else { $Global:SuiteColors.StatusError }
    return @{ Text = "$diffStr $pctStr"; Color = $color }
}

# Baut die In-Tab-Vergleichsansicht (Card capCompareCard) aus zwei Messungen.
# Loest die fruehere MessageBox ab - gleiche Metriken, aber als farbcodierte
# Tabelle im Tab statt als modaler Dialog.
function Show-CapCompare {
    param($Current, $Previous)
    $ctrls.capCompareList.Children.Clear()

    $curTime  = Format-CapTimeShort $Current.CaptureTime
    $prevTime = Format-CapTimeShort $Previous.CaptureTime
    $ctrls.lblCapCompareInfo.Text = "$prevTime  ->  $curTime      gruene Delta = Verbesserung, rote = Verschlechterung"

    # Spalten: Metrik(150) | Vorher(95) | Nachher(95) | Delta(190)
    $colWidths = @(150,95,95,190)

    # Header-Row
    $hdr = New-Object System.Windows.Controls.Border
    $hdr.Background = $Global:SuiteColors.BgBase
    $hdr.Padding = (New-Object System.Windows.Thickness 8,4,8,4)
    $hdr.Margin = (New-Object System.Windows.Thickness 0,0,0,2)
    $hdrGrid = New-Object System.Windows.Controls.Grid
    $hdr.Child = $hdrGrid
    foreach ($w in $colWidths) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = $w; $hdrGrid.ColumnDefinitions.Add($cd) | Out-Null
    }
    $hdrTexts = @('METRIK','VORHER','NACHHER','DELTA')
    for ($i = 0; $i -lt $hdrTexts.Count; $i++) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $hdrTexts[$i]; $tb.Foreground = $Global:SuiteColors.TextSecondary
        $tb.FontSize = 10; $tb.FontWeight = 'SemiBold'
        [System.Windows.Controls.Grid]::SetColumn($tb, $i)
        $hdrGrid.Children.Add($tb) | Out-Null
    }
    $ctrls.capCompareList.Children.Add($hdr) | Out-Null

    # Metrik-Definitionen: Label, Property-Name, Einheit, LowerIsBetter
    $metrics = @(
        @{ Label='AVG FPS';  Prop='AvgFps';        Unit='';    Lower=$false }
        @{ Label='1% Low';   Prop='OnePctLow';     Unit='';    Lower=$false }
        @{ Label='0.1% Low'; Prop='ZeroOnePctLow'; Unit='';    Lower=$false }
        @{ Label='StdDev';   Prop='StdDevMs';      Unit=' ms'; Lower=$true }
        @{ Label='Stutter';  Prop='StutterPct';    Unit=' %';  Lower=$true }
    )
    foreach ($m in $metrics) {
        $prevVal = $Previous.($m.Prop)
        $curVal  = $Current.($m.Prop)
        $delta = Format-Delta -Current ([double]$curVal) -Previous ([double]$prevVal) -Unit $m.Unit -LowerIsBetter $m.Lower

        $row = New-Object System.Windows.Controls.Border
        $row.Background = $Global:SuiteColors.Surface1
        $row.Padding = (New-Object System.Windows.Thickness 8,5,8,5)
        $row.Margin = (New-Object System.Windows.Thickness 0,1,0,0)
        $row.CornerRadius = (New-Object System.Windows.CornerRadius 2)
        $grid = New-Object System.Windows.Controls.Grid
        $row.Child = $grid
        foreach ($w in $colWidths) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            $cd.Width = $w; $grid.ColumnDefinitions.Add($cd) | Out-Null
        }
        $deltaText  = if ($delta) { $delta.Text }  else { '-' }
        $deltaColor = if ($delta) { $delta.Color } else { $Global:SuiteColors.TextSecondary }
        $vals    = @("$($m.Label)", "$prevVal$($m.Unit)", "$curVal$($m.Unit)", $deltaText)
        $cols    = @($Global:SuiteColors.TextSecondary, $Global:SuiteColors.TextPrimary, $Global:SuiteColors.TextPrimary, $deltaColor)
        $weights = @('Normal','Normal','SemiBold','SemiBold')
        for ($i = 0; $i -lt 4; $i++) {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = "$($vals[$i])"; $tb.Foreground = $cols[$i]; $tb.FontSize = 12
            $tb.FontWeight = $weights[$i]
            $tb.FontFamily = (New-Object System.Windows.Media.FontFamily 'Consolas')
            [System.Windows.Controls.Grid]::SetColumn($tb, $i)
            $grid.Children.Add($tb) | Out-Null
        }
        $ctrls.capCompareList.Children.Add($row) | Out-Null
    }

    # Present-Mode-Zeile (volle Breite) - Mode ist kategorisch, kein Delta
    $prevMode = if ($Previous.PresentModeLabel) { [string]$Previous.PresentModeLabel } elseif ($Previous.PresentMode) { [string]$Previous.PresentMode } else { '?' }
    $curMode  = if ($Current.PresentModeLabel)  { [string]$Current.PresentModeLabel }  elseif ($Current.PresentMode)  { [string]$Current.PresentMode }  else { '?' }
    $prevMode = $prevMode -replace '^Mode\s+',''
    $curMode  = $curMode  -replace '^Mode\s+',''
    $modeRow = New-Object System.Windows.Controls.Border
    $modeRow.Background = $Global:SuiteColors.Surface1
    $modeRow.Padding = (New-Object System.Windows.Thickness 8,5,8,5)
    $modeRow.Margin = (New-Object System.Windows.Thickness 0,1,0,0)
    $modeRow.CornerRadius = (New-Object System.Windows.CornerRadius 2)
    $modeTb = New-Object System.Windows.Controls.TextBlock
    $modeTb.FontSize = 12; $modeTb.TextWrapping = 'Wrap'
    if ($prevMode -eq $curMode) {
        $modeTb.Text = "Present Mode:  $curMode  (unveraendert)"
        $modeTb.Foreground = $Global:SuiteColors.TextSecondary
    } else {
        $modeTb.Text = "Present Mode geaendert:  $prevMode  ->  $curMode"
        $modeTb.Foreground = $Global:SuiteColors.StatusWarn
    }
    $modeRow.Child = $modeTb
    $ctrls.capCompareList.Children.Add($modeRow) | Out-Null

    $ctrls.capCompareCard.Visibility = 'Visible'
}

$ctrls.btnCapCompare.Add_Click({
    $hist = @(Get-CaptureHistory)
    if ($hist.Count -lt 2) {
        [System.Windows.MessageBox]::Show('Mindestens 2 Messungen noetig fuer Vergleich. Aktuell vorhanden: ' + $hist.Count, 'Compare', 'OK', 'Information') | Out-Null
        return
    }
    Show-CapCompare -Current $hist[-1] -Previous $hist[-2]
    $ctrls.capCompareCard.BringIntoView()
})

$ctrls.btnCapCompareClose.Add_Click({
    $ctrls.capCompareCard.Visibility = 'Collapsed'
})

$ctrls.btnCapRebuild.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show("Rebuilds captures.json aus allen CSV-Dateien im Captures-Ordner.`n`nNuetzlich falls die History inkonsistent wurde (z.B. durch alten JSON-Serialisierungs-Bug).", 'Rebuild History', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }
    $count = Rebuild-CaptureHistoryFromCsv
    Update-CapHistory
    [System.Windows.MessageBox]::Show("Rebuild fertig: $count Eintraege aus CSV-Dateien wiederhergestellt.", 'Rebuild', 'OK', 'Information') | Out-Null
})

$ctrls.btnCapClearHist.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show("Capture-History komplett loeschen?`n`nCSV-Dateien in $($Global:Suite.CaptureDir) bleiben erhalten - nur die Trend-Daten werden gecleared.", 'History loeschen', 'YesNo', 'Warning')
    if ($confirm -eq 'Yes') {
        Remove-Item $Global:Suite.CapturesFile -Force -ErrorAction SilentlyContinue
        Write-SuiteLog "Capture-History geloescht" 'INFO'
        Update-CapHistory
        $ctrls.capResultGrid.Visibility = 'Collapsed'
        $ctrls.capCompareCard.Visibility = 'Collapsed'
        $ctrls.lblCapLastInfo.Text = 'History geloescht.'
        $ctrls.lblCapLastInfo.Foreground = $Global:SuiteColors.TextSecondary
    }
})

Update-CapToolStatus
Update-CapHistory
# Beim Start: letztes Ergebnis anzeigen. Wenn die CSV noch existiert, neu analysieren
# (alte History-Eintraege haben keine Bottleneck/CpuBusy/GpuBusy/RenderLat-Felder).
$hist = @(Get-CaptureHistory)
if ($hist.Count -gt 0) {
    $lastEntry = $hist[-1]
    $freshResult = $null
    if ($lastEntry.CsvPath -and (Test-Path $lastEntry.CsvPath)) {
        try { $freshResult = Analyze-CaptureCSV -CsvPath $lastEntry.CsvPath }
        catch { Write-SuiteLog "Capture-History: Re-Analyse fehlgeschlagen ($($_.Exception.Message)) - nutze gespeicherten Eintrag" 'WARN' }
    }
    $displayResult = if ($freshResult -and -not $freshResult.Error) { $freshResult } else { $lastEntry }
    $Global:CaptureState.LastResult = $displayResult
    Show-CapResult $displayResult
}

# ==================== KEY GEN (Retro-Spass-Tab) ====================
# Reine Deko - generiert funktionslose Zufalls-Codes und spielt eine 8-bit-
# Loop-Melodie via [Console]::Beep. Hommage an die alten Szene-Keygens.
$Global:KeygenState   = @{ Groups = 4; Len = 6; RollTimer = $null }
$Global:KeygenRandom  = New-Object System.Random
$Global:KeygenCharset = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()
# Thread-uebergreifend geteilter Musik-Zustand (synchronized -> sicher zwischen
# UI-Thread und Audio-Runspace).
$Global:KeygenAudio = [hashtable]::Synchronized(@{ Running = $false; PowerShell = $null })

# Erzeugt einen dekorativen Code: $Groups Gruppen je $Len Zeichen, '-'-getrennt.
function New-KeygenCode {
    param([int]$Groups, [int]$Len)
    $parts = for ($g = 0; $g -lt $Groups; $g++) {
        $chars = for ($i = 0; $i -lt $Len; $i++) {
            $Global:KeygenCharset[$Global:KeygenRandom.Next(0, $Global:KeygenCharset.Length)]
        }
        -join $chars
    }
    return ($parts -join '-')
}

# Kurze "Roll"-Animation (Code rattert), dann settle auf den finalen Code.
function Invoke-KeygenGenerate {
    if ($Global:KeygenState.RollTimer) { $Global:KeygenState.RollTimer.Stop() }
    $ctrls.lblKeygenStatus.Text = 'GENERIERE SCHLUESSEL ...'
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(45)
    $timer.Tag = 0
    $timer.Add_Tick({
        $this.Tag = [int]$this.Tag + 1
        $ctrls.lblKeygenCode.Text = New-KeygenCode -Groups $Global:KeygenState.Groups -Len $Global:KeygenState.Len
        if ([int]$this.Tag -ge 12) {
            $this.Stop()
            $ctrls.lblKeygenStatus.Text = "LIZENZSCHLUESSEL GENERIERT  -  $(Get-Date -Format 'HH:mm:ss')  -  STATUS: GUELTIG"
        }
    })
    $Global:KeygenState.RollTimer = $timer
    $timer.Start()
}

# Startet die 8-bit-Loop-Melodie in einem Hintergrund-Runspace. [Console]::Beep
# blockiert - darf darum nie den UI-Thread treffen. Fehler-tolerant: schlaegt
# der Start fehl, bleibt der Tab trotzdem voll bedienbar (nur eben stumm).
function Start-KeygenMusic {
    if ($Global:KeygenAudio.Running) { return }
    try {
        # alten (beendeten) Runspace aufraeumen, falls vorhanden
        if ($Global:KeygenAudio.PowerShell) {
            try { $Global:KeygenAudio.PowerShell.Dispose() } catch {}  # bereits beendet - egal
            $Global:KeygenAudio.PowerShell = $null
        }
        $Global:KeygenAudio.Running = $true
        $rs = [RunspaceFactory]::CreateRunspace()
        $rs.Open()
        $rs.SessionStateProxy.SetVariable('Audio', $Global:KeygenAudio)
        $ps = [PowerShell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript({
            # Authentischer Keygen-Chiptune im Tracker-Stil. Drei Sektionen:
            # schnelle Arpeggios (fingieren Akkorde auf einem Kanal), eine
            # Lead-Melodie und ein Bass/Melodie-Wechsel. Akkordfolge Am-F-C-G.
            # Paare @(Frequenz_Hz, Dauer_ms); Frequenz 0 = Pause.
            $melody = @(
                # -- Arpeggio-Lauf (Am F C G), 16tel ---------------------------
                @(440,52),@(523,52),@(659,52),@(880,52),@(659,52),@(523,52),@(440,52),@(330,52),
                @(349,52),@(440,52),@(523,52),@(698,52),@(523,52),@(440,52),@(349,52),@(262,52),
                @(262,52),@(330,52),@(392,52),@(523,52),@(392,52),@(330,52),@(262,52),@(196,52),
                @(196,52),@(247,52),@(294,52),@(392,52),@(294,52),@(247,52),@(196,52),@(294,52),
                # -- Lead-Melodie ----------------------------------------------
                @(659,150),@(0,40),@(440,150),@(523,150),@(659,210),@(0,60),
                @(698,150),@(659,150),@(587,150),@(523,210),@(0,60),
                @(659,150),@(784,150),@(659,150),@(523,210),@(0,60),
                @(587,150),@(494,150),@(392,150),@(494,150),@(587,260),@(0,90),
                # -- Bass/Melodie-Wechsel (Tracker-Feel) -----------------------
                @(110,66),@(440,66),@(110,66),@(523,66),@(110,66),@(659,66),@(110,66),@(523,66),
                @(175,66),@(440,66),@(175,66),@(523,66),@(175,66),@(698,66),@(175,66),@(523,66),
                @(131,66),@(659,66),@(131,66),@(392,66),@(131,66),@(523,66),@(131,66),@(659,66),
                @(196,66),@(587,66),@(196,66),@(494,66),@(196,66),@(392,66),@(196,66),@(587,66),
                @(0,140)
            )
            while ($Audio.Running) {
                foreach ($n in $melody) {
                    if (-not $Audio.Running) { break }
                    if ($n[0] -le 0) { Start-Sleep -Milliseconds $n[1] }
                    else { [console]::Beep([int]$n[0], [int]$n[1]) }
                }
            }
        })
        $Global:KeygenAudio.PowerShell = $ps
        [void]$ps.BeginInvoke()
        Write-SuiteLog 'Keygen-Musik gestartet' 'INFO'
    } catch {
        $Global:KeygenAudio.Running = $false
        Write-SuiteLog "Keygen-Musik Start-Fehler: $($_.Exception.Message)" 'WARN'
    }
}

# Stoppt die Musik. Der Runspace-Loop bricht beim naechsten Ton ab (<=~300ms);
# das Dispose passiert lazy beim naechsten Start oder beim Fenster-Schliessen.
function Stop-KeygenMusic {
    $Global:KeygenAudio.Running = $false
}

$ctrls.btnKeygenGenerate.Add_Click({ Invoke-KeygenGenerate })

$ctrls.btnKeygenMusic.Add_Click({
    if ($Global:KeygenAudio.Running) {
        Stop-KeygenMusic
        $ctrls.btnKeygenMusic.Content = 'MUSIK: AUS'
    } else {
        Start-KeygenMusic
        $ctrls.btnKeygenMusic.Content = if ($Global:KeygenAudio.Running) { 'MUSIK: AN' } else { 'MUSIK: AUS' }
    }
})

# Musik nicht ueber den Key-Gen-Tab hinaus weiterlaufen lassen. WICHTIG: das
# SelectionChanged der ComboBoxen im Grafik-Tab ist ein Routed-Event und blubbert
# bis zum TabControl hoch - darum nur auf echte Tab-Wechsel reagieren.
$ctrls.mainTabs.Add_SelectionChanged({
    if ($args[1].Source -isnot [System.Windows.Controls.TabControl]) { return }
    if ($Global:KeygenAudio.Running) {
        $sel = $ctrls.mainTabs.SelectedItem
        if (-not $sel -or "$($sel.Header)" -ne 'Key Gen') {
            Stop-KeygenMusic
            $ctrls.btnKeygenMusic.Content = 'MUSIK: AUS'
        }
    }
})

# ASCII-Art-Header (reines ASCII - keine Encoding-Risiken)
$ctrls.lblKeygenArt.Text = @'
 ____   _   _  ____    ____
|  _ \ | | | || __ )  / ___|
| |_) || | | ||  _ \ | |  _
|  __/ | |_| || |_) || |_| |
|_|     \___/ |____/  \____|
   S U I T E   ::   K E Y G E N
   - 2026 release  //  100% working -
'@

# Greetz-Scroller (DispatcherTimer schiebt den String zeichenweise)
$Global:KeygenGreetz = '***  GREETINGS TO ALL PUBG GRINDERS  ***  STAY SALTY  ***  GG WP  ***  WINNER WINNER CHICKEN DINNER  ***  '
$keygenGreetzTimer = New-Object System.Windows.Threading.DispatcherTimer
$keygenGreetzTimer.Interval = [TimeSpan]::FromMilliseconds(220)
$keygenGreetzTimer.Add_Tick({
    $s = $Global:KeygenGreetz
    $Global:KeygenGreetz = $s.Substring(1) + $s.Substring(0,1)
    if ($ctrls.lblKeygenGreetz) { $ctrls.lblKeygenGreetz.Text = $Global:KeygenGreetz }
})
$keygenGreetzTimer.Start()

# Startwert im Code-Feld (ohne Animation)
$ctrls.lblKeygenCode.Text = New-KeygenCode -Groups $Global:KeygenState.Groups -Len $Global:KeygenState.Len

# Version dynamisch in Header, Window-Title und About-Card (vermeidet "v1.0.0-PoC" Bug)
$ctrls.lblVersion.Text = "v$($Global:Suite.Version)"
$window.Title = "PUBG Performance Suite v$($Global:Suite.Version)"
if ($ctrls.lblAboutVersion) {
    $ctrls.lblAboutVersion.Text = "  -  v$($Global:Suite.Version)"
}

# Update-Check gegen den main-Branch. Fehler-tolerant (kurzer Timeout,
# Exceptions geschluckt) - bei neuer Version erscheint ein klickbares Badge
# im Header, dessen Klick die Update-Anleitung (irm|iex-Befehl) zeigt.
$updateInfo = Test-SuiteUpdate
if ($updateInfo) {
    $ctrls.lblUpdate.Text = "Update: $($updateInfo.Version)"
    $ctrls.updateBadge.Tag = $updateInfo.Version
    $ctrls.updateBadge.Visibility = 'Visible'
    $ctrls.updateBadge.Add_MouseLeftButtonUp({
        $newV = [string]$this.Tag
        [System.Windows.MessageBox]::Show(
            "Neuere Version verfuegbar: $newV   (installiert: v$($Global:Suite.Version))`n`n" +
            "Zum Aktualisieren diesen Befehl in PowerShell ausfuehren:`n`n" +
            "irm `"https://raw.githubusercontent.com/$($Global:Suite.RepoSlug)/main/launch.ps1`" | iex`n`n" +
            "Der Befehl laedt den neuesten Stand und ersetzt die alte Version automatisch.",
            'Update verfuegbar', 'OK', 'Information') | Out-Null
    })
}

# Admin-Badge initial setzen
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    $ctrls.lblAdmin.Text = 'Admin: JA'
    $ctrls.adminBadge.Background = $Global:SuiteColors.StatusOK
} else {
    $ctrls.lblAdmin.Text = 'Admin: NEIN'
    $ctrls.adminBadge.Background = $Global:SuiteColors.StatusError
}

# Config aus File laden (MonitorPattern etc.)
try {
    $cfg = Get-SuiteConfig
    if ($cfg.MonitorPattern) {
        $Global:Suite.MonitorPattern = $cfg.MonitorPattern
        $ctrls.tbMonitorPattern.Text = $cfg.MonitorPattern
    }
    Write-SuiteLog "Suite gestartet (Admin: $isAdmin, MonitorPattern: $($Global:Suite.MonitorPattern))"
} catch {
    Write-SuiteLog "Config-Load Fehler: $($_.Exception.Message)" 'WARN'
}

# Tab-Reihenfolge fuer User-Journey: Dashboard -> Tweaks -> Game Mode -> Capture -> Diagnose -> Settings
# XAML-Order ist: 0=Dashboard, 1=Diagnose, 2=Capture, 3=Game Mode, 4=Tweaks, 5=Settings
# Wir verschieben Items per Code (kein 700-Zeilen XAML-Move).
try {
    $tabsCol = $ctrls.mainTabs.Items
    # Tweaks (idx 4) -> position 1
    $tw = $tabsCol[4]; $tabsCol.RemoveAt(4); $tabsCol.Insert(1, $tw)
    # Game Mode (jetzt idx 4) -> position 2
    $gm = $tabsCol[4]; $tabsCol.RemoveAt(4); $tabsCol.Insert(2, $gm)
    # Capture (jetzt idx 4) -> position 3
    $cp = $tabsCol[4]; $tabsCol.RemoveAt(4); $tabsCol.Insert(3, $cp)
    # Final: 0=Dashboard, 1=Tweaks, 2=Game Mode, 3=Capture, 4=Diagnose, 5=Settings
    $ctrls.mainTabs.SelectedIndex = 0
} catch {
    Write-SuiteLog "Tab-Reorder fehlgeschlagen: $($_.Exception.Message)" 'WARN'
}

# Initial Status
Update-StatusGrid
Update-TweaksTab
Update-GraphicsTab

# Cleanup beim Schliessen - Timer stoppen, ggf. laufenden PresentMon killen
$window.Add_Closing({
    try {
        if ($Global:CaptureState -and $Global:CaptureState.IsRunning) {
            Write-SuiteLog "Window-Close: stoppe laufende Capture" 'INFO'
            Cleanup-CapState
        }
        # Keygen-Musik-Runspace stoppen (sonst beept es nach dem Schliessen weiter)
        Stop-KeygenMusic
    } catch {}  # Fenster schliesst ohnehin - Fehler hier unkritisch
})

# Show
$window.ShowDialog() | Out-Null
