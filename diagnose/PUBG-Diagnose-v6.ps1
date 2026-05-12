<#
.SYNOPSIS
    PUBG Competitive Setup Diagnose v6 - Engine.ini, MMCSS, NIC, Latenz-Tweaks

.DESCRIPTION
    v6 Aenderungen gegenueber v5:
    - PUBG Engine.ini wird auf safe Tweaks geprueft & ergaenzt:
        r.Tonemapper.Sharpen=0.7 (Spotting-Buff, BattlEye-safe)
        r.OneFrameThreadLag=0, r.FinishCurrentFrame=0 (Frame-Pacing)
        r.GTSyncType=1 (glattere Frametimes)
        r.Streaming.PoolSize=4096 (besseres Texture-Streaming bei viel RAM)
        r.Streaming.HLODStrategy=2, r.Streaming.FramesForFullUpdate=1
    - Multi-Monitor-Check: explizite Warnung dass >1 aktiver Monitor Mode 5 erzwingt
    - RTSS-Overlay-Check: wenn aktiv -> wahrscheinliche Mode-5-Ursache
    - HDR-Check: warnt wenn HDR fuer competitive PUBG aktiv ist
    - Network-Adapter Offload-Check (LSO, RSC, Interrupt Moderation, MTU)
    - Latency-Section neu: Timer Resolution, MMCSS, Service-Status
    - Admin-Fix erweitert: Service Disable, MMCSS Registry, NIC Offload Disable, MTU 1492

    WAS NICHT drin ist (BattlEye-Ban-Risiko):
        Special K, ReShade, DXVK
        r.Fog=0, r.Atmosphere=0
        r.Shadow.MaxResolution unter UI-Minimum
        Negative r.MipMapLODBias

    v5 Aenderungen gegenueber v4:
    - NPI Setting-IDs auf verifizierte Werte korrigiert (mehrere v4-IDs
      passten nicht zum aktuellen NV-Treiber/NVIDIA-App-Stack 2025-2026):
        * Power Management: 0x1033CEC2 -> 0x1033DCD2
        * Texture Filtering Quality: 0x10ECDB82 -> 0x00CE0E32
        * Threaded Optimization: 0x10D773D2 -> 0x20FF7493
        * Vertical Sync: 0x10C158AD -> 0x00A879CF
        * AA Setting: 0x00A879CF -> 0x00D55F7D (war ID von V-Sync)
    - Frame Rate Limiter wird jetzt zusaetzlich im NV-Profil gesetzt
      (237 FPS) - bei aktivem Reflex-Mode wirksamer als In-Game-Cap
    - Neue Funktion Test-NPIPubgProfile fuer Verifikation per Export
    - NPI-Output zeigt pro Setting [OK]/[FAIL] explizit
    - Title in Reports: "v6"

    v4 Aenderungen gegenueber v3:
    - BUGFIX: VRAM-Auslesung ueber nvidia-smi / Registry (Win32 ist int32-Overflow bei >4GB)
    - BUGFIX: Quality-Settings als Float verglichen (100.000000 == 100)
    - BUGFIX: Netzwerk-Adapter filtert Xbox-Wireless, Bluetooth, virtuelle, Adapter ohne Gateway
    - BUGFIX: Steam-Ping-Ziele ersetzt (cm-01.*.valve.net antworten nicht auf ICMP)
    - BUGFIX: ViewDistanceQuality = 0 ist BAD (nicht WARN) - critical fuer Competitive
    - LOGIK-FIX: Core Parking auf X3D-CPUs INVERTIERT (100% schadet, der Scheduler braucht Parking)
    - LOGIK-FIX: MSI Mode nur reporten, nicht push (Default-AN bei modernen GPUs)
    - LOGIK-FIX: RAM EXPO via ConfiguredClockSpeed vs Speed

    Neue Checks:
    - Windows Build/Version
    - Defender Real-Time Exclusion fuer PUBG-Ordner
    - Hintergrund-Prozesse (Spotify/Chrome/Discord/Browser)
    - Display-Skalierung
    - PUBG Steam Launch Options
    - AMD 3D V-Cache Optimizer Service (bei X3D)
    - RAM-Konfiguration (2-DIMM vs 4-DIMM)
    - Game-Mode AN/AUS

    Neu pro Finding:
    - EverydayImpact-Feld (KEIN / GERING / MITTEL / HOCH) - Kosten der Optimierung im Alltag
    - AutoFix-Scriptblock (anwendbar ohne Admin)
    - AdminFix-Snippet (wird in elevated Script gebuendelt)

    Am Ende: interaktive Fix-Phase mit Bestaetigung pro Punkt.

.NOTES
    Erstanwendung: powershell -ExecutionPolicy Bypass -File "PUBG-Diagnose-v6.ps1"
    Keine Admin-Rechte noetig fuer Diagnose. Admin-Fixes werden separat als Script erzeugt.

    Parameter:
      -NonInteractive  Skip interaktive Fix-Phase + Admin-Script-Prompt.
                       Nur Diagnose + HTML-Report. Wird von PUBG-Suite genutzt.
#>

param(
    [switch]$NonInteractive
)

# ==================== KONFIGURATION ====================
$OutputFolder    = "$env:USERPROFILE\Desktop"
$ReportTitle     = "PUBG Competitive Setup - System Report v6"
$IncludePingTest = $true
$IncludePUBGIni  = $true
$PingCount       = 10
$EnableFixPhase  = (-not $NonInteractive)
# ========================================================


$ErrorActionPreference = 'SilentlyContinue'
$timestamp  = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$reportPath = Join-Path $OutputFolder "PUBGSystemReport_v6_$timestamp.html"
$Global:Findings = New-Object System.Collections.Generic.List[hashtable]

function Add-Finding {
    param(
        [string]$Section,
        [string]$Item,
        [string]$Value,
        [ValidateSet('OK','WARN','BAD','INFO','SKIP')]
        [string]$Status = 'INFO',
        [string]$Recommendation = '',
        [ValidateSet('','KEIN','GERING','MITTEL','HOCH')]
        [string]$EverydayImpact = '',
        [string]$ImpactDetail = '',
        [scriptblock]$AutoFix = $null,
        [string]$AdminFix = ''
    )
    $Global:Findings.Add(@{
        Section = $Section; Item = $Item; Value = $Value
        Status = $Status; Recommendation = $Recommendation
        EverydayImpact = $EverydayImpact; ImpactDetail = $ImpactDetail
        AutoFix = $AutoFix; AdminFix = $AdminFix
    })
}

function Write-Status {
    param([string]$Msg, [string]$Status = 'INFO')
    $color = switch ($Status) {
        'OK' {'Green'} 'WARN' {'Yellow'} 'BAD' {'Red'} 'SKIP' {'DarkGray'} default {'Cyan'}
    }
    Write-Host "[$Status] $Msg" -ForegroundColor $color
}

function Get-NPIPath {
    # NVIDIA Profile Inspector - sucht in Standardpfaden
    $candidates = @(
        'C:\Tools\nvidiaProfileInspector\nvidiaProfileInspector.exe',
        "$env:USERPROFILE\Tools\nvidiaProfileInspector\nvidiaProfileInspector.exe",
        "$env:USERPROFILE\Downloads\nvidiaProfileInspector\nvidiaProfileInspector.exe",
        "$env:USERPROFILE\Downloads\nvidiaProfileInspector.exe",
        "$env:USERPROFILE\Desktop\nvidiaProfileInspector\nvidiaProfileInspector.exe",
        "$env:USERPROFILE\Desktop\nvidiaProfileInspector.exe",
        'C:\Program Files\nvidiaProfileInspector\nvidiaProfileInspector.exe',
        'C:\nvidiaProfileInspector\nvidiaProfileInspector.exe'
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    try {
        $found = (& where.exe nvidiaProfileInspector.exe 2>$null) | Select-Object -First 1
        if ($found -and (Test-Path $found)) { return $found }
    } catch {}
    return $null
}

$Global:NPIStampPath = "$env:LOCALAPPDATA\PUBGDiag\npi-applied.stamp"
$Global:NPIDefaultDir = 'C:\Tools\nvidiaProfileInspector'

function Install-NPIFromGitHub {
    param([string]$TargetDir = $Global:NPIDefaultDir)

    try {
        # TLS 1.2 fuer aeltere PowerShell-Versionen
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        Write-Host "  Hole Release-Info von GitHub..." -ForegroundColor Cyan
        $apiUrl = 'https://api.github.com/repos/Orbmu2k/nvidiaProfileInspector/releases/latest'
        $headers = @{ 'User-Agent' = 'PUBG-Diag-PS' }
        $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
        $zipAsset = $release.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
        if (-not $zipAsset) { throw 'Kein ZIP-Asset im Release gefunden' }

        Write-Host "  Version: $($release.tag_name) ($([math]::Round($zipAsset.size / 1MB, 2)) MB)" -ForegroundColor Gray

        try {
            if (-not (Test-Path $TargetDir)) {
                New-Item -Path $TargetDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
        } catch {
            # C:\Tools meist nur als Admin schreibbar - fallback auf UserProfile
            $TargetDir = Join-Path $env:USERPROFILE 'Tools\nvidiaProfileInspector'
            Write-Host "  $($_.Exception.Message.Split([Environment]::NewLine)[0]) - fallback auf $TargetDir" -ForegroundColor Yellow
            if (-not (Test-Path $TargetDir)) {
                New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
            }
        }

        $zipPath = Join-Path $env:TEMP "npi_$($release.tag_name).zip"
        Write-Host "  Download laeuft..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipPath -UseBasicParsing -ErrorAction Stop

        Write-Host "  Entpacke nach $TargetDir..." -ForegroundColor Gray
        Expand-Archive -Path $zipPath -DestinationPath $TargetDir -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        $npiExe = Join-Path $TargetDir 'nvidiaProfileInspector.exe'
        if (-not (Test-Path $npiExe)) {
            # Manche Releases packen in einen Sub-Ordner
            $found = Get-ChildItem -Path $TargetDir -Recurse -Filter 'nvidiaProfileInspector.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $npiExe = $found.FullName }
        }
        if (Test-Path $npiExe) {
            Write-Host "  NPI installiert: $npiExe" -ForegroundColor Green
            return $npiExe
        }
        throw 'nvidiaProfileInspector.exe nicht im entpackten Archiv gefunden'
    } catch {
        Write-Host "  FEHLER beim NPI-Install: $_" -ForegroundColor Red
        return $null
    }
}

function Invoke-NPIPubgProfile {
    param([string]$NpiPath)
    $profileName = "PLAYERUNKNOWN'S BATTLEGROUNDS"

    # VERIFIZIERTE Setting-IDs aus NPI-Source (Stand 2025) - v4-IDs waren teilweise
    # falsch (z.B. Power Mgmt 0x1033CEC2 statt 0x1033DCD2)
    $settings = @(
        @{ Id='0x1033DCD2'; Val='0x00000001'; Desc='Power Management Mode = Prefer Max Performance' }
        @{ Id='0x00A879CF'; Val='0x00000000'; Desc='Vertical Sync = Force OFF' }
        @{ Id='0x00CE0E32'; Val='0x00000000'; Desc='Texture Filtering Quality = High Performance' }
        @{ Id='0x20FF7493'; Val='0x00000001'; Desc='Threaded Optimization = ON' }
        @{ Id='0x10835000'; Val='0x00000002'; Desc='Low Latency Mode = Ultra (Reflex-equivalent)' }
        @{ Id='0x10835013'; Val='0x000000ED'; Desc='Frame Rate Limiter v3 = 237 FPS' }
        @{ Id='0x00D55F7D'; Val='0x00000000'; Desc='Antialiasing Mode = Application Controlled' }
        @{ Id='0x101E61A9'; Val='0x00000002'; Desc='Anisotropic Filtering = Use Global' }
    )

    Write-Host "  Wende $($settings.Count) NPI-Settings auf PUBG-Profil an..." -ForegroundColor Cyan
    $applied = New-Object System.Collections.Generic.List[hashtable]
    $ok = 0; $fail = 0
    foreach ($s in $settings) {
        try {
            $output = & $NpiPath '-setProfileSetting' $profileName $s.Id $s.Val 2>&1
            if ($LASTEXITCODE -eq $null -or $LASTEXITCODE -eq 0) {
                Write-Host "    [OK]   $($s.Desc)" -ForegroundColor Green
                $ok++
                $applied.Add(@{ Id=$s.Id; Val=$s.Val; Desc=$s.Desc; State='Applied' })
            } else {
                Write-Host "    [FAIL] $($s.Desc) (Exit $LASTEXITCODE)" -ForegroundColor Red
                $fail++
                $applied.Add(@{ Id=$s.Id; Val=$s.Val; Desc=$s.Desc; State='Failed' })
            }
        } catch {
            Write-Host "    [ERR]  $($s.Desc): $($_.Exception.Message)" -ForegroundColor Red
            $fail++
            $applied.Add(@{ Id=$s.Id; Val=$s.Val; Desc=$s.Desc; State='Error' })
        }
    }
    Write-Host ""
    Write-Host "  Apply-Phase: $ok gesetzt, $fail Fehler" -ForegroundColor Yellow

    # Verifikation: Profil wieder auslesen
    Write-Host "  Verifikation laeuft..." -ForegroundColor Cyan
    $verifyResult = Test-NPIPubgProfile -NpiPath $NpiPath -Expected $settings
    if ($verifyResult.Success) {
        Write-Host ""
        Write-Host "  === VERIFIKATIONS-ERGEBNIS ===" -ForegroundColor Cyan
        $verOk = 0; $verMismatch = 0; $verMissing = 0
        foreach ($s in $settings) {
            $idLower = $s.Id.ToLower() -replace '^0x',''
            $foundVal = $null
            foreach ($k in $verifyResult.Settings.Keys) {
                if (($k.ToLower() -replace '^0x','') -eq $idLower) {
                    $foundVal = $verifyResult.Settings[$k]; break
                }
            }
            if ($null -eq $foundVal) {
                Write-Host "    [?]    $($s.Desc): nicht im Export gefunden" -ForegroundColor DarkGray
                $verMissing++
            } else {
                $expectedNum = [Convert]::ToInt32($s.Val, 16)
                $foundNum = if ($foundVal -match '^0x') { [Convert]::ToInt32($foundVal, 16) } else { [int]$foundVal }
                if ($expectedNum -eq $foundNum) {
                    Write-Host "    [OK]   $($s.Desc): bestaetigt" -ForegroundColor Green
                    $verOk++
                } else {
                    Write-Host "    [DIFF] $($s.Desc): Soll=$($s.Val) / Ist=$foundVal" -ForegroundColor Yellow
                    $verMismatch++
                }
            }
        }
        Write-Host ""
        Write-Host "  Verify: $verOk bestaetigt / $verMismatch abweichend / $verMissing nicht im Export" -ForegroundColor Yellow
    } else {
        Write-Host "  Verifikation nicht moeglich: $($verifyResult.Reason)" -ForegroundColor DarkGray
        Write-Host "  Manuell pruefen via NPI GUI -> Profil 'PLAYERUNKNOWN'S BATTLEGROUNDS' auswaehlen" -ForegroundColor DarkGray
    }

    # Stamp mit erweiterten Daten
    $sd = Split-Path $Global:NPIStampPath -Parent
    if (-not (Test-Path $sd)) { New-Item -Path $sd -ItemType Directory -Force | Out-Null }
    $stampData = @{
        Date = (Get-Date).ToString('o')
        ApplyOk = $ok
        ApplyFail = $fail
        Settings = $applied
    }
    $stampData | ConvertTo-Json -Depth 4 | Out-File $Global:NPIStampPath -Force
}

function Test-NPIPubgProfile {
    param([string]$NpiPath, [array]$Expected)

    $exportFile = Join-Path $env:TEMP "pubg_npi_verify_$(Get-Random).nip"
    try {
        # NPI export - Syntax variiert zwischen Versionen, versuche beide
        $tried = @()
        $null = & $NpiPath '-exportprofile' "PLAYERUNKNOWN'S BATTLEGROUNDS" $exportFile 2>&1
        $tried += 'exportprofile'
        if (-not (Test-Path $exportFile)) {
            $null = & $NpiPath "-export=$exportFile" 2>&1
            $tried += 'export='
        }
        if (-not (Test-Path $exportFile)) {
            return @{ Success = $false; Reason = "Export schlug fehl (versuchte: $($tried -join ', '))" }
        }

        $content = Get-Content $exportFile -Raw
        Remove-Item $exportFile -Force -ErrorAction SilentlyContinue

        # Parse XML
        $xml = [xml]$content
        $found = @{}
        $nodes = $xml.SelectNodes('//ProfileSetting')
        if ($nodes.Count -eq 0) {
            $nodes = $xml.SelectNodes('//Profile/Settings/ProfileSetting')
        }
        foreach ($node in $nodes) {
            $id = $node.SettingID
            $val = $node.SettingValue
            if ($id -and $val) {
                $found[$id] = $val
            }
        }
        return @{ Success = $true; Settings = $found; FoundCount = $found.Count }
    } catch {
        return @{ Success = $false; Reason = $_.Exception.Message }
    }
}

function Get-PUBGGpuVRAM {
    param($gpuObj)
    # 1) nvidia-smi (genau)
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
    # 2) Registry HardwareInformation.qwMemorySize (64-bit korrekt)
    try {
        $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        $subkeys = Get-ChildItem $cls -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' }
        foreach ($k in $subkeys) {
            $props = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
            if ($props.'HardwareInformation.AdapterString' -and $gpuObj.Name -match [regex]::Escape(($props.'HardwareInformation.AdapterString' -replace 'NVIDIA |AMD ',''))) {
                $qw = $props.'HardwareInformation.qwMemorySize'
                if ($qw) {
                    return @{ GB = [math]::Round($qw / 1GB, 1); Source = 'Registry' }
                }
            }
        }
    } catch {}
    # 3) Fallback - Win32 (kaputt bei >4GB)
    if ($gpuObj.AdapterRAM) {
        return @{ GB = [math]::Round($gpuObj.AdapterRAM / 1GB, 1); Source = 'Win32 (ungenau bei >4GB)' }
    }
    return $null
}

function Edit-PUBGEngineIni {
    param([string]$IniPath, [hashtable]$DesiredSections, [string]$Timestamp)

    # Backup
    if (Test-Path $IniPath) {
        Copy-Item $IniPath "$IniPath.bak_$Timestamp" -Force -ErrorAction SilentlyContinue
    } else {
        $dir = Split-Path $IniPath -Parent
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        Set-Content -Path $IniPath -Value '' -NoNewline
    }

    $content = (Get-Content $IniPath -Raw) -replace "`r`n","`n"
    if ($null -eq $content) { $content = '' }

    foreach ($section in $DesiredSections.Keys) {
        $sectionTag = "[$section]"
        $sectionPattern = "(?ms)^\[" + [regex]::Escape($section) + "\]\s*\r?\n(.*?)(?=^\[|\z)"

        if ($content -match $sectionPattern) {
            $sectionBody = $matches[1]
            $newBody = $sectionBody
            foreach ($key in $DesiredSections[$section].Keys) {
                $val = $DesiredSections[$section][$key]
                $keyPattern = "(?m)^\s*" + [regex]::Escape($key) + "\s*=.*$"
                if ($newBody -match $keyPattern) {
                    $newBody = $newBody -replace $keyPattern, "$key=$val"
                } else {
                    $newBody = $newBody.TrimEnd() + "`n$key=$val`n"
                }
            }
            $content = $content -replace $sectionPattern, ($sectionTag + "`n" + $newBody)
        } else {
            $append = "`n$sectionTag`n"
            foreach ($key in $DesiredSections[$section].Keys) {
                $append += "$key=$($DesiredSections[$section][$key])`n"
            }
            $content = $content.TrimEnd() + "`n" + $append
        }
    }

    Set-Content -Path $IniPath -Value $content -NoNewline
}

function Test-PUBGEngineIniTweaks {
    param([string]$IniPath, [hashtable]$Expected)
    $missing = @()
    if (-not (Test-Path $IniPath)) {
        foreach ($section in $Expected.Keys) {
            foreach ($key in $Expected[$section].Keys) {
                $missing += "[$section] $key"
            }
        }
        return @{ AllPresent = $false; Missing = $missing; FileExists = $false }
    }
    $content = (Get-Content $IniPath -Raw) -replace "`r`n","`n"
    foreach ($section in $Expected.Keys) {
        $sectionPattern = "(?ms)^\[" + [regex]::Escape($section) + "\]\s*\r?\n(.*?)(?=^\[|\z)"
        $sectionBody = ''
        if ($content -match $sectionPattern) { $sectionBody = $matches[1] }
        foreach ($key in $Expected[$section].Keys) {
            $expVal = $Expected[$section][$key]
            $keyPattern = "(?m)^\s*" + [regex]::Escape($key) + "\s*=\s*" + [regex]::Escape($expVal) + "\s*$"
            if ($sectionBody -notmatch $keyPattern) {
                $missing += "[$section] $key=$expVal"
            }
        }
    }
    return @{ AllPresent = ($missing.Count -eq 0); Missing = $missing; FileExists = $true }
}

# Konfiguration: Welche Engine.ini Tweaks sollen drin sein (BattlEye-safe)
$Global:EngineIniTweaks = @{
    'SystemSettings' = [ordered]@{
        'r.Tonemapper.Sharpen' = '0.7'
        'r.OneFrameThreadLag' = '0'
        'r.FinishCurrentFrame' = '0'
        'r.GTSyncType' = '1'
    }
    '/Script/Engine.RendererSettings' = [ordered]@{
        'r.Streaming.PoolSize' = '4096'
        'r.Streaming.HLODStrategy' = '2'
        'r.Streaming.FramesForFullUpdate' = '1'
    }
}

function Get-TimerResolutionMs {
    # Aktuelle Windows Timer Resolution via NtQueryTimerResolution
    try {
        if (-not ([System.Management.Automation.PSTypeName]'PInvoke.TimerRes').Type) {
            $sig = @'
[DllImport("ntdll.dll")]
public static extern int NtQueryTimerResolution(out uint MinResolution, out uint MaxResolution, out uint CurrentResolution);
'@
            Add-Type -MemberDefinition $sig -Name 'TimerRes' -Namespace 'PInvoke' -ErrorAction Stop | Out-Null
        }
        $min = 0; $max = 0; $cur = 0
        $null = [PInvoke.TimerRes]::NtQueryTimerResolution([ref]$min, [ref]$max, [ref]$cur)
        return @{ CurrentMs = [math]::Round($cur / 10000, 4); MinMs = [math]::Round($min / 10000, 4); MaxMs = [math]::Round($max / 10000, 4) }
    } catch {
        return $null
    }
}

Write-Host "`n=== PUBG System Report v6 wird erstellt ===`n" -ForegroundColor Cyan


# ==================== 1. PRIMAERER MONITOR ====================
Write-Status "Primaerer Monitor wird identifiziert..." 'INFO'

Add-Type -AssemblyName System.Windows.Forms

$videoControllers = Get-CimInstance -ClassName Win32_VideoController |
    Where-Object { $_.CurrentRefreshRate -gt 0 -and $_.VideoModeDescription }

$primaryCtrl = $videoControllers | Sort-Object -Property CurrentRefreshRate -Descending | Select-Object -First 1

if ($primaryCtrl) {
    $activeHz  = $primaryCtrl.CurrentRefreshRate
    $activeRes = "$($primaryCtrl.CurrentHorizontalResolution) x $($primaryCtrl.CurrentVerticalResolution)"

    $hzStatus = if ($activeHz -ge 240) {'OK'} elseif ($activeHz -ge 144) {'OK'} elseif ($activeHz -ge 120) {'WARN'} else {'BAD'}
    $hzReco = if ($activeHz -lt 144) {'Fuer Competitive PUBG mind. 144 Hz - Windows Anzeige-Einstellungen pruefen'} else {''}

    Add-Finding 'Monitor (Primary)' 'Aktive Refreshrate' "$activeHz Hz" $hzStatus $hzReco
    Add-Finding 'Monitor (Primary)' 'Aktive Aufloesung' $activeRes 'INFO'

    $pixels = $primaryCtrl.CurrentHorizontalResolution * $primaryCtrl.CurrentVerticalResolution
    if ($pixels -gt 2073600) {
        Add-Finding 'Monitor (Primary)' 'Aufloesungs-Hinweis' 'Hoeher als 1920x1080' 'INFO' 'Competitive: viele Pros nutzen 1920x1080 fuer max. FPS. Bei 5080 wahrscheinlich egal'
    }
}

# Multi-Monitor Hinweis
$allActive = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue | Where-Object { $_.Active -eq $true }
if ($allActive -and $allActive.Count -gt 1) {
    Add-Finding 'Monitor (Primary)' 'Multi-Monitor erkannt' "$($allActive.Count) aktive Monitore" 'INFO' 'Bei mehreren Monitoren kann die Primary-Erkennung mischen. Hz/Modell ggf. inkonsistent reportet'
}

try {
    $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop
    $activeMonitor = $monitors | Where-Object { $_.Active -eq $true } | Select-Object -First 1
    if (-not $activeMonitor) { $activeMonitor = $monitors | Select-Object -First 1 }

    if ($activeMonitor) {
        $manu  = ($activeMonitor.ManufacturerName | Where-Object {$_ -ne 0} | ForEach-Object {[char]$_}) -join ''
        $model = ($activeMonitor.UserFriendlyName  | Where-Object {$_ -ne 0} | ForEach-Object {[char]$_}) -join ''
        Add-Finding 'Monitor (Primary)' 'Modell (EDID)' "$manu $model" 'INFO'
    }

    $supportedModes = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorListedSupportedSourceModes -ErrorAction Stop
    $allHz = $supportedModes.MonitorSourceModes | ForEach-Object { $_.VerticalRefreshRate }
    $maxHz = ($allHz | Sort-Object -Descending | Select-Object -First 1)

    if ($maxHz -and $primaryCtrl) {
        if ($primaryCtrl.CurrentRefreshRate -lt $maxHz) {
            Add-Finding 'Monitor (Primary)' 'Max. unterstuetzte Hz (EDID)' "$maxHz Hz" 'WARN' "Active $($primaryCtrl.CurrentRefreshRate) Hz / Max $maxHz Hz - ggf. in Windows Anzeige umstellen (oder bewusst gecappt)" 'KEIN'
        } else {
            Add-Finding 'Monitor (Primary)' 'Max. unterstuetzte Hz (EDID)' "$maxHz Hz" 'OK'
        }
    }
}
catch {
    Add-Finding 'Monitor (Primary)' 'EDID-Auslesung' 'nicht moeglich' 'SKIP'
}


# ==================== 2. DEDIZIERTE GPU ====================
Write-Status "Dedizierte GPU wird identifiziert..." 'INFO'

$allGpus = Get-CimInstance -ClassName Win32_VideoController
$dGpu = $allGpus | Where-Object {
    $_.Name -match 'NVIDIA|GeForce|RTX|GTX|Quadro|Radeon RX|Radeon Pro' -and
    $_.Name -notmatch 'Vega.*Graphics|Radeon Graphics$|UHD|Iris|HD Graphics'
} | Select-Object -First 1

if (-not $dGpu) {
    $dGpu = $allGpus | Sort-Object -Property AdapterRAM -Descending | Select-Object -First 1
    Add-Finding 'GPU (dediziert)' 'Hinweis' 'Keine dGPU eindeutig erkannt' 'WARN'
}

if ($dGpu) {
    Add-Finding 'GPU (dediziert)' 'Modell' $dGpu.Name 'INFO'

    # FIX v4: VRAM korrekt
    $vramInfo = Get-PUBGGpuVRAM -gpuObj $dGpu
    if ($vramInfo) {
        $vram = $vramInfo.GB
        $vramStatus = if ($vram -ge 8) {'OK'} elseif ($vram -ge 6) {'WARN'} else {'BAD'}
        Add-Finding 'GPU (dediziert)' 'VRAM' "$vram GB (Quelle: $($vramInfo.Source))" $vramStatus
    }

    Add-Finding 'GPU (dediziert)' 'Treiber-Version' $dGpu.DriverVersion 'INFO'
    Add-Finding 'GPU (dediziert)' 'Treiber-Datum' $dGpu.DriverDate 'INFO'

    if ($dGpu.DriverDate) {
        $ageDays = (New-TimeSpan -Start $dGpu.DriverDate -End (Get-Date)).Days
        $drvStatus = if ($ageDays -lt 90) {'OK'} elseif ($ageDays -lt 180) {'WARN'} else {'BAD'}
        $drvReco = if ($ageDays -ge 90) {"Treiber $ageDays Tage alt - Update via GeForce Experience / AMD Adrenalin"} else {''}
        Add-Finding 'GPU (dediziert)' 'Treiber-Alter' "$ageDays Tage" $drvStatus $drvReco
    }

    # LOGIK-FIX v4: MSI Mode nur reporten, nicht push (RTX 4000+/RX 7000+ haben das schon AN by default)
    if ($dGpu.PNPDeviceID) {
        $msiPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dGpu.PNPDeviceID)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
        if (Test-Path $msiPath) {
            $msi = Get-ItemProperty -Path $msiPath -Name 'MSISupported' -ErrorAction SilentlyContinue
            if ($null -ne $msi.MSISupported) {
                $msiVal = if ($msi.MSISupported -eq 1) {'AN (MSI)'} else {'AUS (Line-Based)'}
                # Moderne GPUs haben MSI per Default an - nur als INFO/WARN reporten
                $msiStatus = if ($msi.MSISupported -eq 1) {'OK'} else {'WARN'}
                $msiReco   = if ($msi.MSISupported -ne 1) {'MSI Mode via MSI Util v3 aktivieren - in 2025 bei modernen GPUs aber meist schon AN. Verify-Only, nicht aggressiv twiddeln'} else {''}
                Add-Finding 'GPU (dediziert)' 'MSI Mode (IRQ)' $msiVal $msiStatus $msiReco 'KEIN'
            }
        }
    }

    # NVIDIA Live-Daten
    $nvSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($nvSmi -and $dGpu.Name -match 'NVIDIA|GeForce|RTX|GTX|Quadro') {
        try {
            $nvOutput = & nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1
            if ($nvOutput) {
                $nvParts = ($nvOutput -split ',') | ForEach-Object { $_.Trim() }
                $gpuTemp = [int]$nvParts[0]
                $gpuUtil = [int]$nvParts[1]
                $vramUsed = [int]$nvParts[2]
                $vramTotal = [int]$nvParts[3]

                $tempStatus = if ($gpuTemp -lt 60) {'OK'} elseif ($gpuTemp -lt 75) {'WARN'} else {'BAD'}
                Add-Finding 'GPU (dediziert)' 'GPU-Temperatur (live)' "$gpuTemp C" $tempStatus
                Add-Finding 'GPU (dediziert)' 'GPU-Auslastung (live)' "$gpuUtil %" 'INFO'
                Add-Finding 'GPU (dediziert)' 'VRAM-Belegung (live)' "$vramUsed / $vramTotal MB" 'INFO'
            }
        } catch {
            Add-Finding 'GPU (dediziert)' 'nvidia-smi' 'Fehler' 'SKIP'
        }

        # NPI-Integration: Profile-Inspector finden, Stamp pruefen, Auto-Apply anbieten
        $script:nvGpuFound = $true
        $script:npiPathCaptured = Get-NPIPath
        $script:npiMissing = (-not $script:npiPathCaptured)
        $npiAlreadyApplied = $false
        $npiStampAge = $null
        if (Test-Path $Global:NPIStampPath) {
            $npiStampAge = (Get-Date) - (Get-Item $Global:NPIStampPath).LastWriteTime
            # 60 Tage Cache - danach erneut anbieten falls NV-Treiber-Update das Profil resettet hat
            if ($npiStampAge.TotalDays -lt 60) { $npiAlreadyApplied = $true }
        }

        if ($script:npiPathCaptured) {
            Add-Finding 'GPU (dediziert)' 'NVIDIA Profile Inspector' $script:npiPathCaptured 'OK'

            if ($npiAlreadyApplied) {
                $daysAgo = [int]$npiStampAge.TotalDays
                $whenTxt = if ($daysAgo -eq 0) {'heute'} else {"vor $daysAgo Tag(en)"}
                Add-Finding 'GPU (dediziert)' 'NV-Profil PUBG' "applied $whenTxt" 'OK'
            } else {
                Add-Finding 'GPU (dediziert)' 'NV-Profil PUBG (Low Latency etc.)' 'NPI verfuegbar - Auto-Apply moeglich' 'WARN' 'Setzt: Low Latency=Ultra, Power=Max Perf, Texture Filtering=High Perf, Threaded Opt=AN. G-Sync bleibt manuell (global setting)' 'KEIN' '' {
                    Invoke-NPIPubgProfile -NpiPath $script:npiPathCaptured
                }
            }
        } else {
            Add-Finding 'GPU (dediziert)' 'NV-Profil PUBG' 'NPI nicht gefunden' 'WARN' 'Fuer Auto-Apply: NVIDIA Profile Inspector laden (https://github.com/Orbmu2k/nvidiaProfileInspector), entpacken nach C:\Tools\nvidiaProfileInspector\ - dann Script erneut. Manuell: NV Control Panel > 3D-Einstellungen > Programmeinstellungen > TslGame.exe > Low Latency=Ultra, Power=Max Perf, Texture Filtering=High Perf' 'KEIN'
        }
    } elseif ($dGpu.Name -match 'Radeon|AMD') {
        Add-Finding 'GPU (dediziert)' 'AMD Adrenalin (manuell)' 'siehe Empfehlung' 'INFO' 'Fuer PUBG: Anti-Lag+ = AN (falls verfuegbar), Radeon Boost = AUS, Image Sharpening = AUS, FreeSync = AN'
    }
}


# ==================== 3. CPU & RAM ====================
Write-Status "CPU/RAM-Informationen werden ausgelesen..." 'INFO'
$cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
Add-Finding 'CPU/RAM' 'CPU-Modell' $cpu.Name 'INFO'

# X3D-Detektion fuer korrekte Core-Parking-Logik
$isX3D = ($cpu.Name -match 'X3D')

$cores   = $cpu.NumberOfCores
$threads = $cpu.NumberOfLogicalProcessors
$cpuStatus = if ($cores -ge 8) {'OK'} elseif ($cores -ge 6) {'OK'} elseif ($cores -ge 4) {'WARN'} else {'BAD'}
$cpuReco = if ($cpuStatus -eq 'BAD') {'Unter 4 Kerne wird in PUBG kritisch'} else {''}
Add-Finding 'CPU/RAM' 'Kerne / Threads' "$cores / $threads" $cpuStatus $cpuReco

if ($isX3D) {
    Add-Finding 'CPU/RAM' 'X3D-CPU erkannt' 'JA' 'INFO' 'V-Cache-CCD wird fuer Games genutzt. Core-Parking AUS lassen, Xbox Game Bar registrieren'

    # AMD 3D V-Cache Optimizer Service Check
    $svcs = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '3DVCache|AMD3DVCache' }
    if ($svcs) {
        $svc = $svcs | Select-Object -First 1
        $svcStatus = if ($svc.Status -eq 'Running') {'OK'} else {'WARN'}
        Add-Finding 'CPU/RAM' 'AMD 3D V-Cache Service' "$($svc.Name) - $($svc.Status)" $svcStatus $(if ($svc.Status -ne 'Running') {'Service sollte laufen - koordiniert Xbox Game Bar mit X3D-Scheduler'} else {''})
    } else {
        Add-Finding 'CPU/RAM' 'AMD 3D V-Cache Optimizer' 'Service nicht gefunden' 'WARN' 'Aktuellsten AMD Chipset-Treiber installieren (amd.com/de/support) - bringt den V-Cache Optimizer mit' 'KEIN'
    }
}

$ram = @(Get-CimInstance -ClassName Win32_PhysicalMemory)
$totalRAM = [math]::Round(($ram | Measure-Object -Property Capacity -Sum).Sum / 1GB, 0)
$ramStatus = if ($totalRAM -ge 32) {'OK'} elseif ($totalRAM -ge 16) {'OK'} else {'BAD'}
$ramReco = if ($totalRAM -lt 16) {'16 GB Minimum, 32 GB empfohlen'} else {''}
Add-Finding 'CPU/RAM' 'RAM gesamt' "$totalRAM GB" $ramStatus $ramReco

# NEU v4: 2-DIMM vs 4-DIMM Hinweis
$ramSticks = $ram.Count
if ($ramSticks -gt 0) {
    $ramFirst = $ram[0]
    Add-Finding 'CPU/RAM' 'RAM-Module' "$ramSticks DIMM(s)" 'INFO'

    $memType  = $ramFirst.SMBIOSMemoryType
    $memTypeText = switch ($memType) {
        20 { 'DDR' } 21 { 'DDR2' } 24 { 'DDR3' } 26 { 'DDR4' } 34 { 'DDR5' } 35 { 'DDR5' }
        default { "Type-$memType" }
    }
    Add-Finding 'CPU/RAM' 'RAM-Typ' $memTypeText 'INFO'

    # NEU v4: 4-DIMM-DDR5 schwerer zu OCen
    if ($ramSticks -eq 4 -and ($memType -eq 34 -or $memType -eq 35)) {
        Add-Finding 'CPU/RAM' 'RAM-Layout 4-DIMM DDR5' '4 Module bestueckt' 'WARN' '4-DIMM DDR5 schwer auf 6000 MT/s+ stabil zu bekommen. 2x32GB statt 4x16GB ergibt mehr OC-Headroom' 'HOCH' 'Hardware-Upgrade noetig, nur planen falls EXPO instabil'
    }

    # LOGIK-FIX v4: EXPO-Status via Speed vs ConfiguredClockSpeed
    $ramRated      = $ramFirst.Speed
    $ramConfigured = $ramFirst.ConfiguredClockSpeed
    if (-not $ramConfigured) { $ramConfigured = $ramRated }

    if ($ramRated -and $ramConfigured) {
        $expoActive = ($ramRated -le ($ramConfigured + 50))  # Toleranz
        if ($memType -eq 34 -or $memType -eq 35) {
            # DDR5
            $expoStatus = if ($ramConfigured -ge 6000) {'OK'} elseif ($ramConfigured -ge 5200) {'WARN'} else {'BAD'}
            $expoReco = if ($ramConfigured -lt 5200) {
                'DDR5 laeuft auf JEDEC. EXPO im BIOS aktivieren. Auf 7950X3D: 6000 CL30 bringt 8-15% bessere 1%-Lows in PUBG'
            } elseif ($ramConfigured -lt 6000) {
                'Akzeptabel aber 6000 CL30 ist der Sweet-Spot fuer 7950X3D'
            } else {''}
        } else {
            # DDR4
            $expoStatus = if ($ramConfigured -ge 3600) {'OK'} elseif ($ramConfigured -ge 3200) {'OK'} elseif ($ramConfigured -ge 3000) {'WARN'} else {'BAD'}
            $expoReco = if ($ramConfigured -lt 3000) {'DDR4 laeuft auf JEDEC. XMP im BIOS aktivieren'} else {''}
        }
        Add-Finding 'CPU/RAM' 'RAM-Takt (aktiv)' "$ramConfigured MT/s (Rated: $ramRated)" $expoStatus $expoReco 'GERING' 'EXPO/XMP-Aktivierung erfordert BIOS-Reboot. Auf 7950X3D mit 24+ AGESA stabil. Selten leicht laengere POST-Zeit'
    }
}


# ==================== 4. SPEICHER (PUBG-INSTALL) ====================
Write-Status "Storage-Typ fuer PUBG-Installation..." 'INFO'

$steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
if (-not $steamPath) {
    $steamPath = (Get-ItemProperty 'HKLM:\Software\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
}
if (-not $steamPath) {
    $steamPath = (Get-ItemProperty 'HKLM:\Software\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
}

$pubgInstallPath = $null
if ($steamPath -and (Test-Path $steamPath)) {
    Add-Finding 'Speicher' 'Steam-Installation' $steamPath 'INFO'

    $libFile = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path $libFile) {
        $libContent = Get-Content $libFile -Raw
        $libMatches = [regex]::Matches($libContent, '"path"\s+"([^"]+)"')
        $libs = $libMatches | ForEach-Object { $_.Groups[1].Value -replace '\\\\','\' }

        foreach ($lib in $libs) {
            $manifest = Join-Path $lib 'steamapps\appmanifest_578080.acf'
            if (Test-Path $manifest) {
                $manifestContent = Get-Content $manifest -Raw
                if ($manifestContent -match '"installdir"\s+"([^"]+)"') {
                    $installDir = $matches[1]
                    $pubgInstallPath = Join-Path $lib "steamapps\common\$installDir"
                }
                break
            }
        }
    }
}

if ($pubgInstallPath -and (Test-Path $pubgInstallPath)) {
    Add-Finding 'Speicher' 'PUBG-Installationspfad' $pubgInstallPath 'INFO'

    try {
        $driveLetter = (Get-Item $pubgInstallPath).PSDrive.Name
        $partition = Get-Partition -DriveLetter $driveLetter -ErrorAction Stop
        $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
        $physDisk = Get-PhysicalDisk -DeviceNumber $partition.DiskNumber -ErrorAction Stop

        $busType   = $disk.BusType
        $mediaType = $physDisk.MediaType
        $diskModel = $physDisk.FriendlyName

        Add-Finding 'Speicher' 'Datentraeger Modell' $diskModel 'INFO'

        $busStatus = if ($busType -eq 'NVMe') {'OK'} elseif ($busType -in 'SATA','SAS') {'WARN'} else {'BAD'}
        Add-Finding 'Speicher' 'PUBG Drive Bus' $busType $busStatus

        $mediaStatus = if ($mediaType -eq 'SSD') {'OK'} elseif ($mediaType -eq 'HDD') {'BAD'} else {'INFO'}
        Add-Finding 'Speicher' 'PUBG Drive Typ' $mediaType $mediaStatus

        $vol = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
        if ($vol) {
            $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
            $totGB  = [math]::Round($vol.Size / 1GB, 1)
            $freePct = if ($vol.Size -gt 0) { [math]::Round(($vol.SizeRemaining / $vol.Size) * 100, 1) } else { 0 }
            $freeStatus = if ($freePct -gt 15) {'OK'} elseif ($freePct -gt 10) {'WARN'} else {'BAD'}
            Add-Finding 'Speicher' 'Freier Speicher PUBG-Drive' "$freeGB / $totGB GB ($freePct %)" $freeStatus
        }
    } catch {
        Add-Finding 'Speicher' 'Datentraeger-Analyse' 'Fehler beim Auslesen' 'SKIP'
    }
} else {
    Add-Finding 'Speicher' 'PUBG-Installation' 'nicht gefunden' 'SKIP'
}


# ==================== 5. WINDOWS GAMING-RELEVANT ====================
Write-Status "Windows Gaming-Settings werden geprueft..." 'INFO'

# Win-Version
$os = Get-CimInstance Win32_OperatingSystem
$winDisplayVer = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion
$ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).UBR
Add-Finding 'Windows' 'Windows Version' "$($os.Caption) $winDisplayVer (Build $($os.BuildNumber).$ubr)" 'INFO'

# Energieplan
# FIX v4.3: Pruefe via GUID, nicht via lokalisiertem Namen (Encoding-/Umlaut-unabhaengig)
$activePlan = powercfg /getactivescheme
$planGuid = $null
if ($activePlan -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
    $planGuid = $matches[1].ToLower()
}
$planName = if ($activePlan -match '\((.+)\)') { $matches[1] } else { '?' }

# Bekannte Gaming-relevante GUIDs
$guidHigh     = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'  # Hoechstleistung
$guidUltimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'  # Ultimative Leistung
$guidBalanced = '381b4222-f694-41f0-9685-ff5bb260df2e'  # Ausbalanciert

if ($planGuid -eq $guidHigh -or $planGuid -eq $guidUltimate) {
    $planStatus = 'OK'
    $planReco = ''
} elseif ($planGuid -eq $guidBalanced) {
    $planStatus = 'WARN'
    $planReco = 'Auf Hoechstleistung umstellen - kleiner aber gratis Gewinn'
} else {
    # Custom Plan / AMD Ryzen High Performance / unbekannt - via Namen heuristisch raten
    if ($planName -match 'chstleistung|High performance|Ultimate|Ultimative|Performance') {
        $planStatus = 'OK'
        $planReco = ''
    } else {
        $planStatus = 'WARN'
        $planReco = 'Custom Plan erkannt - falls nicht performance-optimiert, auf Hoechstleistung wechseln'
    }
}

$autoFixPlan = $null
if ($planStatus -eq 'WARN') {
    $autoFixPlan = {
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null
        Write-Host '    -> Energieplan auf Hoechstleistung umgestellt' -ForegroundColor Green
    }
}
Add-Finding 'Windows' 'Energieplan' "$planName ($planGuid)" $planStatus $planReco 'GERING' 'Hoechstleistung haelt CPU bei voller Frequenz - leicht hoeherer Idle-Verbrauch (~5W), aber 7950X3D Boost-Verhalten gleich' $autoFixPlan

# Core Parking - X3D-aware
try {
    $parkOut = (powercfg /q SCHEME_CURRENT SUB_PROCESSOR 0cc5b647-c1df-4637-891a-dec35c318583 2>$null) -join "`n"
    if ($parkOut) {
        $lines = $parkOut -split "`r?`n"
        $currentLines = $lines | Where-Object { $_ -match '0x[0-9a-fA-F]+' -and $_ -match 'Aktuell|Current' }
        if (-not $currentLines) {
            $currentLines = $lines | Where-Object {
                $_ -match '0x[0-9a-fA-F]+' -and
                $_ -notmatch 'Min Possible|Max Possible|Increment|Mindest|Hoechst|Erhoeh|Moeglich|GUID'
            }
        }
        if ($currentLines -and ($currentLines | Select-Object -First 1) -match '0x([0-9a-fA-F]+)') {
            $parkMin = [Convert]::ToInt32($matches[1], 16)

            if ($isX3D) {
                # LOGIK-FIX v4: X3D braucht Parking AKTIV (niedrige Min Cores)
                $pkStatus = if ($parkMin -le 25) {'OK'} elseif ($parkMin -le 75) {'WARN'} else {'BAD'}
                $pkReco = if ($parkMin -gt 25) {
                    "Min Cores = $parkMin %. Auf X3D NICHT 100 setzen - Scheduler braucht Parking um Games aufs V-Cache-CCD zu pinnen. Default ~5 % zurueckstellen"
                } else {''}
                $autoFixPark = $null
                if ($pkStatus -ne 'OK') {
                    $autoFixPark = {
                        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 0cc5b647-c1df-4637-891a-dec35c318583 5 | Out-Null
                        powercfg /setactive SCHEME_CURRENT | Out-Null
                        Write-Host '    -> Core Parking Min Cores AC auf 5 % zurueckgesetzt (X3D-konform)' -ForegroundColor Green
                    }
                }
                Add-Finding 'Windows' 'CPU Core Parking (Min Cores AC)' "$parkMin % - X3D-Modus" $pkStatus $pkReco 'KEIN' 'Wichtig: bei X3D bringt Parking-Disable bis -15 % FPS in PUBG' $autoFixPark
            } else {
                # Non-X3D: 100 % ist OK
                $pkStatus = if ($parkMin -eq 100) {'OK'} elseif ($parkMin -ge 50) {'WARN'} else {'BAD'}
                $pkReco = if ($parkMin -lt 100) { 'Min Cores = 100 % setzen (verhindert Park-Latenz)' } else { '' }
                $autoFixPark = $null
                if ($pkStatus -ne 'OK') {
                    $autoFixPark = {
                        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 0cc5b647-c1df-4637-891a-dec35c318583 100 | Out-Null
                        powercfg /setactive SCHEME_CURRENT | Out-Null
                        Write-Host '    -> Core Parking Min Cores AC auf 100 % gesetzt' -ForegroundColor Green
                    }
                }
                Add-Finding 'Windows' 'CPU Core Parking (Min Cores AC)' "$parkMin %" $pkStatus $pkReco 'GERING' 'Hoeherer Idle-Verbrauch (~3-8W). Auf X3D-CPUs anders! Hier aber kein X3D' $autoFixPark
            }
        }
    }
} catch {
    Add-Finding 'Windows' 'CPU Core Parking' 'nicht ermittelbar' 'SKIP'
}

# Reboot-Pending Detection (relevant fuer VBS/HVCI Status nach Admin-Fix)
$rebootPending = $false
$rebootReasons = @()
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
    $rebootPending = $true; $rebootReasons += 'CBS'
}
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
    $rebootPending = $true; $rebootReasons += 'WindowsUpdate'
}
$pfro = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
if ($pfro) { $rebootPending = $true; $rebootReasons += 'PendingFileRename' }

# VBS Registry-State pruefen (gesetzt-aber-nicht-uebernommen erkennen)
$vbsRegOff = $false
$hvciRegOff = $false
try {
    $vbsRegVal = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'EnableVirtualizationBasedSecurity' -ErrorAction Stop).EnableVirtualizationBasedSecurity
    if ($vbsRegVal -eq 0) { $vbsRegOff = $true }
} catch {}
try {
    $hvciRegVal = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled' -ErrorAction Stop).Enabled
    if ($hvciRegVal -eq 0) { $hvciRegOff = $true }
} catch {}
$hyperLaunchOff = $false
try {
    $bcd = bcdedit /enum '{current}' 2>$null
    if ($bcd -match 'hypervisorlaunchtype\s+Off') { $hyperLaunchOff = $true }
} catch {}

# NEU v4.2: Detektion ob Hyper-V/SAC VBS erzwingen (dann ist es kein Reboot-Pending sondern stuck-on)
$hvForcingVBS = @()
$hvSvcMap = @{
    'vmms' = 'Hyper-V VMMS'
    'vmcompute' = 'Hyper-V Host Compute'
    'hvhost' = 'Hyper-V Host'
    'WslService' = 'WSL2'
    'LxssManager' = 'WSL'
}
foreach ($svcName in $hvSvcMap.Keys) {
    $s = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq 'Running') { $hvForcingVBS += $hvSvcMap[$svcName] }
}
# Smart App Control
$sacState = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name 'VerifiedAndReputablePolicyState' -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
$sacOn = ($null -ne $sacState -and $sacState -ne 0)
if ($sacOn) { $hvForcingVBS += 'Smart App Control' }

# Reboot-Pending Warnung NUR wenn echte Reboot-Indikatoren vorhanden ODER Reg-Off ohne Hyper-V-Erzwingung
$realRebootPending = ($rebootPending) -or (($vbsRegOff -or $hyperLaunchOff) -and $hvForcingVBS.Count -eq 0)
if ($realRebootPending) {
    $rsn = if ($rebootPending) { $rebootReasons -join ', ' } else { 'VBS/HVCI Registry-Aenderung' }
    Add-Finding 'Windows' 'REBOOT ausstehend' $rsn 'WARN' 'Neustart durchfuehren - VBS/HVCI Aenderungen greifen erst nach Reboot' 'KEIN'
}

# VBS / HVCI
try {
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
    if ($dg) {
        $vbsRunning = [int]$dg.VirtualizationBasedSecurityStatus
        # FIX v4.1: "registry off but state still running" als WARN statt BAD anzeigen
        $vbsPendingReboot = ($vbsRunning -eq 2 -and ($vbsRegOff -or $hyperLaunchOff))

        if ($vbsPendingReboot -and $hvForcingVBS.Count -gt 0) {
            # FIX v4.2: VBS bleibt aktiv weil Hyper-V/WSL/SAC es erzwingen, nicht weil Reboot fehlt
            $vbsText = "AKTIV (erzwungen durch: $($hvForcingVBS -join ', '))"
            $vbsStatus = 'WARN'
            $vbsReco = "Registry/BCD ist deaktiviert, aber $($hvForcingVBS -join ' + ') erzwingt VBS weiter. Optional zum Vollabschalten: Windows Features > 'Hyper-V', 'Virtual Machine Platform', 'Windows-Hypervisor-Plattform' deaktivieren. Bringt nur 1-3% extra FPS - vs. WSL2/Sandbox-Verlust abwaegen"
            $vbsAdmin = ''
        } elseif ($vbsPendingReboot) {
            $vbsText = 'AKTIV (Registry deaktiviert - Reboot ausstehend)'
            $vbsStatus = 'WARN'
            $vbsReco = 'VBS-Deaktivierung in Registry/BCD gesetzt - greift nach Neustart'
            $vbsAdmin = ''
        } else {
            $vbsText = switch ($vbsRunning) {
                0 { 'AUS' } 1 { 'konfiguriert, nicht aktiv' } 2 { 'AKTIV' }
                default { "Status $vbsRunning" }
            }
            $vbsStatus = if ($vbsRunning -eq 0) {'OK'} elseif ($vbsRunning -eq 1) {'WARN'} else {'BAD'}
            $vbsReco = if ($vbsRunning -eq 2) { 'VBS kostet ~1-3 % zusaetzlich zu HVCI. Hauptkosten ist HVCI selbst' } else {''}
            $vbsAdmin = ''
            if ($vbsRunning -eq 2) {
                $vbsAdmin = @"
# VBS deaktivieren (benoetigt Reboot)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v "EnableVirtualizationBasedSecurity" /t REG_DWORD /d 0 /f
bcdedit /set hypervisorlaunchtype off
"@
            }
        }
        Add-Finding 'Windows' 'VBS (Virtualization-Based Security)' $vbsText $vbsStatus $vbsReco 'MITTEL' 'Off entfernt zusaetzlich Credential Guard Haerten. Fuer reines Gaming akzeptabel. WSL2/Hyper-V/Docker funktionieren weiter' $null $vbsAdmin

        $hvciRunning = $false
        if ($dg.SecurityServicesRunning) {
            $hvciRunning = ($dg.SecurityServicesRunning -contains 2)
        }
        $hvciPendingReboot = ($hvciRunning -and $hvciRegOff)

        if ($hvciPendingReboot) {
            $hvciText = 'AN (Registry deaktiviert - Reboot ausstehend)'
            $hvciStatus = 'WARN'
            $hvciReco = 'HVCI in Registry deaktiviert - greift nach Neustart'
            $hvciAdmin = ''
        } else {
            $hvciText   = if ($hvciRunning) {'AN'} else {'AUS'}
            $hvciStatus = if ($hvciRunning) {'BAD'} else {'OK'}
            $hvciReco   = if ($hvciRunning) {'HVCI ~5-8 % FPS in PUBG. Win Security > Geraetesicherheit > Kernisolierung > Speicherintegritaet AUS + Reboot'} else {''}
            $hvciAdmin = ''
            if ($hvciRunning) {
                $hvciAdmin = @"
# HVCI / Memory Integrity deaktivieren (benoetigt Reboot)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v "Enabled" /t REG_DWORD /d 0 /f
"@
            }
        }
        Add-Finding 'Windows' 'Memory Integrity (HVCI)' $hvciText $hvciStatus $hvciReco 'MITTEL' 'Kernel-Schutz gegen unsignierte/boese Treiber faellt weg. Solo-Gaming ohne geknackte Software: akzeptables Risiko. Bei Firmen-Laptop: NICHT abschalten' $null $hvciAdmin
    }
} catch {
    Add-Finding 'Windows' 'VBS / HVCI' 'nicht auslesbar' 'SKIP'
}

# Fullscreen-Optimierungen TslGame.exe
$compatPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
$compatProps = Get-ItemProperty -Path $compatPath -ErrorAction SilentlyContinue
$tslFlags = $null
$tslExePath = $null
if ($pubgInstallPath) {
    $cand1 = Join-Path $pubgInstallPath 'TslGame\Binaries\Win64\TslGame.exe'
    if (Test-Path $cand1) { $tslExePath = $cand1 }
}
if ($compatProps) {
    $tslProp = $compatProps.PSObject.Properties | Where-Object { $_.Name -match 'TslGame.*\.exe$' } | Select-Object -First 1
    if ($tslProp) {
        $tslFlags = $tslProp.Value
        if (-not $tslExePath) { $tslExePath = $tslProp.Name }
        Add-Finding 'Windows' 'TslGame.exe Compat-Flags' $tslFlags 'INFO'
    }
}
$hasFSO = ($tslFlags -and $tslFlags -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE')
$fsoText   = if ($hasFSO) {'JA (FSO deaktiviert)'} else {'NEIN (FSO aktiv)'}
$fsoStatus = if ($hasFSO) {'OK'} else {'WARN'}
$fsoReco   = if (-not $hasFSO) {'Rechtsklick TslGame.exe > Eigenschaften > Kompatibilitaet > Vollbildoptimierungen deaktivieren'} else {''}
$autoFixFSO = $null
if ((-not $hasFSO) -and $tslExePath) {
    $script:tslExePathCaptured = $tslExePath
    $autoFixFSO = {
        $exe = $script:tslExePathCaptured
        if (-not (Test-Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers')) {
            New-Item -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Force | Out-Null
        }
        Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Name $exe -Value '~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE' -Type String
        Write-Host "    -> FSO fuer $exe deaktiviert + HighDPI override" -ForegroundColor Green
    }
}
Add-Finding 'Windows' 'Vollbildoptimierungen TslGame.exe' $fsoText $fsoStatus $fsoReco 'KEIN' 'Auto-HDR und VRR-Alt-Tab koennen minimal anders reagieren. MS hat FSO in 24H2/25H2 nicht "gefixt"' $autoFixFSO

# Defender Exclusion fuer PUBG-Ordner
# FIX v4.2: ExclusionPath ist nur mit Admin lesbar - sonst leeres Array (=False-Negative)
if ($pubgInstallPath) {
    $isAdminShell = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    try {
        $defPref = Get-MpPreference -ErrorAction Stop
        $exclusions = @($defPref.ExclusionPath)

        if ($exclusions.Count -eq 0 -and -not $isAdminShell) {
            Add-Finding 'Windows' 'Defender Exclusion (PUBG-Ordner)' 'nicht auslesbar (Script laeuft ohne Admin)' 'INFO' 'Manuell verifizieren: in Admin-PowerShell -> Get-MpPreference | Select -ExpandProperty ExclusionPath'
        } else {
            $pubgExcluded = $false
            $pNorm = $pubgInstallPath.TrimEnd('\').ToLower()
            foreach ($e in $exclusions) {
                if ($e) {
                    $eNorm = $e.TrimEnd('\').ToLower()
                    if ($pNorm -eq $eNorm -or $pNorm.StartsWith($eNorm + '\') -or $eNorm.StartsWith($pNorm + '\')) {
                        $pubgExcluded = $true; break
                    }
                }
            }
            $defText = if ($pubgExcluded) {'JA'} else {'NEIN'}
            $defStatus = if ($pubgExcluded) {'OK'} else {'WARN'}
            $defReco = if (-not $pubgExcluded) {'1-4 % FPS + besseres Map-Streaming durch Exclusion (sicher bei Vanilla-Steam-PUBG)'} else {''}
            $defAdmin = ''
            if (-not $pubgExcluded) {
                $defAdmin = "Add-MpPreference -ExclusionPath '$pubgInstallPath'"
            }
            Add-Finding 'Windows' 'Defender Exclusion (PUBG-Ordner)' $defText $defStatus $defReco 'GERING' 'Risiko nur falls Mods/Cheats im Ordner landen - bei reinem Steam-PUBG vernachlaessigbar' $null $defAdmin
        }
    } catch {
        Add-Finding 'Windows' 'Defender Exclusion' 'Get-MpPreference Fehler' 'SKIP'
    }
}

# Display-Skalierung
$dpi = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'AppliedDPI' -ErrorAction SilentlyContinue).AppliedDPI
if ($dpi) {
    $scalePct = [math]::Round(($dpi / 96) * 100)
    $scaleStatus = if ($scalePct -eq 100) {'OK'} else {'WARN'}
    $scaleReco = if ($scalePct -ne 100) {'PUBG kann bei Skalierung != 100 Maus/UI-Probleme bekommen. Einstellungen > System > Anzeige > Skalierung 100 %'} else {''}
    Add-Finding 'Windows' 'Display Skalierung' "$scalePct %" $scaleStatus $scaleReco 'MITTEL' 'Andere Apps werden ggf. klein. Bei 4K-Display oft wichtig fuer Lesbarkeit. Nur fuer Gaming-Setup empfohlen'
}

# Game Mode
$gameMode = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -ErrorAction SilentlyContinue
if ($gameMode) {
    $gmVal = if ($gameMode.AutoGameModeEnabled -eq 1) {'AN'} else {'AUS'}
    $gmStatus = if ($gameMode.AutoGameModeEnabled -eq 1) {'OK'} else {'WARN'}
    $autoFixGM = $null
    if ($gmStatus -eq 'WARN') {
        $autoFixGM = {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1 -Type DWord
            Write-Host '    -> Game Mode AN' -ForegroundColor Green
        }
    }
    Add-Finding 'Windows' 'Game Mode' $gmVal $gmStatus 'AN empfohlen - priorisiert Game-Prozess' 'KEIN' '' $autoFixGM
}

$hags = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -ErrorAction SilentlyContinue
if ($hags) {
    $hagsVal = if ($hags.HwSchMode -eq 2) {'AN'} else {'AUS'}
    Add-Finding 'Windows' 'HW-beschl. GPU-Planung (HAGS)' $hagsVal 'INFO' 'PUBG: meist AUS besser. AN wenn DLSS Frame Generation gewuenscht'
}

$gameDVR = Get-ItemProperty -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -ErrorAction SilentlyContinue
if ($gameDVR) {
    $dvrVal = if ($gameDVR.GameDVR_Enabled -eq 0) {'AUS'} else {'AN'}
    $dvrStatus = if ($gameDVR.GameDVR_Enabled -eq 0) {'OK'} else {'BAD'}
    $autoFixDvr = $null
    if ($dvrStatus -eq 'BAD') {
        $autoFixDvr = {
            Set-ItemProperty -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0 -Type DWord
            Write-Host '    -> Xbox Game DVR AUS' -ForegroundColor Green
        }
    }
    Add-Finding 'Windows' 'Xbox Game DVR' $dvrVal $dvrStatus 'AUSSCHALTEN - kostet messbar FPS' 'KEIN' '' $autoFixDvr
}

# Maus
$mouseProps = Get-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -ErrorAction SilentlyContinue
if ($mouseProps) {
    $accelOff = ($mouseProps.MouseSpeed -eq '0')
    $maText   = if ($accelOff) {'AUS'} else {"AN (MouseSpeed=$($mouseProps.MouseSpeed))"}
    $maStatus = if ($accelOff) {'OK'} else {'BAD'}
    $autoFixMA = $null
    if (-not $accelOff) {
        $autoFixMA = {
            Set-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -Value '0' -Type String
            Set-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0' -Type String
            Set-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0' -Type String
            Write-Host '    -> Enhanced Pointer Precision AUS (gilt nach Neu-Anmeldung)' -ForegroundColor Green
        }
    }
    Add-Finding 'Windows' 'Enhanced Pointer Precision' $maText $maStatus 'AUSSCHALTEN' 'KEIN' '' $autoFixMA

    $sliderOk = ($mouseProps.MouseSensitivity -eq '10')
    $autoFixSlider = $null
    if (-not $sliderOk) {
        $autoFixSlider = {
            Set-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSensitivity' -Value '10' -Type String
            Write-Host '    -> Maus-Slider auf 10 (6/11 = 1:1 Mapping)' -ForegroundColor Green
        }
    }
    Add-Finding 'Windows' 'Maus Slider-Position' "Wert $($mouseProps.MouseSensitivity) (10 = 6/11 = 1:1)" $(if ($sliderOk){'OK'}else{'BAD'}) $(if (-not $sliderOk){'Slider auf 6/11 stellen'}else{''}) 'KEIN' '' $autoFixSlider
}

# NEU v6: RTSS-Overlay-Check (RTSS-Overlay forciert Mode 5 in PUBG)
$rtss = Get-Process -Name 'RTSS' -ErrorAction SilentlyContinue
if ($rtss) {
    Add-Finding 'Windows' 'RivaTuner Statistics Server (RTSS) laeuft' "PID $($rtss.Id)" 'WARN' 'RTSS-Overlay forciert PUBG in Composed Copy Mode 5 (Latenz+). Falls nur fuer Framecap genutzt: RTSS-Setup > Show On-Screen Display = OFF. Framecap geht ueber NV-Profil oder In-Game' 'KEIN' 'CapFrameX nutzt RTSS auch im Hintergrund - waehrend Match ggf. CapFrameX zu'
}

# NEU v6: HDR-Status fuer Competitive PUBG warnen
try {
    $hdr = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\VideoSettings' -ErrorAction SilentlyContinue
    $hdrEnabled = $false
    if ($hdr -and $hdr.EnableHDRForPlayback -eq 1) { $hdrEnabled = $true }
    # Auch via Display Settings
    $hdrPerMon = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\GraphicsDrivers\Configuration' -ErrorAction SilentlyContinue
    foreach ($k in $hdrPerMon) {
        $sub = Get-ChildItem $k.PSPath -ErrorAction SilentlyContinue
        foreach ($s in $sub) {
            $advCol = (Get-ItemProperty $s.PSPath -Name 'AdvancedColorEnabled' -ErrorAction SilentlyContinue).AdvancedColorEnabled
            if ($advCol -eq 1) { $hdrEnabled = $true }
        }
    }
    if ($hdrEnabled) {
        Add-Finding 'Windows' 'HDR (Anzeige)' 'AKTIV' 'WARN' 'PUBG HDR auf QD-OLED 2025 broken (washed-out Skins). Plus: HDR kann Mode 3 (Independent Flip) blockieren. Fuer Competitive: SDR + sRGB-Monitor-Mode + Digital Vibrance 70%' 'GERING' 'Falls Daily-Driver auch HDR-Content (Filme): pro PUBG-Session toggeln via Win+Alt+B'
    } else {
        Add-Finding 'Windows' 'HDR (Anzeige)' 'AUS' 'OK'
    }
} catch {
    Add-Finding 'Windows' 'HDR-Status' 'nicht ermittelbar' 'SKIP'
}

# NEU v6: Multi-Monitor-Warnung verschaerft (vorher INFO, jetzt WARN da Mode-5-Ursache)
$activeMonitors = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue | Where-Object { $_.Active -eq $true })
if ($activeMonitors.Count -gt 1) {
    Add-Finding 'Windows' 'Multi-Monitor (>1 aktiv)' "$($activeMonitors.Count) aktive Monitore" 'WARN' 'Independent Flip (Mode 3) braucht single-monitor. Mit >1 Monitor zwingt DWM PUBG in Composed-Copy Mode 5 (~3-5ms Latency extra). Fuer Competitive-Session: Win+P > Nur Bildschirm 1' 'MITTEL' 'Sekundaere Monitore temporaer abklemmen waehrend Match'
}

# NEU v6: Timer Resolution Check
$tr = Get-TimerResolutionMs
if ($tr) {
    if ($tr.CurrentMs -le 0.6) {
        Add-Finding 'Windows' 'System Timer Resolution' "$($tr.CurrentMs) ms" 'OK'
    } elseif ($tr.CurrentMs -le 1.0) {
        Add-Finding 'Windows' 'System Timer Resolution' "$($tr.CurrentMs) ms" 'WARN' 'Auf 0.5 ms reduzieren bringt 10-25% bessere 1%-Lows. Tool: TimerResolution.exe (Lucas Hale, https://timerresolution.com) - vor PUBG-Start ausfuehren' 'KEIN'
    } else {
        Add-Finding 'Windows' 'System Timer Resolution' "$($tr.CurrentMs) ms" 'BAD' 'Default 15.6 ms - PUBG laeuft mit grobem Scheduling. TimerResolution.exe runterladen + minimieren = laeuft im Tray, setzt 0.5 ms' 'KEIN' 'https://timerresolution.com'
    }
}

# NEU v6: MMCSS-Settings Check
$mmcssKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$sysResp = (Get-ItemProperty $mmcssKey -Name 'SystemResponsiveness' -ErrorAction SilentlyContinue).SystemResponsiveness
$netThrot = (Get-ItemProperty $mmcssKey -Name 'NetworkThrottlingIndex' -ErrorAction SilentlyContinue).NetworkThrottlingIndex

$mmcssOk = ($sysResp -le 10 -and ($netThrot -eq [int32]::MaxValue -or $netThrot -eq -1 -or $netThrot -eq 0xFFFFFFFF))
if ($mmcssOk) {
    Add-Finding 'Windows' 'MMCSS Gaming-Profil' "SystemResponsiveness=$sysResp, NetworkThrottlingIndex=optimal" 'OK'
} else {
    $mmcssAdmin = @"
# MMCSS Tuning - 10% statt 20% CPU fuer Background-Multimedia, kein Network-Throttle
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "SystemResponsiveness" /t REG_DWORD /d 10 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "NetworkThrottlingIndex" /t REG_DWORD /d 0xFFFFFFFF /f
"@
    $detail = "SystemResponsiveness=$($sysResp -as [string]), NetworkThrottlingIndex=$($netThrot -as [string])"
    Add-Finding 'Windows' 'MMCSS Gaming-Profil' $detail 'WARN' 'SystemResponsiveness=10 (statt 20) + NetworkThrottlingIndex=FFFFFFFF entlastet Game-Thread und stoppt 10ms-Network-Throttle' 'KEIN' '' $null $mmcssAdmin
}

# NEU v6: Service-Status fuer Game-Modus
$gameUnfriendlyServices = @{
    'SysMain' = 'SuperFetch/Memory Prefetcher (HDD-Zeit, auf SSD nutzlos)'
    'WSearch' = 'Windows Search Indexer (toucht NVMe waehrend Match)'
    'DiagTrack' = 'Connected User Experiences and Telemetry'
    'MapsBroker' = 'Maps Background Service'
}
$activeBadSvcs = @()
foreach ($svc in $gameUnfriendlyServices.Keys) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq 'Running' -and $s.StartType -ne 'Disabled') {
        $activeBadSvcs += $svc
    }
}
if ($activeBadSvcs.Count -eq 0) {
    Add-Finding 'Windows' 'Game-unfriendly Services' 'alle disabled/gestoppt' 'OK'
} else {
    $svcAdmin = "# Game-unfriendly Services disablen (sicher fuer reines Gaming-Rig)`n"
    foreach ($svc in $activeBadSvcs) {
        $svcAdmin += "Set-Service -Name '$svc' -StartupType Disabled -ErrorAction SilentlyContinue`n"
        $svcAdmin += "Stop-Service -Name '$svc' -Force -ErrorAction SilentlyContinue`n"
    }
    Add-Finding 'Windows' 'Game-unfriendly Services' "$($activeBadSvcs.Count) laufen: $($activeBadSvcs -join ', ')" 'WARN' 'Auf Gaming-Rig deaktivieren: SysMain (Prefetch), WSearch (NVMe-Indexer), DiagTrack (Telemetry), MapsBroker' 'GERING' 'Suche im Startmenue ist ohne WSearch langsamer (paar Sek). Indexierung-Files bleiben aber verfuegbar' $null $svcAdmin
}


# Hintergrund-Prozesse: in v6 entfernt - nicht aktionable, lenkt vom Wesentlichen ab


# ==================== 6. PUBG CONFIG + LAUNCH OPTIONS ====================
if ($IncludePUBGIni) {
    Write-Status "PUBG Config wird ausgelesen und bewertet..." 'INFO'

    # NEU v4: Steam Launch Options
    $launchOpts = (Get-ItemProperty 'HKCU:\Software\Valve\Steam\Apps\578080' -Name 'LaunchOptions' -ErrorAction SilentlyContinue).LaunchOptions
    if ($launchOpts) {
        $oldFlags = @()
        if ($launchOpts -match '-USEALLAVAILABLECORES') { $oldFlags += '-USEALLAVAILABLECORES (no-op seit UE4)' }
        if ($launchOpts -match '-malloc=system') { $oldFlags += '-malloc=system (deprecated)' }
        if ($launchOpts -match '-high') { $oldFlags += '-high (kann BattlEye-Konflikt erzeugen)' }
        if ($launchOpts -match '-nojoy') { $oldFlags += '-nojoy (kein messbarer Effekt)' }

        if ($oldFlags.Count -gt 0) {
            Add-Finding 'PUBG Settings' 'Steam Launch Options' $launchOpts 'WARN' "Veraltet/no-op: $($oldFlags -join ', '). 2025-Konsens: Launch Options leer lassen" 'KEIN' 'Konnte Anti-Cheat triggern, gewinnt aber keine FPS mehr'
        } else {
            Add-Finding 'PUBG Settings' 'Steam Launch Options' $launchOpts 'INFO'
        }
    } else {
        Add-Finding 'PUBG Settings' 'Steam Launch Options' 'leer' 'OK'
    }

    $pubgConfigPath = "$env:LOCALAPPDATA\TslGame\Saved\Config\WindowsNoEditor"

    if (Test-Path $pubgConfigPath) {
        $gus = Join-Path $pubgConfigPath 'GameUserSettings.ini'

        if (Test-Path $gus) {
            $content = Get-Content $gus -Raw

            function Get-IniValue {
                param([string]$Key, [string]$Content)
                if ($Content -match "(?m)^$Key=([^\r\n]+)") { return $matches[1].Trim() }
                return $null
            }

            function Set-IniValue {
                param([string]$Path, [string]$Key, [string]$NewValue)
                $c = Get-Content $Path -Raw
                if ($c -match "(?m)^$Key=([^\r\n]+)") {
                    $c = $c -replace "(?m)^$Key=[^\r\n]+","$Key=$NewValue"
                    Set-Content -Path $Path -Value $c -NoNewline
                    return $true
                }
                return $false
            }

            $resX = Get-IniValue 'ResolutionSizeX' $content
            $resY = Get-IniValue 'ResolutionSizeY' $content
            if ($resX -and $resY) {
                Add-Finding 'PUBG Settings' 'Aufloesung (ResolutionSize)' "$resX x $resY" 'INFO'
            }

            $lastResX = Get-IniValue 'LastUserConfirmedResolutionSizeX' $content
            $lastResY = Get-IniValue 'LastUserConfirmedResolutionSizeY' $content
            if ($lastResX -and $lastResY -and ($lastResX -ne $resX -or $lastResY -ne $resY)) {
                Add-Finding 'PUBG Settings' 'Aufloesung (LastUserConfirmed)' "$lastResX x $lastResY" 'WARN' 'Weicht von ResolutionSize ab - das ist die zuletzt im Spiel bestaetigte (aktive)'
            }

            $fsm = Get-IniValue 'FullscreenMode' $content
            $lastFsm = Get-IniValue 'LastConfirmedFullscreenMode' $content
            if ($fsm) {
                $fsmText = switch ($fsm) {
                    '0' { 'Mode 0 (Fullscreen Exclusive)' }
                    '1' { 'Mode 1 (Windowed Fullscreen / Borderless)' }
                    '2' { 'Mode 2 (Fenster)' }
                    default { "Mode $fsm" }
                }
                $fsmStatus = if ($fsm -eq '0') {'OK'} elseif ($fsm -eq '2') {'BAD'} else {'WARN'}
                $fsmReco   = switch ($fsm) {
                    '0' {''}
                    '1' {'Borderless = leicht hoehere Latenz, kein echtes G-Sync. 0 fuer Competitive'}
                    '2' {'Windowed-Modus = Compositor-Lag. Auf 0 (Exclusive Fullscreen) umstellen'}
                    default {''}
                }
                $autoFixFsm = $null
                if ($fsm -ne '0' -and (Test-Path $gus)) {
                    $script:gusCaptured = $gus
                    $autoFixFsm = {
                        $g = $script:gusCaptured
                        Copy-Item $g "$g.bak_$timestamp"
                        $c = Get-Content $g -Raw
                        $c = $c -replace '(?m)^FullscreenMode=\d+','FullscreenMode=0'
                        $c = $c -replace '(?m)^LastConfirmedFullscreenMode=\d+','LastConfirmedFullscreenMode=0'
                        Set-Content -Path $g -Value $c -NoNewline
                        Write-Host "    -> FullscreenMode=0 gesetzt (Backup: $g.bak_$timestamp)" -ForegroundColor Green
                    }
                }
                Add-Finding 'PUBG Settings' 'Anzeige-Modus' $fsmText $fsmStatus $fsmReco 'GERING' 'Exclusive Fullscreen: Alt-Tab langsamer, kein leichtes Overlay (Discord-Overlay etc. ggf. nicht sichtbar)' $autoFixFsm
            }
            if ($lastFsm -and $lastFsm -ne $fsm) {
                Add-Finding 'PUBG Settings' 'LastConfirmedFullscreenMode' "Mode $lastFsm" 'WARN' "Tatsaechlich aktiv: Mode $lastFsm"
            }

            $vsync = Get-IniValue 'bUseVSync' $content
            if ($vsync) {
                $vsStatus = if ($vsync -eq 'False') {'OK'} else {'BAD'}
                Add-Finding 'PUBG Settings' 'V-Sync' $vsync $vsStatus 'V-Sync = massiver Input-Lag'
            }

            $dynRes = Get-IniValue 'bUseDynamicResolution' $content
            if ($dynRes) {
                $drStatus = if ($dynRes -eq 'False') {'OK'} else {'BAD'}
                Add-Finding 'PUBG Settings' 'Dynamische Aufloesung' $dynRes $drStatus 'Verursacht sichtbare Aufloesungs-Wechsel'
            }

            $fps = Get-IniValue 'FrameRateLimit' $content
            if ($fps) {
                $fpsVal = [int]([math]::Floor([double]$fps))
                # Target = Monitor-Hz - 3 (z.B. 237 bei 240Hz). Fallback 237 wenn $activeHz nicht da
                $targetFps = if ($activeHz -and $activeHz -ge 60) { $activeHz - 3 } else { 237 }

                $autoFixFps = $null
                if ($fpsVal -eq 0 -or $fpsVal -ge 500) {
                    $fpsStatus = 'WARN'
                    $fpsRecoTxt = "Cap setzen auf $targetFps (3 unter Monitor-Hz). Zwingend bei G-Sync/Reflex"
                    $script:gusCaptured = $gus
                    $script:fpsTargetCaptured = $targetFps
                    $autoFixFps = [scriptblock]::Create(@"
`$g = `$script:gusCaptured
`$tgt = `$script:fpsTargetCaptured
if (-not (Test-Path "`$g.bak_$timestamp")) { Copy-Item `$g "`$g.bak_$timestamp" }
`$c = Get-Content `$g -Raw
`$c = `$c -replace '(?m)^FrameRateLimit=[^\r\n]+',"FrameRateLimit=`$tgt.000000"
Set-Content -Path `$g -Value `$c -NoNewline
Write-Host "    -> FrameRateLimit = `$tgt FPS gesetzt" -ForegroundColor Green
"@)
                } elseif ($activeHz -and ($fpsVal -gt $activeHz - 2 -or $fpsVal -lt $activeHz - 10)) {
                    $fpsStatus = 'WARN'
                    $fpsRecoTxt = "Aktueller Cap nicht optimal. 3-5 unter Monitor-Hz = $targetFps fuer $activeHz Hz Monitor"
                } else {
                    $fpsStatus = 'OK'
                    $fpsRecoTxt = ''
                }
                Add-Finding 'PUBG Settings' 'FPS-Limit (In-Game)' "$fpsVal FPS" $fpsStatus $fpsRecoTxt 'KEIN' '' $autoFixFps
            }

            # LOGIK-FIX v4: ViewDistance = 0 ist BAD (Spotting!)
            $qualityChecks = @(
                @{ Key='sg.ResolutionQuality';   Optimal=100; OptimalText='100 (Native Aufloesung)'; BadIfNot=$false }
                @{ Key='sg.AntiAliasingQuality'; Optimal=0;   OptimalText='0 (Aus, klarstes Bild fuer Spotting)'; BadIfNot=$false }
                @{ Key='sg.PostProcessQuality';  Optimal=0;   OptimalText='0 (Aus, kein Motion Blur)'; BadIfNot=$false }
                @{ Key='sg.ShadowQuality';       Optimal=0;   OptimalText='0 (Aus, max FPS)'; BadIfNot=$false }
                @{ Key='sg.EffectsQuality';      Optimal=2;   OptimalText='2 (Effekte gut sichtbar)'; BadIfNot=$false }
                @{ Key='sg.FoliageQuality';      Optimal=0;   OptimalText='0 (weniger Versteck-Vegetation)'; BadIfNot=$false }
                @{ Key='sg.ViewDistanceQuality'; Optimal=3;   OptimalText='3 (Ultra) - Pflicht fuer Spotting auf Distanz'; BadIfNot=$true }
                @{ Key='sg.TextureQuality';      Optimal=3;   OptimalText='3 (Ultra, kostet kaum FPS bei 16GB VRAM)'; BadIfNot=$false }
            )

            foreach ($qc in $qualityChecks) {
                $valStr = Get-IniValue $qc.Key $content
                if ($valStr) {
                    # LOGIK-FIX v4: Float-tolerant
                    $valNum = try { [int][math]::Floor([double]$valStr) } catch { -1 }
                    $isOk = ($valNum -eq $qc.Optimal)
                    $status = if ($isOk) {'OK'} elseif ($qc.BadIfNot) {'BAD'} else {'WARN'}
                    $reco = if (-not $isOk) {"Competitive empfohlen: $($qc.OptimalText)"} else {''}

                    $autoFixQ = $null
                    if (-not $isOk) {
                        $script:gusCaptured = $gus
                        $keyCaptured = $qc.Key
                        $valCaptured = if ($qc.Key -eq 'sg.ResolutionQuality') { "$($qc.Optimal).000000" } else { "$($qc.Optimal)" }
                        $autoFixQ = [scriptblock]::Create(@"
`$g = `$script:gusCaptured
if (-not (Test-Path "`$g.bak_$timestamp")) { Copy-Item `$g "`$g.bak_$timestamp" }
`$c = Get-Content `$g -Raw
`$c = `$c -replace '(?m)^$keyCaptured=[^\r\n]+',"$keyCaptured=$valCaptured"
Set-Content -Path `$g -Value `$c -NoNewline
Write-Host '    -> $keyCaptured = $valCaptured' -ForegroundColor Green
"@)
                    }
                    Add-Finding 'PUBG Settings' $qc.Key $valStr $status $reco 'KEIN' '' $autoFixQ
                }
            }

        } else {
            Add-Finding 'PUBG Settings' 'GameUserSettings.ini' 'nicht gefunden' 'WARN' 'PUBG mind. 1x starten'
        }

        $eng = Join-Path $pubgConfigPath 'Engine.ini'
        if (Test-Path $eng) {
            $engSize = (Get-Item $eng).Length
            Add-Finding 'PUBG Settings' 'Engine.ini' "vorhanden ($engSize Bytes)" 'INFO'
        }

        # NEU v6: Engine.ini Tweaks pruefen + Auto-Fix
        $tweakStatus = Test-PUBGEngineIniTweaks -IniPath $eng -Expected $Global:EngineIniTweaks
        if ($tweakStatus.AllPresent) {
            Add-Finding 'PUBG Settings' 'Engine.ini Tweaks (Sharpen/Pacing/Streaming)' 'alle gesetzt' 'OK'
        } else {
            $missingCount = $tweakStatus.Missing.Count
            $missingStr = ($tweakStatus.Missing | Select-Object -First 4) -join ', '
            if ($tweakStatus.Missing.Count -gt 4) { $missingStr += ", ..." }
            $script:engIniPathCaptured = $eng
            $autoFixEngIni = {
                Edit-PUBGEngineIni -IniPath $script:engIniPathCaptured -DesiredSections $Global:EngineIniTweaks -Timestamp $timestamp
                Write-Host '    -> Engine.ini Tweaks gesetzt (Backup als .bak_<timestamp>)' -ForegroundColor Green
                Write-Host '       Inkl: r.Tonemapper.Sharpen=0.7 (Spotting), r.GTSyncType=1 (Frametimes)' -ForegroundColor DarkGray
                Write-Host '       r.Streaming.PoolSize=4096 (1%-Lows)' -ForegroundColor DarkGray
            }
            Add-Finding 'PUBG Settings' 'Engine.ini Tweaks (Sharpen/Pacing/Streaming)' "$missingCount fehlend: $missingStr" 'WARN' 'r.Tonemapper.Sharpen=0.7 (Spotting), Frame-Pacing-Settings, Streaming-Pool 4096 MB. Alle BattlEye-safe' 'KEIN' '' $autoFixEngIni
        }

    } else {
        Add-Finding 'PUBG Settings' 'Config-Ordner' 'nicht gefunden' 'WARN'
    }
}


# ==================== 8. NETZWERK - EU MIT JITTER ====================
if ($IncludePingTest) {
    Write-Status "EU-Ping/Jitter ($PingCount Pings)..." 'INFO'
    # FIX v4: ICMP-erreichbare Ziele
    $pingTargets = [ordered]@{
        'Cloudflare DE'           = '1.1.1.1'
        'Google DNS'              = '8.8.8.8'
        'PUBG-Telemetry'          = 'telemetry.pubg.com'
        'Steam Community'         = 'steamcommunity.com'
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

                $pStatus = if ($avg -lt 25) {'OK'} elseif ($avg -lt 50) {'WARN'} else {'BAD'}
                Add-Finding 'Netzwerk (EU)' "Ping $region (avg)" "$avg ms" $pStatus

                $jStatus = if ($stddev -lt 2) {'OK'} elseif ($stddev -lt 5) {'WARN'} else {'BAD'}
                Add-Finding 'Netzwerk (EU)' "Jitter $region" "stddev=$stddev ms (min=$min, max=$max)" $jStatus
            }
        }
        catch {
            Add-Finding 'Netzwerk (EU)' "Ping $region" 'nicht erreichbar' 'SKIP'
        }
    }

    # FIX v4: Adapter mit echtem Gateway, kein Xbox-Wireless / Bluetooth / virtuell
    $candidates = Get-NetAdapter | Where-Object {
        $_.Status -eq 'Up' -and
        $_.Virtual -eq $false -and
        $_.InterfaceDescription -notmatch 'Xbox|Bluetooth|Loopback|Hyper-V|TAP|VPN|WAN Miniport|VirtualBox|VMware'
    }
    $netAdapter = $candidates | Where-Object {
        $cfg = Get-NetIPConfiguration -InterfaceIndex $_.IfIndex -ErrorAction SilentlyContinue
        $cfg -and $cfg.IPv4DefaultGateway
    } | Select-Object -First 1
    if (-not $netAdapter) { $netAdapter = $candidates | Select-Object -First 1 }

    if ($netAdapter) {
        Add-Finding 'Netzwerk (EU)' 'Aktiver Adapter' $netAdapter.InterfaceDescription 'INFO'
        $mediaType = if ($netAdapter.PhysicalMediaType -match '802\.11|Wireless' -or $netAdapter.InterfaceDescription -match 'Wi-Fi|Wireless|WLAN') {'WLAN'} else {'LAN'}
        $mediaStatus = if ($mediaType -eq 'LAN') {'OK'} else {'BAD'}
        $mediaReco = if ($mediaStatus -eq 'BAD') {'Competitive immer Kabel - WLAN hat Jitter-Spikes'} else {''}
        Add-Finding 'Netzwerk (EU)' 'Verbindungstyp' $mediaType $mediaStatus $mediaReco
        Add-Finding 'Netzwerk (EU)' 'Link-Speed' $netAdapter.LinkSpeed 'INFO'

        # NEU v6: NIC Offload-Check (LSO, RSC, RSS, Interrupt Moderation, MTU)
        try {
            $lsoStatus = Get-NetAdapterLso -Name $netAdapter.Name -ErrorAction SilentlyContinue
            if ($lsoStatus) {
                $lsoOn = ($lsoStatus.V2IPv4Enabled -or $lsoStatus.V2IPv6Enabled)
                if ($lsoOn) {
                    $lsoAdmin = "Disable-NetAdapterLso -Name '$($netAdapter.Name)' -IPv4 -IPv6 -ErrorAction SilentlyContinue"
                    Add-Finding 'Netzwerk (EU)' 'NIC Large Send Offload v2' "AN (v4=$($lsoStatus.V2IPv4Enabled), v6=$($lsoStatus.V2IPv6Enabled))" 'WARN' 'LSO buendelt TCP - fuer UDP-Games (PUBG) nutzlos, fuegt aber Latenz. Deaktivieren' 'KEIN' '' $null $lsoAdmin
                } else {
                    Add-Finding 'Netzwerk (EU)' 'NIC Large Send Offload v2' 'AUS' 'OK'
                }
            }

            $rscStatus = Get-NetAdapterRsc -Name $netAdapter.Name -ErrorAction SilentlyContinue
            if ($rscStatus) {
                $rscOn = ($rscStatus.IPv4Enabled -or $rscStatus.IPv6Enabled)
                if ($rscOn) {
                    $rscAdmin = "Disable-NetAdapterRsc -Name '$($netAdapter.Name)' -IPv4 -IPv6 -ErrorAction SilentlyContinue"
                    Add-Finding 'Netzwerk (EU)' 'NIC Receive Segment Coalescing (RSC)' 'AN' 'WARN' 'RSC bundles incoming packets - fuegt Latenz fuer Gaming. Deaktivieren' 'KEIN' '' $null $rscAdmin
                } else {
                    Add-Finding 'Netzwerk (EU)' 'NIC Receive Segment Coalescing (RSC)' 'AUS' 'OK'
                }
            }

            $rssStatus = Get-NetAdapterRss -Name $netAdapter.Name -ErrorAction SilentlyContinue
            if ($rssStatus) {
                if ($rssStatus.Enabled) {
                    Add-Finding 'Netzwerk (EU)' 'NIC Receive Side Scaling (RSS)' 'AN' 'OK'
                } else {
                    $rssAdmin = "Enable-NetAdapterRss -Name '$($netAdapter.Name)' -ErrorAction SilentlyContinue"
                    Add-Finding 'Netzwerk (EU)' 'NIC Receive Side Scaling (RSS)' 'AUS' 'WARN' 'RSS verteilt Receive-Interrupts auf alle Cores - auf 16-Core CPU wichtig. Aktivieren' 'KEIN' '' $null $rssAdmin
                }
            }

            # Interrupt Moderation
            $imProp = Get-NetAdapterAdvancedProperty -Name $netAdapter.Name -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Interrupt Moderation|Interrupt-Moderation' }
            if ($imProp) {
                $imOn = $imProp.DisplayValue -notmatch 'Disabled|Aus|Off'
                if ($imOn) {
                    $imAdmin = "Set-NetAdapterAdvancedProperty -Name '$($netAdapter.Name)' -DisplayName '$($imProp.DisplayName)' -RegistryValue 0 -ErrorAction SilentlyContinue"
                    Add-Finding 'Netzwerk (EU)' 'NIC Interrupt Moderation' "$($imProp.DisplayValue)" 'WARN' 'Interrupt Moderation cached Interrupts (Batching). Fuer minimum latency abschalten' 'KEIN' '' $null $imAdmin
                } else {
                    Add-Finding 'Netzwerk (EU)' 'NIC Interrupt Moderation' 'AUS' 'OK'
                }
            }

            # MTU
            $ipCfg = Get-NetIPInterface -InterfaceIndex $netAdapter.IfIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($ipCfg) {
                $mtu = $ipCfg.NlMtu
                if ($mtu -eq 1492) {
                    Add-Finding 'Netzwerk (EU)' 'MTU (Ethernet)' "$mtu" 'OK'
                } elseif ($mtu -eq 1500) {
                    $mtuAdmin = "netsh interface ipv4 set subinterface `"$($netAdapter.Name)`" mtu=1492 store=persistent"
                    Add-Finding 'Netzwerk (EU)' 'MTU (Ethernet)' "$mtu (Default)" 'WARN' 'PUBG-Server cappen bei 1492. Mit 1500 entstehen evtl. fragmentierte Pakete (Latency+Loss). Auf 1492 setzen' 'GERING' 'Aendert nicht viel falls Provider PMTU richtig macht - aber kostet auch nix' $null $mtuAdmin
                } else {
                    Add-Finding 'Netzwerk (EU)' 'MTU (Ethernet)' "$mtu" 'INFO'
                }
            }
        } catch {
            Add-Finding 'Netzwerk (EU)' 'NIC Offloads' 'Auslese-Fehler (Admin?)' 'SKIP'
        }
    }
}


# ==================== HTML-REPORT ====================
Write-Status "HTML-Report wird gebaut..." 'INFO'

$statusColors = @{
    'OK'='#4ade80'; 'WARN'='#fbbf24'; 'BAD'='#f87171'; 'INFO'='#60a5fa'; 'SKIP'='#9ca3af'
}
$impactColors = @{
    'KEIN'='#4ade80'; 'GERING'='#60a5fa'; 'MITTEL'='#fbbf24'; 'HOCH'='#f87171'
}

$sectionOrder = @('Monitor (Primary)','GPU (dediziert)','CPU/RAM','Speicher','Windows','PUBG Settings','Netzwerk (EU)')
$grouped = $Global:Findings | Group-Object -Property { $_.Section }
$sectionsHtml = foreach ($name in $sectionOrder) {
    $s = $grouped | Where-Object { $_.Name -eq $name }
    if (-not $s) { continue }
    $rows = foreach ($f in $s.Group) {
        $color = $statusColors[$f.Status]
        # FIX v6: Empfehlung + Alltagsauswirkung nur bei WARN/BAD anzeigen
        # OK/INFO bleiben sauber ohne dangling orange text
        $showExtras = $f.Status -in 'WARN','BAD'
        $reco = if ($f.Recommendation -and $showExtras) {
            "<div class='reco'>&rarr; $($f.Recommendation)</div>"
        } else { '' }
        $impact = ''
        if ($f.EverydayImpact -and $showExtras) {
            $ic = $impactColors[$f.EverydayImpact]
            $detail = if ($f.ImpactDetail) { " &middot; $($f.ImpactDetail)" } else { '' }
            $impact = "<div class='impact' style='color:$ic'>Alltagsauswirkung: $($f.EverydayImpact)$detail</div>"
        }
        $fixable = ''
        if ($f.AutoFix -and $showExtras) { $fixable = " <span class='badge auto'>auto</span>" }
        elseif ($f.AdminFix -and $showExtras) { $fixable = " <span class='badge admin'>admin</span>" }
@"
        <tr>
            <td class='item'>$($f.Item)$fixable</td>
            <td class='value'>$($f.Value)$reco$impact</td>
            <td class='status' style='color:$color'>$($f.Status)</td>
        </tr>
"@
    }
@"
    <section>
        <h2>$($s.Name)</h2>
        <table>
            <thead><tr><th>Punkt</th><th>Wert / Empfehlung / Alltagsauswirkung</th><th>Status</th></tr></thead>
            <tbody>
$($rows -join "`n")
            </tbody>
        </table>
    </section>
"@
}

# FIX: @(...) Wrapper - sonst gibt Where-Object bei genau 1 Treffer ein Hashtable zurueck,
# dessen .Count die Anzahl Keys (=9) ist, nicht die Treffer-Anzahl
$ok   = @($Global:Findings | Where-Object Status -eq 'OK').Count
$warn = @($Global:Findings | Where-Object Status -eq 'WARN').Count
$bad  = @($Global:Findings | Where-Object Status -eq 'BAD').Count
$info = @($Global:Findings | Where-Object Status -eq 'INFO').Count

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
    .summary { display: flex; gap: 1rem; margin-bottom: 2rem; flex-wrap: wrap; }
    .summary-card { background: #1f2937; padding: 1rem 1.5rem; border-radius: 6px; border-left: 4px solid #60a5fa; min-width: 110px; }
    .summary-card.ok { border-left-color: #4ade80; }
    .summary-card.warn { border-left-color: #fbbf24; }
    .summary-card.bad { border-left-color: #f87171; }
    .summary-card .count { font-size: 1.5rem; font-weight: bold; }
    .summary-card .label { font-size: 0.85rem; color: #9ca3af; }
    section { background: #1a1d23; padding: 1.5rem; border-radius: 8px; margin-bottom: 1.5rem; border: 1px solid #2d3139; }
    h2 { color: #93c5fd; margin-bottom: 1rem; font-size: 1.2rem; border-bottom: 1px solid #2d3139; padding-bottom: 0.5rem; }
    table { width: 100%; border-collapse: collapse; }
    th { text-align: left; padding: 0.5rem; color: #9ca3af; font-size: 0.85rem; text-transform: uppercase; border-bottom: 1px solid #2d3139; }
    td { padding: 0.6rem 0.5rem; border-bottom: 1px solid #232730; vertical-align: top; }
    td.item { color: #d1d5db; width: 30%; }
    td.value { color: #e5e7eb; }
    td.status { font-weight: bold; width: 80px; text-align: center; }
    .reco { color: #fbbf24; font-size: 0.85rem; margin-top: 0.3rem; font-style: italic; }
    .impact { font-size: 0.8rem; margin-top: 0.2rem; opacity: 0.85; }
    .badge { display: inline-block; padding: 1px 6px; border-radius: 4px; font-size: 0.7rem; margin-left: 6px; font-weight: bold; }
    .badge.auto { background: #16a34a; color: #fff; }
    .badge.admin { background: #ea580c; color: #fff; }
    footer { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #2d3139; color: #6b7280; font-size: 0.8rem; text-align: center; }
</style>
</head>
<body>
<header>
    <h1>$ReportTitle</h1>
    <div class="meta">Erstellt am $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss') auf $env:COMPUTERNAME</div>
</header>

<div class="summary">
    <div class="summary-card ok"><div class="count">$ok</div><div class="label">OK</div></div>
    <div class="summary-card warn"><div class="count">$warn</div><div class="label">Warnungen</div></div>
    <div class="summary-card bad"><div class="count">$bad</div><div class="label">Probleme</div></div>
    <div class="summary-card"><div class="count">$info</div><div class="label">Info</div></div>
</div>

$($sectionsHtml -join "`n")

<footer>PUBG Competitive Setup Diagnose v6 &middot; auto = ohne Admin direkt ausfuehrbar &middot; admin = Elevated-Script benoetigt</footer>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host "`n=== Diagnose fertig ===" -ForegroundColor Green
Write-Host "Report: $reportPath" -ForegroundColor Cyan
Write-Host "OK: $ok  |  WARN: $warn  |  BAD: $bad  |  INFO: $info`n" -ForegroundColor Yellow
Start-Process $reportPath


# ==================== INTERAKTIVE FIX-PHASE ====================
if (-not $EnableFixPhase) { return }

# FIX v4.1: @() Wrapper - sonst gibt Where-Object bei 1 Treffer ein Hashtable zurueck,
# dessen .Count die Key-Anzahl (=9) statt 1 ist
$autoFixable = @($Global:Findings | Where-Object { $_.AutoFix -and $_.Status -in 'WARN','BAD' })
$adminFixable = @($Global:Findings | Where-Object { $_.AdminFix -and $_.Status -in 'WARN','BAD' })

if ($autoFixable.Count -eq 0 -and $adminFixable.Count -eq 0) {
    Write-Host "Keine automatisch behebbaren Punkte gefunden. Fertig." -ForegroundColor Green
    return
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " INTERAKTIVE FIX-PHASE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($autoFixable.Count -gt 0) {
    Write-Host "`n$($autoFixable.Count) Punkt(e) ohne Admin-Rechte anwendbar.`n" -ForegroundColor Yellow
    $go = Read-Host "Punkte interaktiv durchgehen? (j/n)"
    if ($go -match '^(j|y)') {
        $applied = 0
        $skipped = 0
        $failed = 0
        foreach ($f in $autoFixable) {
            Write-Host "`n--------------------------------------------------" -ForegroundColor DarkCyan
            Write-Host "Sektion: $($f.Section)" -ForegroundColor DarkGray
            Write-Host "Punkt:   $($f.Item)" -ForegroundColor Yellow
            Write-Host "Aktuell: $($f.Value)" -ForegroundColor White
            Write-Host "Vorschlag: $($f.Recommendation)" -ForegroundColor Cyan
            if ($f.EverydayImpact) {
                $ic = switch ($f.EverydayImpact) {
                    'KEIN' {'Green'} 'GERING' {'Cyan'} 'MITTEL' {'Yellow'} 'HOCH' {'Red'}
                    default {'White'}
                }
                Write-Host "Alltagsauswirkung: $($f.EverydayImpact)" -ForegroundColor $ic
                if ($f.ImpactDetail) {
                    Write-Host "  -> $($f.ImpactDetail)" -ForegroundColor DarkGray
                }
            }
            $ans = Read-Host "Anwenden? (j=ja / n=nein / q=abbrechen)"
            if ($ans -match '^q') {
                Write-Host "`nFix-Phase abgebrochen." -ForegroundColor Yellow
                break
            }
            if ($ans -match '^(j|y)') {
                try {
                    & $f.AutoFix
                    $applied++
                } catch {
                    Write-Host "    FEHLER: $_" -ForegroundColor Red
                    $failed++
                }
            } else {
                $skipped++
            }
        }
        Write-Host "`nAuto-Fixes: $applied angewendet, $skipped uebersprungen, $failed Fehler.`n" -ForegroundColor Green
    }
}

# NPI Install-Prompt (nur wenn NVIDIA-GPU UND NPI fehlt)
if ($script:nvGpuFound -and $script:npiMissing) {
    Write-Host "`n----- NVIDIA Profile Inspector -----" -ForegroundColor Cyan
    Write-Host "NPI ist nicht installiert. Es ist nur ueber NPI moeglich, Low Latency Mode = Ultra,"
    Write-Host "Power Mgmt = Prefer Max Perf etc. fuer das PUBG-Profil zu setzen (NVIDIA exposed dafuer"
    Write-Host "keine offizielle API)."
    Write-Host ""
    Write-Host "  Quelle: https://github.com/Orbmu2k/nvidiaProfileInspector (Open Source, single .exe)"
    Write-Host "  Ziel:   $Global:NPIDefaultDir"
    Write-Host "  Groesse: ~1 MB"
    Write-Host ""
    $instAns = Read-Host "Jetzt automatisch laden, installieren und PUBG-Profil setzen? (j/n)"
    if ($instAns -match '^(j|y)') {
        $newNpi = Install-NPIFromGitHub
        if ($newNpi) {
            Write-Host "`n  Wende PUBG-Profil an..." -ForegroundColor Cyan
            Invoke-NPIPubgProfile -NpiPath $newNpi
        } else {
            Write-Host "`n  Install fehlgeschlagen - manuell von $Global:NPIDefaultDir versuchen" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Uebersprungen. Spaeter manuell laden, dann Script nochmal." -ForegroundColor DarkGray
    }
}

if ($adminFixable.Count -gt 0) {
    Write-Host "`n$($adminFixable.Count) Punkt(e) benoetigen Admin-Rechte:" -ForegroundColor Yellow
    foreach ($af in $adminFixable) {
        Write-Host "  - $($af.Item) [$($af.EverydayImpact)]" -ForegroundColor DarkYellow
    }
    Write-Host ""
    $genScript = Read-Host "Elevated Fix-Script generieren? (j/n)"
    if ($genScript -match '^(j|y)') {
        $adminScriptLines = @(
            "<#",
            ".SYNOPSIS",
            "  PUBG Admin-Fixes - generiert am $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')",
            "  Quelle: PUBG-Diagnose-v6.ps1",
            ".NOTES",
            "  Ausfuehrung: Rechtsklick > Mit PowerShell ausfuehren (als Administrator)",
            "  Oder: Start > PowerShell als Admin > & '<dieser Pfad>'",
            "#>",
            "",
            "if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {",
            "    Write-Host 'Dieses Script benoetigt Admin-Rechte. Bitte erneut als Admin starten.' -ForegroundColor Red",
            "    pause",
            "    exit 1",
            "}",
            "",
            "`$ErrorActionPreference = 'Stop'",
            ""
        )

        foreach ($af in $adminFixable) {
            $adminScriptLines += "# === $($af.Item) ==="
            $adminScriptLines += "# $($af.Recommendation)"
            if ($af.EverydayImpact) {
                $adminScriptLines += "# Alltagsauswirkung: $($af.EverydayImpact) - $($af.ImpactDetail)"
            }
            $adminScriptLines += "Write-Host '--> $($af.Item)' -ForegroundColor Cyan"
            $adminScriptLines += $af.AdminFix
            $adminScriptLines += ""
        }
        $adminScriptLines += "Write-Host ''"
        $adminScriptLines += "Write-Host '========================================' -ForegroundColor Green"
        $adminScriptLines += "Write-Host '  Fertig.' -ForegroundColor Green"
        $adminScriptLines += "Write-Host '========================================' -ForegroundColor Green"
        $adminScriptLines += "Write-Host 'HVCI/VBS-Aenderungen greifen erst nach Reboot.' -ForegroundColor Yellow"
        $adminScriptLines += "`$rb = Read-Host 'Jetzt neu starten? (j/n)'"
        $adminScriptLines += "if (`$rb -match '^(j|y)') { shutdown.exe /r /t 10 /c 'PUBG-Diagnose Admin-Fixes - Neustart in 10 Sek.' }"

        $adminScriptPath = Join-Path $OutputFolder "PUBG-AdminFixes_$timestamp.ps1"
        $adminScriptLines | Out-File $adminScriptPath -Encoding UTF8
        Write-Host "`nAdmin-Script geschrieben:" -ForegroundColor Green
        Write-Host "  $adminScriptPath" -ForegroundColor White
        Write-Host "Ausfuehren via: Rechtsklick > Mit PowerShell ausfuehren (als Admin)" -ForegroundColor Yellow
        Write-Host "Bei HVCI/VBS-Aenderungen ist ein Reboot erforderlich.`n" -ForegroundColor Yellow
    }
}

Write-Host "Fertig. Die Diagnose ist im Browser geoeffnet." -ForegroundColor Green
