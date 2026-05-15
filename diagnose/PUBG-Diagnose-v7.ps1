<#
.SYNOPSIS
    PUBG Competitive Setup Diagnose v7 - reiner Report gegen geteilte Konfiguration

.DESCRIPTION
    v7 ist ein REPORT-ONLY-Tool. Es bewertet das System und schreibt einen
    HTML-Report. Es nimmt selbst KEINE Aenderungen mehr vor - alle Fixes laufen
    ueber die PUBG Performance Suite (Tweaks-Tab + Grafik-Tab).

    Aenderungen gegenueber v6:
    - Single Source of Truth: Grafik-Soll-Werte kommen aus config\PUBGProfile.psd1,
      System-Tweak-Checks aus config\PUBGTweakRegistry.psm1. Kein Hardcoding mehr.
    - Neue, mechanisch definierte Status-Kategorien:
        SYSINFO   reine Identifikation / Live-Messung, nicht bewertet
        OK        gegen Soll geprueft, passt
        TWEAK     Verbesserung via Suite moeglich, nicht kritisch
        ISSUE     muss adressiert werden (Suite kann es fixen)
        MANUELL   Nutzer kann es selbst beheben (BIOS/Treiber/Windows), nicht via Suite
        SKIP      nicht pruefbar
    - System-Tweak-Checks laufen ueber eine Schleife ueber die Tweak-Registry:
      jeder TWEAK-Befund hat damit garantiert einen Apply-Button in der Suite.
    - Grafik-Checks vergleichen gegen PUBGProfile.psd1 (loest den alten
      Konflikt Suite-setzt-X / Diagnose-erwartet-Y).
    - MMCSS-Check kommt aus der Registry (robuster String-Vergleich, kein
      Int/UInt-Bug mehr).
    - Multi-Monitor zaehlt aktive Displays via Screen.AllScreens (statt
      WmiMonitorID, das auch abgeklemmte Monitore mitzaehlte).
    - Entfernt: Display-Skalierung (zu invasiver Fix), System Timer Resolution
      (auf Win11 22H2+ technisch obsolet - per-process seit Win10 2004).
    - Entfernt: interaktive Fix-Phase + Admin-Script-Generierung (Fixes laufen
      jetzt in der Suite).

.NOTES
    Aufruf: powershell -ExecutionPolicy Bypass -File "PUBG-Diagnose-v7.ps1"
    Keine Admin-Rechte noetig. Einige Checks zeigen ohne Admin SKIP.

    Parameter:
      -NonInteractive  Akzeptiert (Abwaertskompatibilitaet, von der Suite genutzt).
                       v7 ist ohnehin immer report-only.
#>

param(
    [switch]$NonInteractive
)

# ==================== KONFIGURATION ====================
$OutputFolder = "$env:USERPROFILE\Desktop"
$ReportTitle  = 'PUBG Competitive Setup - System Report v7'
$IncludePingTest = $true
$PingCount    = 10
# ========================================================

$ErrorActionPreference = 'SilentlyContinue'
$timestamp  = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$reportPath = Join-Path $OutputFolder "PUBGSystemReport_v7_$timestamp.html"
$Global:Findings = New-Object System.Collections.Generic.List[hashtable]

function Add-Finding {
    param(
        [string]$Section,
        [string]$Item,
        [string]$Value,
        [ValidateSet('SYSINFO','OK','TWEAK','ISSUE','MANUELL','SKIP')]
        [string]$Status = 'SYSINFO',
        [string]$Recommendation = '',
        [string]$Impact = '',
        [string]$ImpactDetail = ''
    )
    $Global:Findings.Add(@{
        Section = $Section; Item = $Item; Value = $Value; Status = $Status
        Recommendation = $Recommendation; Impact = $Impact; ImpactDetail = $ImpactDetail
    })
}

function Write-Status {
    param([string]$Msg, [string]$Status = 'INFO')
    $color = switch ($Status) {
        'OK' {'Green'} 'TWEAK' {'Yellow'} 'ISSUE' {'Red'} 'MANUELL' {'DarkYellow'}
        'SKIP' {'DarkGray'} default {'Cyan'}
    }
    Write-Host "[$Status] $Msg" -ForegroundColor $color
}

# ==================== GETEILTE KONFIGURATION LADEN ====================
# Diagnose liegt in <repo>\diagnose\ - die geteilte Config in <repo>\config\.
$Global:ConfigDir = $null
foreach ($cand in @(
    (Join-Path $PSScriptRoot '..\config'),
    (Join-Path $PSScriptRoot 'config'),
    (Join-Path (Split-Path $PSScriptRoot -Parent) 'config')
)) {
    if ($cand -and (Test-Path (Join-Path $cand 'PUBGProfile.psd1'))) {
        $Global:ConfigDir = (Resolve-Path $cand).Path
        break
    }
}

$Global:PUBGProfile = $null
$Global:ProfileVersion = '?'
$Global:ProfileHash = '?'
$profilePath = if ($Global:ConfigDir) { Join-Path $Global:ConfigDir 'PUBGProfile.psd1' } else { $null }
if ($profilePath -and (Test-Path $profilePath)) {
    try {
        $pd = Import-PowerShellDataFile -Path $profilePath -ErrorAction Stop
        $Global:PUBGProfile    = $pd.Sections
        $Global:ProfileVersion = "$($pd.ProfileVersion)"
        $Global:ProfileHash    = (Get-FileHash -Path $profilePath -Algorithm SHA256).Hash.Substring(0,12).ToLower()
        Write-Status "Grafikprofil geladen: v$($Global:ProfileVersion) (SHA256 $($Global:ProfileHash))" 'INFO'
    } catch {
        Write-Status "Grafikprofil konnte nicht geladen werden: $($_.Exception.Message)" 'SKIP'
    }
} else {
    Write-Status 'PUBGProfile.psd1 nicht gefunden - Grafik-Checks werden uebersprungen' 'SKIP'
}

$Global:TweakRegistryLoaded = $false
$registryPath = if ($Global:ConfigDir) { Join-Path $Global:ConfigDir 'PUBGTweakRegistry.psm1' } else { $null }
if ($registryPath -and (Test-Path $registryPath)) {
    try {
        Import-Module $registryPath -Force -ErrorAction Stop
        $Global:TweakRegistryLoaded = (Get-Command Get-PUBGTweakRegistry -ErrorAction SilentlyContinue) -ne $null
        Write-Status 'Tweak-Registry geladen' 'INFO'
    } catch {
        Write-Status "Tweak-Registry konnte nicht geladen werden: $($_.Exception.Message)" 'SKIP'
    }
} else {
    Write-Status 'PUBGTweakRegistry.psm1 nicht gefunden - System-Tweak-Checks werden uebersprungen' 'SKIP'
}

# ==================== HELFER ====================
function Get-PUBGGpuVRAM {
    param($gpuObj)
    if ($gpuObj.Name -match 'NVIDIA|GeForce|RTX|GTX') {
        $nvSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
        if ($nvSmi) {
            try {
                $out = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1
                if ($out) {
                    $mb = [int]$out.Trim()
                    return @{ GB = [math]::Round($mb / 1024, 1); Source = 'nvidia-smi' }
                }
            } catch {}
        }
    }
    try {
        $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        $subkeys = Get-ChildItem $cls -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' }
        foreach ($k in $subkeys) {
            $props = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
            if ($props.'HardwareInformation.AdapterString' -and $gpuObj.Name -match [regex]::Escape(($props.'HardwareInformation.AdapterString' -replace 'NVIDIA |AMD ',''))) {
                $qw = $props.'HardwareInformation.qwMemorySize'
                if ($qw) { return @{ GB = [math]::Round($qw / 1GB, 1); Source = 'Registry' } }
            }
        }
    } catch {}
    if ($gpuObj.AdapterRAM) {
        return @{ GB = [math]::Round($gpuObj.AdapterRAM / 1GB, 1); Source = 'Win32 (ungenau bei >4GB)' }
    }
    return $null
}

function Get-IniValue {
    param([string]$Key, [string]$Content)
    if ($Content -and $Content -match "(?m)^\s*$([regex]::Escape($Key))\s*=\s*([^\r\n]+)") {
        return $matches[1].Trim()
    }
    return $null
}

Write-Host "`n=== PUBG System Report v7 wird erstellt ===`n" -ForegroundColor Cyan


# ==================== 1. PRIMAERER MONITOR ====================
Write-Status 'Primaerer Monitor wird identifiziert...' 'INFO'
Add-Type -AssemblyName System.Windows.Forms

$videoControllers = Get-CimInstance -ClassName Win32_VideoController |
    Where-Object { $_.CurrentRefreshRate -gt 0 -and $_.VideoModeDescription }
$primaryCtrl = $videoControllers | Sort-Object -Property CurrentRefreshRate -Descending | Select-Object -First 1

$activeHz = $null
if ($primaryCtrl) {
    $activeHz  = $primaryCtrl.CurrentRefreshRate
    $activeRes = "$($primaryCtrl.CurrentHorizontalResolution) x $($primaryCtrl.CurrentVerticalResolution)"

    if ($activeHz -ge 144) {
        Add-Finding 'Monitor (Primary)' 'Aktive Refreshrate' "$activeHz Hz" 'OK'
    } else {
        Add-Finding 'Monitor (Primary)' 'Aktive Refreshrate' "$activeHz Hz" 'MANUELL' `
            'Fuer Competitive PUBG mind. 144 Hz - in den Windows-Anzeige-Einstellungen pruefen/umstellen'
    }
    Add-Finding 'Monitor (Primary)' 'Aktive Aufloesung' $activeRes 'SYSINFO'
}

# Multi-Monitor: aktive Displays via Screen.AllScreens (zeigt nur vom DWM real
# genutzte Displays - abgeklemmte/per Suite deaktivierte Monitore zaehlen NICHT
# mit, anders als das alte WmiMonitorID). Damit faellt der Count nach dem
# Suite-Game-Mode korrekt auf 1.
try { $monCount = [System.Windows.Forms.Screen]::AllScreens.Count } catch { $monCount = 0 }
if ($monCount -eq 1) {
    Add-Finding 'Monitor (Primary)' 'Aktive Monitore' '1 (Solo - optimal)' 'OK'
} elseif ($monCount -gt 1) {
    Add-Finding 'Monitor (Primary)' 'Aktive Monitore' "$monCount aktiv" 'MANUELL' `
        'Mehr als 1 aktives Display zwingt PUBG aus dem Independent-Flip-Modus (~3-5 ms Latenz extra). Fuer Competitive-Sessions den Game-Mode der Suite nutzen - der klemmt die Nebenmonitore sauber ab.' `
        'GERING' 'Suite > Game-Mode-Tab erledigt das per Klick und stellt es danach wieder her'
} elseif ($monCount -eq 0) {
    Add-Finding 'Monitor (Primary)' 'Aktive Monitore' 'nicht ermittelbar' 'SKIP'
}

# EDID-Modell + maximale Hz
try {
    $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop
    $activeMonitor = $monitors | Where-Object { $_.Active -eq $true } | Select-Object -First 1
    if (-not $activeMonitor) { $activeMonitor = $monitors | Select-Object -First 1 }
    if ($activeMonitor) {
        $manu  = ($activeMonitor.ManufacturerName | Where-Object {$_ -ne 0} | ForEach-Object {[char]$_}) -join ''
        $model = ($activeMonitor.UserFriendlyName  | Where-Object {$_ -ne 0} | ForEach-Object {[char]$_}) -join ''
        Add-Finding 'Monitor (Primary)' 'Modell (EDID)' "$manu $model" 'SYSINFO'
    }
    $supportedModes = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorListedSupportedSourceModes -ErrorAction Stop
    $allHz = $supportedModes.MonitorSourceModes | ForEach-Object { $_.VerticalRefreshRate }
    $maxHz = ($allHz | Sort-Object -Descending | Select-Object -First 1)
    if ($maxHz -and $primaryCtrl) {
        if ($primaryCtrl.CurrentRefreshRate -lt $maxHz) {
            Add-Finding 'Monitor (Primary)' 'Max. unterstuetzte Hz (EDID)' "$maxHz Hz" 'MANUELL' `
                "Aktiv laeuft der Monitor mit $($primaryCtrl.CurrentRefreshRate) Hz, kann aber $maxHz Hz. In den Windows-Anzeige-Einstellungen die hoehere Bildwiederholrate waehlen (falls nicht bewusst gecappt)."
        } else {
            Add-Finding 'Monitor (Primary)' 'Max. unterstuetzte Hz (EDID)' "$maxHz Hz" 'OK'
        }
    }
} catch {
    Add-Finding 'Monitor (Primary)' 'EDID-Auslesung' 'nicht moeglich' 'SKIP'
}


# ==================== 2. DEDIZIERTE GPU ====================
Write-Status 'Dedizierte GPU wird identifiziert...' 'INFO'
$allGpus = Get-CimInstance -ClassName Win32_VideoController
$dGpu = $allGpus | Where-Object {
    $_.Name -match 'NVIDIA|GeForce|RTX|GTX|Quadro|Radeon RX|Radeon Pro' -and
    $_.Name -notmatch 'Vega.*Graphics|Radeon Graphics$|UHD|Iris|HD Graphics'
} | Select-Object -First 1
if (-not $dGpu) {
    $dGpu = $allGpus | Sort-Object -Property AdapterRAM -Descending | Select-Object -First 1
}

if ($dGpu) {
    Add-Finding 'GPU (dediziert)' 'Modell' $dGpu.Name 'SYSINFO'

    $vramInfo = Get-PUBGGpuVRAM -gpuObj $dGpu
    if ($vramInfo) {
        $vram = $vramInfo.GB
        if ($vram -ge 8) {
            Add-Finding 'GPU (dediziert)' 'VRAM' "$vram GB (Quelle: $($vramInfo.Source))" 'OK'
        } else {
            Add-Finding 'GPU (dediziert)' 'VRAM' "$vram GB (Quelle: $($vramInfo.Source))" 'MANUELL' `
                'Unter 8 GB VRAM wird PUBG bei hohen Texturen eng - Hardware-seitig, nicht per Software fixbar'
        }
    }

    Add-Finding 'GPU (dediziert)' 'Treiber-Version' "$($dGpu.DriverVersion)" 'SYSINFO'
    Add-Finding 'GPU (dediziert)' 'Treiber-Datum' "$($dGpu.DriverDate)" 'SYSINFO'
    if ($dGpu.DriverDate) {
        $ageDays = (New-TimeSpan -Start $dGpu.DriverDate -End (Get-Date)).Days
        if ($ageDays -lt 90) {
            Add-Finding 'GPU (dediziert)' 'Treiber-Alter' "$ageDays Tage" 'OK'
        } else {
            Add-Finding 'GPU (dediziert)' 'Treiber-Alter' "$ageDays Tage" 'MANUELL' `
                "Treiber $ageDays Tage alt - Update via NVIDIA App / AMD Adrenalin"
        }
    }

    if ($dGpu.PNPDeviceID) {
        $msiPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dGpu.PNPDeviceID)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
        if (Test-Path $msiPath) {
            $msi = Get-ItemProperty -Path $msiPath -Name 'MSISupported' -ErrorAction SilentlyContinue
            if ($null -ne $msi.MSISupported) {
                $msiVal = if ($msi.MSISupported -eq 1) {'AN (MSI)'} else {'AUS (Line-Based)'}
                Add-Finding 'GPU (dediziert)' 'MSI Mode (IRQ)' $msiVal 'SYSINFO'
            }
        }
    }

    $nvSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($nvSmi -and $dGpu.Name -match 'NVIDIA|GeForce|RTX|GTX|Quadro') {
        try {
            $nvOutput = & nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1
            if ($nvOutput) {
                $nvParts = ($nvOutput -split ',') | ForEach-Object { $_.Trim() }
                $gpuTemp = [int]$nvParts[0]
                if ($gpuTemp -lt 75) {
                    Add-Finding 'GPU (dediziert)' 'GPU-Temperatur (live)' "$gpuTemp C" 'SYSINFO'
                } else {
                    Add-Finding 'GPU (dediziert)' 'GPU-Temperatur (live)' "$gpuTemp C" 'MANUELL' `
                        'GPU laeuft warm - Gehaeuse-Airflow / Luefterkurve / Staub pruefen'
                }
                Add-Finding 'GPU (dediziert)' 'GPU-Auslastung (live)' "$($nvParts[1]) %" 'SYSINFO'
                Add-Finding 'GPU (dediziert)' 'VRAM-Belegung (live)' "$($nvParts[2]) / $($nvParts[3]) MB" 'SYSINFO'
            }
        } catch {
            Add-Finding 'GPU (dediziert)' 'nvidia-smi' 'Fehler beim Auslesen' 'SKIP'
        }
    } elseif ($dGpu.Name -match 'Radeon|AMD') {
        Add-Finding 'GPU (dediziert)' 'AMD Adrenalin (manuell)' 'Anti-Lag+ AN, Radeon Boost AUS, Image Sharpening AUS, FreeSync AN' 'MANUELL' `
            'AMD bietet keine Skript-API - diese Werte manuell in der Adrenalin-Software setzen'
    }
}


# ==================== 3. CPU & RAM ====================
Write-Status 'CPU/RAM-Informationen werden ausgelesen...' 'INFO'
$cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
Add-Finding 'CPU/RAM' 'CPU-Modell' "$($cpu.Name)" 'SYSINFO'
$isX3D = ($cpu.Name -match 'X3D')

$cores   = $cpu.NumberOfCores
$threads = $cpu.NumberOfLogicalProcessors
if ($cores -ge 6) {
    Add-Finding 'CPU/RAM' 'Kerne / Threads' "$cores / $threads" 'OK'
} else {
    Add-Finding 'CPU/RAM' 'Kerne / Threads' "$cores / $threads" 'MANUELL' `
        'Unter 6 Kerne wird PUBG CPU-limitiert - Hardware-seitig, nicht per Software fixbar'
}

if ($isX3D) {
    # Positiver Befund gegen die Empfehlung "X3D fuer Gaming" -> OK
    Add-Finding 'CPU/RAM' 'X3D-CPU erkannt' 'JA' 'OK'
    $svcs = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '3DVCache|AMD3DVCache' }
    if ($svcs) {
        $svc = $svcs | Select-Object -First 1
        if ($svc.Status -eq 'Running') {
            Add-Finding 'CPU/RAM' 'AMD 3D V-Cache Service' "$($svc.Name) - laeuft" 'OK'
        } else {
            Add-Finding 'CPU/RAM' 'AMD 3D V-Cache Service' "$($svc.Name) - $($svc.Status)" 'MANUELL' `
                'Service sollte laufen - koordiniert den X3D-Scheduler. Aktuellen AMD Chipset-Treiber installieren.'
        }
    } else {
        Add-Finding 'CPU/RAM' 'AMD 3D V-Cache Optimizer' 'Service nicht gefunden' 'MANUELL' `
            'Aktuellen AMD Chipset-Treiber installieren (amd.com/support) - bringt den V-Cache Optimizer mit'
    }
}

$ram = @(Get-CimInstance -ClassName Win32_PhysicalMemory)
$totalRAM = [math]::Round(($ram | Measure-Object -Property Capacity -Sum).Sum / 1GB, 0)
if ($totalRAM -ge 16) {
    Add-Finding 'CPU/RAM' 'RAM gesamt' "$totalRAM GB" 'OK'
} else {
    Add-Finding 'CPU/RAM' 'RAM gesamt' "$totalRAM GB" 'MANUELL' '16 GB Minimum, 32 GB empfohlen - Hardware-Upgrade'
}

$ramSticks = $ram.Count
if ($ramSticks -gt 0) {
    $ramFirst = $ram[0]
    Add-Finding 'CPU/RAM' 'RAM-Module' "$ramSticks DIMM(s)" 'SYSINFO'
    $memType = $ramFirst.SMBIOSMemoryType
    $memTypeText = switch ($memType) {
        20 {'DDR'} 21 {'DDR2'} 24 {'DDR3'} 26 {'DDR4'} 34 {'DDR5'} 35 {'DDR5'} default {"Type-$memType"}
    }
    Add-Finding 'CPU/RAM' 'RAM-Typ' $memTypeText 'SYSINFO'

    if ($ramSticks -eq 4 -and ($memType -eq 34 -or $memType -eq 35)) {
        Add-Finding 'CPU/RAM' 'RAM-Layout 4-DIMM DDR5' '4 Module bestueckt' 'MANUELL' `
            '4-DIMM DDR5 ist schwer stabil auf 6000 MT/s+ zu bekommen. 2x32GB statt 4x16GB ergibt mehr OC-Headroom.' `
            'HOCH' 'Hardware-Wechsel - nur planen falls EXPO instabil'
    }

    $ramRated = $ramFirst.Speed
    $ramConfigured = $ramFirst.ConfiguredClockSpeed
    if (-not $ramConfigured) { $ramConfigured = $ramRated }
    if ($ramRated -and $ramConfigured) {
        if ($memType -eq 34 -or $memType -eq 35) {
            $expoOk = ($ramConfigured -ge 6000)
            $expoReco = if ($ramConfigured -lt 5200) {
                'DDR5 laeuft auf JEDEC - EXPO im BIOS aktivieren. 6000 CL30 bringt 8-15% bessere 1%-Lows.'
            } elseif ($ramConfigured -lt 6000) {
                '6000 CL30 ist der Sweet-Spot - EXPO-Profil im BIOS pruefen'
            } else { '' }
        } else {
            $expoOk = ($ramConfigured -ge 3200)
            $expoReco = if (-not $expoOk) { 'DDR4 laeuft auf JEDEC - XMP im BIOS aktivieren' } else { '' }
        }
        if ($expoOk) {
            Add-Finding 'CPU/RAM' 'RAM-Takt (aktiv)' "$ramConfigured MT/s (Rated: $ramRated)" 'OK'
        } else {
            Add-Finding 'CPU/RAM' 'RAM-Takt (aktiv)' "$ramConfigured MT/s (Rated: $ramRated)" 'MANUELL' `
                $expoReco 'GERING' 'EXPO/XMP-Aktivierung erfordert einen BIOS-Reboot'
        }
    }
}


# ==================== 4. SPEICHER (PUBG-INSTALL) ====================
Write-Status 'Storage-Typ fuer PUBG-Installation...' 'INFO'
$steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
if (-not $steamPath) { $steamPath = (Get-ItemProperty 'HKLM:\Software\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath }
if (-not $steamPath) { $steamPath = (Get-ItemProperty 'HKLM:\Software\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath }

$pubgInstallPath = $null
if ($steamPath -and (Test-Path $steamPath)) {
    Add-Finding 'Speicher' 'Steam-Installation' $steamPath 'SYSINFO'
    $libFile = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path $libFile) {
        $libContent = Get-Content $libFile -Raw
        $libs = [regex]::Matches($libContent, '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\','\' }
        foreach ($lib in $libs) {
            $manifest = Join-Path $lib 'steamapps\appmanifest_578080.acf'
            if (Test-Path $manifest) {
                $mc = Get-Content $manifest -Raw
                if ($mc -match '"installdir"\s+"([^"]+)"') {
                    $pubgInstallPath = Join-Path $lib "steamapps\common\$($matches[1])"
                }
                break
            }
        }
    }
}

if ($pubgInstallPath -and (Test-Path $pubgInstallPath)) {
    Add-Finding 'Speicher' 'PUBG-Installationspfad' $pubgInstallPath 'SYSINFO'
    try {
        $driveLetter = (Get-Item $pubgInstallPath).PSDrive.Name
        $partition = Get-Partition -DriveLetter $driveLetter -ErrorAction Stop
        $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
        $physDisk = Get-PhysicalDisk -DeviceNumber $partition.DiskNumber -ErrorAction Stop

        Add-Finding 'Speicher' 'Datentraeger Modell' "$($physDisk.FriendlyName)" 'SYSINFO'

        if ($disk.BusType -eq 'NVMe') {
            Add-Finding 'Speicher' 'PUBG Drive Bus' "$($disk.BusType)" 'OK'
        } else {
            Add-Finding 'Speicher' 'PUBG Drive Bus' "$($disk.BusType)" 'MANUELL' `
                'PUBG laeuft am besten von einer NVMe-SSD - ggf. die Installation verschieben'
        }
        if ($physDisk.MediaType -eq 'SSD') {
            Add-Finding 'Speicher' 'PUBG Drive Typ' "$($physDisk.MediaType)" 'OK'
        } elseif ($physDisk.MediaType -eq 'HDD') {
            Add-Finding 'Speicher' 'PUBG Drive Typ' 'HDD' 'MANUELL' 'PUBG von einer SSD installieren - HDD verursacht Streaming-Stutter'
        } else {
            Add-Finding 'Speicher' 'PUBG Drive Typ' "$($physDisk.MediaType)" 'SYSINFO'
        }

        $vol = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
        if ($vol) {
            $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
            $totGB  = [math]::Round($vol.Size / 1GB, 1)
            $freePct = if ($vol.Size -gt 0) { [math]::Round(($vol.SizeRemaining / $vol.Size) * 100, 1) } else { 0 }
            if ($freePct -gt 15) {
                Add-Finding 'Speicher' 'Freier Speicher PUBG-Drive' "$freeGB / $totGB GB ($freePct %)" 'OK'
            } else {
                Add-Finding 'Speicher' 'Freier Speicher PUBG-Drive' "$freeGB / $totGB GB ($freePct %)" 'MANUELL' `
                    'Unter 15% frei - SSDs verlieren dann Schreib-Performance. Platte aufraeumen.'
            }
        }
    } catch {
        Add-Finding 'Speicher' 'Datentraeger-Analyse' 'Fehler beim Auslesen' 'SKIP'
    }
} else {
    Add-Finding 'Speicher' 'PUBG-Installation' 'nicht gefunden' 'SKIP'
}


# ==================== 5. WINDOWS - HARDWARE/OS-SYSTEM-INFO + MANUELLE CHECKS =
Write-Status 'Windows Gaming-Settings werden geprueft...' 'INFO'
$os = Get-CimInstance Win32_OperatingSystem
$winDisplayVer = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion
$ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).UBR
Add-Finding 'Windows' 'Windows Version' "$($os.Caption) $winDisplayVer (Build $($os.BuildNumber).$ubr)" 'SYSINFO'

# Reboot-Pending
$rebootReasons = @()
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $rebootReasons += 'CBS' }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $rebootReasons += 'WindowsUpdate' }
if (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue) { $rebootReasons += 'PendingFileRename' }
if ($rebootReasons.Count -gt 0) {
    Add-Finding 'Windows' 'REBOOT ausstehend' ($rebootReasons -join ', ') 'MANUELL' `
        'Windows-Neustart durchfuehren - ausstehende Aenderungen (u.a. VBS/HVCI) greifen erst danach'
}

# CPU Core Parking - X3D-aware
try {
    $parkOut = (powercfg /q SCHEME_CURRENT SUB_PROCESSOR 0cc5b647-c1df-4637-891a-dec35c318583 2>$null) -join "`n"
    if ($parkOut) {
        $lines = $parkOut -split "`r?`n"
        $currentLines = $lines | Where-Object { $_ -match '0x[0-9a-fA-F]+' -and $_ -match 'Aktuell|Current' }
        if (-not $currentLines) {
            $currentLines = $lines | Where-Object {
                $_ -match '0x[0-9a-fA-F]+' -and $_ -notmatch 'Min Possible|Max Possible|Increment|Mindest|Hoechst|Erhoeh|Moeglich|GUID'
            }
        }
        if ($currentLines -and ($currentLines | Select-Object -First 1) -match '0x([0-9a-fA-F]+)') {
            $parkMin = [Convert]::ToInt32($matches[1], 16)
            if ($isX3D) {
                if ($parkMin -le 25) {
                    Add-Finding 'Windows' 'CPU Core Parking (Min Cores AC)' "$parkMin % - X3D-Modus" 'OK'
                } else {
                    Add-Finding 'Windows' 'CPU Core Parking (Min Cores AC)' "$parkMin % - X3D-Modus" 'MANUELL' `
                        "Auf X3D NICHT auf 100 setzen - der Scheduler braucht Parking, um Games aufs V-Cache-CCD zu pinnen. Default (~5%) via 'powercfg' zuruecksetzen."
                }
            } else {
                if ($parkMin -eq 100) {
                    Add-Finding 'Windows' 'CPU Core Parking (Min Cores AC)' "$parkMin %" 'OK'
                } else {
                    Add-Finding 'Windows' 'CPU Core Parking (Min Cores AC)' "$parkMin %" 'MANUELL' `
                        'Min Cores = 100 % setzen verhindert Park-Latenz (via powercfg, Nicht-X3D-CPU)'
                }
            }
        }
    }
} catch {
    Add-Finding 'Windows' 'CPU Core Parking' 'nicht ermittelbar' 'SKIP'
}

# HDR
try {
    $hdrEnabled = $false
    $hdr = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\VideoSettings' -ErrorAction SilentlyContinue
    if ($hdr -and $hdr.EnableHDRForPlayback -eq 1) { $hdrEnabled = $true }
    $hdrPerMon = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\GraphicsDrivers\Configuration' -ErrorAction SilentlyContinue
    foreach ($k in $hdrPerMon) {
        foreach ($s in (Get-ChildItem $k.PSPath -ErrorAction SilentlyContinue)) {
            if ((Get-ItemProperty $s.PSPath -Name 'AdvancedColorEnabled' -ErrorAction SilentlyContinue).AdvancedColorEnabled -eq 1) { $hdrEnabled = $true }
        }
    }
    if ($hdrEnabled) {
        Add-Finding 'Windows' 'HDR (Anzeige)' 'AKTIV' 'MANUELL' `
            'HDR kann in PUBG den Independent-Flip-Modus blockieren und Farben "washed out" wirken lassen. Fuer Competitive SDR nutzen (Win+Alt+B toggelt HDR).' `
            'GERING' 'Falls der PC auch fuer HDR-Filme dient: pro PUBG-Session toggeln'
    } else {
        Add-Finding 'Windows' 'HDR (Anzeige)' 'AUS' 'OK'
    }
} catch {
    Add-Finding 'Windows' 'HDR-Status' 'nicht ermittelbar' 'SKIP'
}


# ==================== 6. SYSTEM-TWEAKS (aus der Tweak-Registry) ==============
# Statt jeden Tweak-Check hier hart zu codieren: ueber die Registry iterieren.
# Damit hat jeder TWEAK-Befund garantiert einen Apply-Button in der Suite.
Write-Status 'System-Tweaks werden gegen die Tweak-Registry geprueft...' 'INFO'
$sectionForCategory = @{
    'Windows' = 'Windows'; 'GPU' = 'GPU (dediziert)'
    'Network' = 'Netzwerk (EU)'; 'PUBG' = 'PUBG Settings'
}
if ($Global:TweakRegistryLoaded) {
    foreach ($tw in (Get-PUBGTweakRegistry)) {
        $section = $sectionForCategory[$tw.Category]
        if (-not $section) { $section = 'Windows' }
        $res = $null
        try { $res = & $tw.Check } catch { $res = @{ Status='SKIP'; CurrentValue="Check-Fehler: $($_.Exception.Message)"; Detail='' } }
        $st = "$($res.Status)"
        if ($st -notin 'OK','TWEAK','ISSUE','SKIP') { $st = 'SKIP' }
        Add-Finding $section $tw.Label "$($res.CurrentValue)" $st "$($res.Detail)" "$($tw.Impact)" "$($tw.ImpactDetail)"
    }
} else {
    Add-Finding 'Windows' 'System-Tweak-Checks' 'Tweak-Registry nicht geladen' 'SKIP' `
        'config\PUBGTweakRegistry.psm1 nicht gefunden - System-Tweaks konnten nicht geprueft werden'
}


# ==================== 7. PUBG GRAFIK-PROFIL (aus PUBGProfile.psd1) ===========
Write-Status 'PUBG-Grafiksettings werden gegen das Profil geprueft...' 'INFO'

# Steam Launch Options
$launchOpts = (Get-ItemProperty 'HKCU:\Software\Valve\Steam\Apps\578080' -Name 'LaunchOptions' -ErrorAction SilentlyContinue).LaunchOptions
if ($launchOpts) {
    $oldFlags = @()
    if ($launchOpts -match '-USEALLAVAILABLECORES') { $oldFlags += '-USEALLAVAILABLECORES (no-op seit UE4)' }
    if ($launchOpts -match '-malloc=system')        { $oldFlags += '-malloc=system (deprecated)' }
    if ($launchOpts -match '-high')                 { $oldFlags += '-high (kann BattlEye-Konflikt erzeugen)' }
    if ($launchOpts -match '-nojoy')                { $oldFlags += '-nojoy (kein messbarer Effekt)' }
    if ($oldFlags.Count -gt 0) {
        Add-Finding 'PUBG Settings' 'Steam Launch Options' $launchOpts 'MANUELL' `
            "Veraltet/no-op: $($oldFlags -join ', '). 2025/2026-Konsens: Launch Options leer lassen (in Steam > PUBG > Eigenschaften)."
    } else {
        Add-Finding 'PUBG Settings' 'Steam Launch Options' $launchOpts 'OK'
    }
} else {
    Add-Finding 'PUBG Settings' 'Steam Launch Options' 'leer' 'OK'
}

$pubgConfigPath = "$env:LOCALAPPDATA\TslGame\Saved\Config\WindowsNoEditor"
$gus = Join-Path $pubgConfigPath 'GameUserSettings.ini'

# Friendly Labels + kritische Keys (Mismatch = ISSUE statt TWEAK)
$gfxLabels = @{
    'sg.ResolutionQuality'='Render-Skalierung'; 'sg.AntiAliasingQuality'='Anti-Aliasing'
    'sg.ViewDistanceQuality'='Sichtweite'; 'sg.ShadowQuality'='Schatten'
    'sg.PostProcessQuality'='Post-Processing'; 'sg.TextureQuality'='Texturen'
    'sg.EffectsQuality'='Effekte'; 'sg.FoliageQuality'='Laub'
    'ScreenScale'='Screen Scale'; 'bUseVSync'='V-Sync'
    'bUseDynamicResolution'='Dynamische Aufloesung'; 'bMotionBlur'='Bewegungsunschaerfe'
    'bSharpen'='In-Game-Sharpen'; 'bSavedGraphicOption'='Grafik-Option gespeichert'
    'FullscreenMode'='Anzeige-Modus'; 'LastConfirmedFullscreenMode'='Anzeige-Modus (bestaetigt)'
    'PreferredFullscreenMode'='Anzeige-Modus (bevorzugt)'
}
$gfxCritical = @('bUseVSync','bUseDynamicResolution','bMotionBlur','FullscreenMode')

if (-not $Global:PUBGProfile) {
    Add-Finding 'PUBG Settings' 'Grafik-Profil' 'PUBGProfile.psd1 nicht geladen' 'SKIP' `
        'config\PUBGProfile.psd1 nicht gefunden - Grafik-Soll-Werte konnten nicht geprueft werden'
} elseif (-not (Test-Path $gus)) {
    Add-Finding 'PUBG Settings' 'GameUserSettings.ini' 'nicht gefunden' 'SKIP' 'PUBG mind. einmal starten und beenden'
} else {
    $content = Get-Content $gus -Raw

    $resX = Get-IniValue 'ResolutionSizeX' $content
    $resY = Get-IniValue 'ResolutionSizeY' $content
    if ($resX -and $resY) {
        # Aufloesung ist monitorabhaengig -> reine System-Info, nicht bewertet
        Add-Finding 'PUBG Settings' 'Aufloesung (ResolutionSize)' "$resX x $resY" 'SYSINFO'
    }
    $fps = Get-IniValue 'FrameRateLimit' $content
    if ($fps) {
        $fpsVal = [int]([math]::Floor([double]$fps))
        # FPS-Limit gehoert dem fpscap-Tweak (Registry) - hier nur als System-Info zeigen
        Add-Finding 'PUBG Settings' 'FPS-Limit (Ist-Wert)' "$fpsVal FPS" 'SYSINFO'
    }

    foreach ($section in $Global:PUBGProfile.Keys) {
        foreach ($key in $Global:PUBGProfile[$section].Keys) {
            $want = [string]$Global:PUBGProfile[$section][$key]
            $have = Get-IniValue $key $content
            $label = $gfxLabels[$key]; if (-not $label) { $label = $key }
            if ($null -eq $have) {
                $st = if ($key -in $gfxCritical) { 'ISSUE' } else { 'TWEAK' }
                Add-Finding 'PUBG Settings' "Grafik: $label" "fehlt (Soll: $want)" $st `
                    'Grafik-Profil ueber den Grafik-Tab der Suite anwenden'
                continue
            }
            # Float-tolerant (100.000000 == 100); Bools wie 'False' -> String-Vergleich
            $wantNum = $null; $haveNum = $null
            try { $wantNum = [double]$want } catch {}
            try { $haveNum = [double]$have } catch {}
            $match = $false
            if ($null -ne $wantNum -and $null -ne $haveNum) {
                $match = ([math]::Floor($wantNum) -eq [math]::Floor($haveNum))
            } else {
                $match = ($want -eq $have)
            }
            if ($match) {
                Add-Finding 'PUBG Settings' "Grafik: $label" "$have" 'OK'
            } else {
                $st = if ($key -in $gfxCritical) { 'ISSUE' } else { 'TWEAK' }
                Add-Finding 'PUBG Settings' "Grafik: $label" "$have (Soll: $want)" $st `
                    "Grafik-Profil ueber den Grafik-Tab der Suite anwenden (Soll laut Profil v$($Global:ProfileVersion): $want)"
            }
        }
    }

    $eng = Join-Path $pubgConfigPath 'Engine.ini'
    if (Test-Path $eng) {
        Add-Finding 'PUBG Settings' 'Engine.ini' "vorhanden ($((Get-Item $eng).Length) Bytes)" 'SYSINFO'
    }
}


# ==================== 8. NETZWERK - EU MIT JITTER ====================
if ($IncludePingTest) {
    Write-Status "EU-Ping/Jitter ($PingCount Pings)..." 'INFO'
    $pingTargets = [ordered]@{
        'Cloudflare DE'   = '1.1.1.1'
        'Google DNS'      = '8.8.8.8'
        'PUBG-Telemetry'  = 'telemetry.pubg.com'
        'Steam Community' = 'steamcommunity.com'
    }
    foreach ($region in $pingTargets.Keys) {
        try {
            $pings = Test-Connection -ComputerName $pingTargets[$region] -Count $PingCount -ErrorAction Stop
            $times = @($pings | ForEach-Object { $_.ResponseTime })
            if ($times.Count -gt 0) {
                $avg = [math]::Round(($times | Measure-Object -Average).Average, 0)
                $min = ($times | Measure-Object -Minimum).Minimum
                $max = ($times | Measure-Object -Maximum).Maximum
                $variance = ($times | ForEach-Object { [math]::Pow($_ - $avg, 2) } | Measure-Object -Sum).Sum / $times.Count
                $stddev = [math]::Round([math]::Sqrt($variance), 1)
                # Ping/Jitter sind Live-Messungen (ISP/Distanz-abhaengig) -> System-Info
                Add-Finding 'Netzwerk (EU)' "Ping $region (avg)" "$avg ms" 'SYSINFO'
                Add-Finding 'Netzwerk (EU)' "Jitter $region" "stddev=$stddev ms (min=$min, max=$max)" 'SYSINFO'
            }
        } catch {
            Add-Finding 'Netzwerk (EU)' "Ping $region" 'nicht erreichbar' 'SKIP'
        }
    }

    $candidates = Get-NetAdapter | Where-Object {
        $_.Status -eq 'Up' -and $_.Virtual -eq $false -and
        $_.InterfaceDescription -notmatch 'Xbox|Bluetooth|Loopback|Hyper-V|TAP|VPN|WAN Miniport|VirtualBox|VMware'
    }
    $netAdapter = $candidates | Where-Object {
        $cfg = Get-NetIPConfiguration -InterfaceIndex $_.IfIndex -ErrorAction SilentlyContinue
        $cfg -and $cfg.IPv4DefaultGateway
    } | Select-Object -First 1
    if (-not $netAdapter) { $netAdapter = $candidates | Select-Object -First 1 }

    if ($netAdapter) {
        Add-Finding 'Netzwerk (EU)' 'Aktiver Adapter' "$($netAdapter.InterfaceDescription)" 'SYSINFO'
        $isWlan = ($netAdapter.PhysicalMediaType -match '802\.11|Wireless' -or $netAdapter.InterfaceDescription -match 'Wi-Fi|Wireless|WLAN')
        if ($isWlan) {
            Add-Finding 'Netzwerk (EU)' 'Verbindungstyp' 'WLAN' 'MANUELL' `
                'Competitive immer per Kabel - WLAN hat Jitter-Spikes. LAN-Kabel anschliessen.'
        } else {
            Add-Finding 'Netzwerk (EU)' 'Verbindungstyp' 'LAN' 'OK'
        }
        Add-Finding 'Netzwerk (EU)' 'Link-Speed' "$($netAdapter.LinkSpeed)" 'SYSINFO'

        try {
            $rssStatus = Get-NetAdapterRss -Name $netAdapter.Name -ErrorAction SilentlyContinue
            if ($rssStatus) {
                if ($rssStatus.Enabled) {
                    Add-Finding 'Netzwerk (EU)' 'NIC Receive Side Scaling (RSS)' 'AN' 'OK'
                } else {
                    Add-Finding 'Netzwerk (EU)' 'NIC Receive Side Scaling (RSS)' 'AUS' 'MANUELL' `
                        'RSS verteilt Receive-Interrupts auf alle Kerne. Aktivieren via Admin-PowerShell: Enable-NetAdapterRss -Name "<Adapter>"'
                }
            }
            $imProp = Get-NetAdapterAdvancedProperty -Name $netAdapter.Name -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Interrupt Moderation|Interrupt-Moderation' }
            if ($imProp) {
                $imOn = $imProp.DisplayValue -notmatch 'Disabled|Aus|Off'
                if ($imOn) {
                    Add-Finding 'Netzwerk (EU)' 'NIC Interrupt Moderation' "$($imProp.DisplayValue)" 'MANUELL' `
                        'Interrupt Moderation batcht Interrupts (Latenz). Im Geraete-Manager > NIC > Erweitert deaktivieren.'
                } else {
                    Add-Finding 'Netzwerk (EU)' 'NIC Interrupt Moderation' 'AUS' 'OK'
                }
            }
            $ipCfg = Get-NetIPInterface -InterfaceIndex $netAdapter.IfIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($ipCfg) {
                # MTU rein als System-Info - 1500 ist fuer Kabel/Glasfaser korrekt, der
                # PPPoE-Adapter setzt 1492 ohnehin automatisch. Kein Tweak noetig.
                Add-Finding 'Netzwerk (EU)' 'MTU (Ethernet)' "$($ipCfg.NlMtu)" 'SYSINFO'
            }
        } catch {
            Add-Finding 'Netzwerk (EU)' 'NIC-Eigenschaften' 'Auslese-Fehler (Admin?)' 'SKIP'
        }
    }
}


# ==================== HTML-REPORT ====================
Write-Status 'HTML-Report wird gebaut...' 'INFO'

# Status -> Darstellung. SYSINFO/SKIP dezent, Bewertungen kraeftig.
$statusStyle = @{
    'SYSINFO' = @{ Color='#6b7280'; Weight='normal'; Style='normal'; Bg='' }
    'OK'       = @{ Color='#4ade80'; Weight='normal'; Style='normal'; Bg='' }
    'TWEAK'    = @{ Color='#fbbf24'; Weight='bold';   Style='normal'; Bg='' }
    'ISSUE'    = @{ Color='#f87171'; Weight='bold';   Style='normal'; Bg='background:rgba(248,113,113,0.08);' }
    'MANUELL'  = @{ Color='#fb923c'; Weight='bold';   Style='normal'; Bg='' }
    'SKIP'     = @{ Color='#9ca3af'; Weight='normal'; Style='italic'; Bg='' }
}
$statusIcon = @{
    'SYSINFO'='[i]'; 'OK'='[OK]'; 'TWEAK'='[~]'; 'ISSUE'='[!]'; 'MANUELL'='[M]'; 'SKIP'='[-]'
}

function Get-StatusCount { param([string]$S) @($Global:Findings | Where-Object { $_.Status -eq $S }).Count }
$cInv = Get-StatusCount 'SYSINFO'
$cOk  = Get-StatusCount 'OK'
$cTwk = Get-StatusCount 'TWEAK'
$cIss = Get-StatusCount 'ISSUE'
$cMan = Get-StatusCount 'MANUELL'
$cSkp = Get-StatusCount 'SKIP'

$sectionOrder = @('Monitor (Primary)','GPU (dediziert)','CPU/RAM','Speicher','Windows','PUBG Settings','Netzwerk (EU)')
$grouped = $Global:Findings | Group-Object -Property { $_.Section }
$sectionsHtml = foreach ($name in $sectionOrder) {
    $s = $grouped | Where-Object { $_.Name -eq $name }
    if (-not $s) { continue }
    $rows = foreach ($f in $s.Group) {
        $sty = $statusStyle[$f.Status]; if (-not $sty) { $sty = $statusStyle['SYSINFO'] }
        $rowClass = if ($f.Status -eq 'SYSINFO') { ' class="inv"' } else { '' }
        $showExtras = $f.Status -in 'TWEAK','ISSUE','MANUELL'
        $reco = if ($f.Recommendation -and $showExtras) { "<div class='reco'>&rarr; $($f.Recommendation)</div>" } else { '' }
        $impact = ''
        if ($f.Impact -and $showExtras) {
            $detail = if ($f.ImpactDetail) { " &middot; $($f.ImpactDetail)" } else { '' }
            $impact = "<div class='impact'>Alltagsauswirkung: $($f.Impact)$detail</div>"
        }
        $icon = $statusIcon[$f.Status]
@"
        <tr$rowClass style='$($sty.Bg)'>
            <td class='item'>$($f.Item)</td>
            <td class='value'>$($f.Value)$reco$impact</td>
            <td class='status' style='color:$($sty.Color); font-weight:$($sty.Weight); font-style:$($sty.Style)'>$icon $($f.Status)</td>
        </tr>
"@
    }
@"
    <section>
        <h2>$($s.Name)</h2>
        <table>
            <thead><tr><th>Punkt</th><th>Wert / Empfehlung</th><th>Status</th></tr></thead>
            <tbody>
$($rows -join "`n")
            </tbody>
        </table>
    </section>
"@
}

$html = @"
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<title>$ReportTitle</title>
<style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Segoe UI', sans-serif; background: #0f1115; color: #e5e7eb; padding: 2rem; line-height: 1.5; }
    header { border-bottom: 2px solid #2563eb; padding-bottom: 1rem; margin-bottom: 2rem; }
    h1 { color: #60a5fa; font-size: 1.8rem; }
    .meta { color: #9ca3af; font-size: 0.9rem; margin-top: 0.3rem; }
    .summary { display: flex; gap: 0.8rem; margin-bottom: 2rem; flex-wrap: wrap; align-items: stretch; }
    .summary-card { background: #1f2937; padding: 1rem 1.4rem; border-radius: 6px; border-left: 4px solid #60a5fa; min-width: 110px; }
    .summary-card.ok      { border-left-color: #4ade80; }
    .summary-card.tweak   { border-left-color: #fbbf24; }
    .summary-card.issue   { border-left-color: #f87171; }
    .summary-card.manuell { border-left-color: #fb923c; }
    .summary-card.skip    { border-left-color: #9ca3af; }
    .summary-card .count { font-size: 1.5rem; font-weight: bold; }
    .summary-card .label { font-size: 0.85rem; color: #9ca3af; }
    /* System-Info-Karte bewusst dezenter als die Bewertungs-Karten */
    .summary-card.inv { background: #15171c; padding: 0.7rem 1rem; border-left-color: #6b7280; min-width: 90px; align-self: center; }
    .summary-card.inv .count { font-size: 1.1rem; color: #6b7280; }
    .summary-card.inv .label { font-size: 0.75rem; }
    section { background: #1a1d23; padding: 1.5rem; border-radius: 8px; margin-bottom: 1.5rem; border: 1px solid #2d3139; }
    h2 { color: #93c5fd; margin-bottom: 1rem; font-size: 1.2rem; border-bottom: 1px solid #2d3139; padding-bottom: 0.5rem; }
    table { width: 100%; border-collapse: collapse; }
    th { text-align: left; padding: 0.5rem; color: #9ca3af; font-size: 0.85rem; text-transform: uppercase; border-bottom: 1px solid #2d3139; }
    td { padding: 0.6rem 0.5rem; border-bottom: 1px solid #232730; vertical-align: top; }
    td.item { color: #d1d5db; width: 32%; }
    td.value { color: #e5e7eb; }
    td.status { width: 110px; text-align: center; white-space: nowrap; }
    /* System-Info-Zeilen optisch zuruecknehmen, damit das Auge zu den Bewertungen wandert */
    tr.inv td.item, tr.inv td.value { color: #6b7280; }
    .reco { color: #fbbf24; font-size: 0.85rem; margin-top: 0.3rem; font-style: italic; }
    .impact { font-size: 0.8rem; margin-top: 0.2rem; color: #9ca3af; }
    .legend { color: #6b7280; font-size: 0.82rem; margin-bottom: 1.5rem; }
    footer { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #2d3139; color: #6b7280; font-size: 0.8rem; text-align: center; }
</style>
</head>
<body>
<header>
    <h1>$ReportTitle</h1>
    <div class="meta">Erstellt am $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss') auf $env:COMPUTERNAME</div>
</header>

<div class="summary">
    <div class="summary-card ok"><div class="count">$cOk</div><div class="label">OK</div></div>
    <div class="summary-card tweak"><div class="count">$cTwk</div><div class="label">TWEAK (Suite)</div></div>
    <div class="summary-card issue"><div class="count">$cIss</div><div class="label">ISSUE</div></div>
    <div class="summary-card manuell"><div class="count">$cMan</div><div class="label">MANUELL</div></div>
    <div class="summary-card skip"><div class="count">$cSkp</div><div class="label">SKIP</div></div>
    <div class="summary-card inv"><div class="count">$cInv</div><div class="label">System-Info</div></div>
</div>
<div class="legend">
    OK = gegen Soll geprueft, passt &middot; TWEAK = via Suite verbesserbar &middot;
    ISSUE = via Suite zu beheben, wichtig &middot; MANUELL = selbst zu beheben (BIOS/Treiber/Windows) &middot;
    SKIP = nicht pruefbar &middot; System-Info = reine Identifikation
</div>

$($sectionsHtml -join "`n")

<footer>
    PUBG Competitive Setup Diagnose v7 &middot; report-only - Fixes laufen ueber die PUBG Performance Suite<br>
    Geprueft gegen PUBGProfile.psd1 v$($Global:ProfileVersion) (SHA256 $($Global:ProfileHash))
</footer>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host "`n=== Diagnose fertig ===" -ForegroundColor Green
Write-Host "Report: $reportPath" -ForegroundColor Cyan
Write-Host "OK: $cOk  |  TWEAK: $cTwk  |  ISSUE: $cIss  |  MANUELL: $cMan  |  SKIP: $cSkp  |  System-Info: $cInv`n" -ForegroundColor Yellow
Write-Host 'Fixes anwenden: PUBG Performance Suite (Tweaks-Tab / Grafik-Tab).' -ForegroundColor Gray
try { Start-Process $reportPath } catch {}
