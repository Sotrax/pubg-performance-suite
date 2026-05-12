<#
.SYNOPSIS
    PUBG Performance Suite v1.0 (PoC)
    GUI-Wrapper fuer Diagnose, Tweaks und Game-Mode-Workflow

.DESCRIPTION
    Phase 1 PoC. Drei funktionale Tabs:
    - Dashboard: Live-Status aller relevanten Settings
    - Diagnose: ruft PUBG-Diagnose-v6.ps1 auf, oeffnet HTML
    - Game Mode: One-Click pre-/post-game prep

    Tools werden bei Bedarf auto-installiert:
      C:\Tools\MultiMonitorTool\
      C:\Tools\nvidiaProfileInspector\
      C:\Tools\PresentMon\

.NOTES
    Start: PUBG-Suite.bat (Doppelklick) oder
           powershell -ExecutionPolicy Bypass -File PUBG-Suite.ps1
#>

$ErrorActionPreference = 'SilentlyContinue'

# ==================== KONFIGURATION ====================
$Global:Suite = @{
    Version    = '0.11.1-beta'
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
    # Diag-Script liegt fest neben der Suite (Repo: diagnose\PUBG-Diagnose-v6.ps1,
    # Bootstrap-Install: %LOCALAPPDATA%\PUBGSuite\app\diagnose\PUBG-Diagnose-v6.ps1).
    # $PSScriptRoot zeigt in beiden Faellen auf den richtigen Folder.
    DiagScript = (Join-Path $PSScriptRoot 'diagnose\PUBG-Diagnose-v6.ps1')
    Tools = @{
        MMT  = 'C:\Tools\MultiMonitorTool\MultiMonitorTool.exe'
        NPI  = 'C:\Tools\nvidiaProfileInspector\nvidiaProfileInspector.exe'
        PM   = 'C:\Tools\PresentMon'
    }
    MonitorPattern = 'XB271HU'
    PUBGSteamURI   = 'steam://run/578080'
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
    } catch {}
}

function Get-SuiteConfig {
    if (Test-Path $Global:Suite.ConfigFile) {
        try { return Get-Content $Global:Suite.ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }
    return [PSCustomObject]@{
        MonitorPattern = 'XB271HU'
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
function Get-RegistrySnapshot {
    param([string]$Path, [string]$Name)
    try {
        $regPath = $Path -replace '^HKCU:','HKEY_CURRENT_USER' -replace '^HKLM:','HKEY_LOCAL_MACHINE'
        if (-not (Test-Path $Path)) {
            return @{ Path=$Path; Name=$Name; HadKey=$false; HadValue=$false; OldValue=$null; ValueKind='None' }
        }
        $key = Get-Item -Path $Path -ErrorAction Stop
        $val = $key.GetValue($Name, $null)
        $kind = if ($null -ne $val) { [string]$key.GetValueKind($Name) } else { 'None' }
        return @{ Path=$Path; Name=$Name; HadKey=$true; HadValue=($null -ne $val); OldValue=$val; ValueKind=$kind }
    } catch {
        return @{ Path=$Path; Name=$Name; HadKey=$false; HadValue=$false; OldValue=$null; ValueKind='None' }
    }
}

function Restore-RegistrySnapshot {
    param($Snap)
    try {
        if (-not $Snap.HadKey -or -not $Snap.HadValue) {
            # Vor Apply existierte der Wert nicht -> loeschen
            if (Test-Path $Snap.Path) {
                Remove-ItemProperty -Path $Snap.Path -Name $Snap.Name -ErrorAction SilentlyContinue
            }
            return $true
        }
        $type = switch ($Snap.ValueKind) {
            'DWord'  { 'DWord' }
            'QWord'  { 'QWord' }
            'String' { 'String' }
            'ExpandString' { 'ExpandString' }
            'MultiString' { 'MultiString' }
            'Binary' { 'Binary' }
            default  { 'String' }
        }
        if (-not (Test-Path $Snap.Path)) { New-Item -Path $Snap.Path -Force -ErrorAction Stop | Out-Null }
        Set-ItemProperty -Path $Snap.Path -Name $Snap.Name -Value $Snap.OldValue -Type $type -ErrorAction Stop
        return $true
    } catch {
        Write-SuiteLog "Restore-RegistrySnapshot Fehler: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

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
        try { $isReadOnly = ((Get-Item $eng -Force).Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0 } catch {}
        if ($hasSharpen -and $hasStreaming) {
            $lbl = if ($isReadOnly) { 'Tweaks drin (geschuetzt)' } else { 'Tweaks drin' }
            $s['Engine.ini'] = @{ Value=$lbl; Status='OK' }
        } else {
            $s['Engine.ini'] = @{ Value='Tweaks fehlen'; Status='WARN' }
        }
    } else { $s['Engine.ini'] = @{ Value='nicht gefunden'; Status='SKIP' } }

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

# ==================== TWEAK-REGISTRY ====================
# Zentrale Definition aller Tweaks. Jeder Tweak hat:
#  StatusFn: liefert 'OK' / 'WARN' / 'BAD' / 'SKIP' und optional Value-Text
#  ApplyFn:  Apply-Logik (return $true bei Erfolg)
#  RevertFn: optional - Rollback

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
    } catch {}
    return 240  # Fallback
}

function Get-OptimalFpsCap {
    $hz = Get-PrimaryMonitorHz
    return ($hz - 3)
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
    } catch {}
    try {
        Set-Content -Path $Path -Value $content -NoNewline -Encoding UTF8 -ErrorAction Stop
        # Wenn die Datei vorher schon ReadOnly war (Apply re-run), Flag wiederherstellen
        if ($wasReadOnly) {
            try {
                $fi2 = Get-Item $Path -Force
                $fi2.Attributes = $fi2.Attributes -bor [System.IO.FileAttributes]::ReadOnly
            } catch {}
        }
        return $true
    } catch {
        Write-SuiteLog "Update-IniValue: Write-Fehler $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$Global:Tweaks = @(
    [PSCustomObject]@{
        Id='energieplan'; Cat='Windows'; Name='Energieplan: Hoechstleistung'; Admin=$false
        Desc='CPU haelt volle Frequenz'; Impact='GERING'; ImpactDetail='~5W mehr Idle-Verbrauch'
        Changes = @(
            'powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c',
            'Aktiver Energieplan -> Windows-Standard-Hoechstleistung'
        )
        StatusFn = {
            $a = powercfg /getactivescheme 2>$null
            if ($a -match '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c|e9a42b02-d5df-448d-aa00-03f14749eb61') { 'OK' } else { 'WARN' }
        }
        SnapshotFn = {
            $a = powercfg /getactivescheme 2>$null
            if ($a -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                return @{ PreGuid = $matches[1] }
            }
            return $null
        }
        ApplyFn = {
            try {
                powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { return $true } else { return $false }
            } catch { return $false }
        }
        RevertFn = {
            param($snap)
            if ($snap -and $snap.PreGuid) {
                powercfg /setactive $snap.PreGuid 2>&1 | Out-Null
                return ($LASTEXITCODE -eq 0)
            }
            return $false
        }
    },
    [PSCustomObject]@{
        Id='gamemode'; Cat='Windows'; Name='Game Mode: AN'; Admin=$false
        Desc='Priorisiert Game-Prozess'; Impact='KEIN'; ImpactDetail=''
        Changes = @('HKCU\Software\Microsoft\GameBar', 'AutoGameModeEnabled = 1 (DWord)')
        StatusFn = {
            $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -ErrorAction SilentlyContinue).AutoGameModeEnabled
            if ($v -eq 1) { 'OK' } else { 'WARN' }
        }
        SnapshotFn = { Get-RegistrySnapshot -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' }
        ApplyFn = {
            try {
                if (-not (Test-Path 'HKCU:\Software\Microsoft\GameBar')) { New-Item 'HKCU:\Software\Microsoft\GameBar' -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1 -Type DWord -ErrorAction Stop
                return $true
            } catch { return $false }
        }
        RevertFn = { param($snap) Restore-RegistrySnapshot $snap }
    },
    [PSCustomObject]@{
        Id='gamedvr'; Cat='Windows'; Name='Xbox Game DVR: AUS'; Admin=$false
        Desc='kostet messbar FPS'; Impact='KEIN'; ImpactDetail=''
        Changes = @('HKCU\System\GameConfigStore', 'GameDVR_Enabled = 0 (DWord)')
        StatusFn = {
            $v = (Get-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -ErrorAction SilentlyContinue).GameDVR_Enabled
            if ($v -eq 0) { 'OK' } else { 'BAD' }
        }
        SnapshotFn = { Get-RegistrySnapshot -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' }
        ApplyFn = {
            try {
                Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0 -Type DWord -ErrorAction Stop
                return $true
            } catch { return $false }
        }
        RevertFn = { param($snap) Restore-RegistrySnapshot $snap }
    },
    [PSCustomObject]@{
        Id='mouseaccel'; Cat='Windows'; Name='Maus: Enhanced Pointer Precision AUS'; Admin=$false
        Desc='1:1 Mapping ohne Software-Beschleunigung'; Impact='KEIN'; ImpactDetail=''
        Changes = @('HKCU\Control Panel\Mouse', 'MouseSpeed = 0', 'MouseThreshold1 = 0', 'MouseThreshold2 = 0')
        StatusFn = {
            $v = (Get-ItemProperty 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -ErrorAction SilentlyContinue).MouseSpeed
            if ($v -eq '0') { 'OK' } else { 'BAD' }
        }
        SnapshotFn = {
            @{
                Speed = (Get-RegistrySnapshot -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed')
                T1 = (Get-RegistrySnapshot -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1')
                T2 = (Get-RegistrySnapshot -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2')
            }
        }
        ApplyFn = {
            try {
                Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -Value '0' -Type String -ErrorAction Stop
                Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0' -Type String -ErrorAction Stop
                Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0' -Type String -ErrorAction Stop
                return $true
            } catch { return $false }
        }
        RevertFn = {
            param($snap)
            $ok = $true
            if ($snap.Speed) { $ok = (Restore-RegistrySnapshot $snap.Speed) -and $ok }
            if ($snap.T1) { $ok = (Restore-RegistrySnapshot $snap.T1) -and $ok }
            if ($snap.T2) { $ok = (Restore-RegistrySnapshot $snap.T2) -and $ok }
            return $ok
        }
    },
    [PSCustomObject]@{
        Id='mouseslider'; Cat='Windows'; Name='Maus: Slider Mitte (6/11)'; Admin=$false
        Desc='1:1 DPI-Mapping ohne Software-Skalierung'; Impact='KEIN'; ImpactDetail=''
        Changes = @('HKCU\Control Panel\Mouse', 'MouseSensitivity = 10 (= Mitte)')
        StatusFn = {
            $v = (Get-ItemProperty 'HKCU:\Control Panel\Mouse' -Name 'MouseSensitivity' -ErrorAction SilentlyContinue).MouseSensitivity
            if ($v -eq '10') { 'OK' } else { 'BAD' }
        }
        SnapshotFn = { Get-RegistrySnapshot -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSensitivity' }
        ApplyFn = {
            try {
                Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name 'MouseSensitivity' -Value '10' -Type String -ErrorAction Stop
                return $true
            } catch { return $false }
        }
        RevertFn = { param($snap) Restore-RegistrySnapshot $snap }
    },
    [PSCustomObject]@{
        Id='fso'; Cat='PUBG'; Name='Vollbildoptimierungen TslGame.exe: AUS'; Admin=$false
        Desc='Ermoeglicht Mode 3 (Hardware Independent Flip) statt Compose-Copy'; Impact='KEIN'; ImpactDetail=''
        Changes = @(
            'HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
            'Wert: <PUBG-Pfad>\TslGame.exe = "~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE"',
            'PUBG-Pfad wird via Steam-Manifest (libraryfolders.vdf) automatisch erkannt'
        )
        StatusFn = {
            $layers = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -ErrorAction SilentlyContinue
            if (-not $layers) { return 'WARN' }
            $tsl = $layers.PSObject.Properties | Where-Object { $_.Name -match 'TslGame.*\.exe$' } | Select-Object -First 1
            if ($tsl -and $tsl.Value -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE') { 'OK' } else { 'WARN' }
        }
        SnapshotFn = {
            # Aktuelle Compat-Flags pro vorhandenem TslGame Eintrag sichern
            $path = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
            $existing = @()
            if (Test-Path $path) {
                $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
                if ($props) {
                    foreach ($prop in ($props.PSObject.Properties | Where-Object { $_.Name -match 'TslGame.*\.exe$' })) {
                        $existing += @{ Name = $prop.Name; OldValue = $prop.Value }
                    }
                }
            }
            return @{ Path = $path; Entries = $existing }
        }
        ApplyFn = {
            try {
                $steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
                $tslExe = $null
                if ($steamPath -and (Test-Path "$steamPath\steamapps\libraryfolders.vdf")) {
                    $libContent = Get-Content "$steamPath\steamapps\libraryfolders.vdf" -Raw
                    $libs = [regex]::Matches($libContent, '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\','\' }
                    foreach ($lib in $libs) {
                        $cand = Join-Path $lib 'steamapps\common\PUBG\TslGame\Binaries\Win64\TslGame.exe'
                        if (Test-Path $cand) { $tslExe = $cand; break }
                    }
                }
                if (-not $tslExe) { return $false }
                $path = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
                if (-not (Test-Path $path)) { New-Item $path -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty $path -Name $tslExe -Value '~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE' -Type String -ErrorAction Stop
                return $true
            } catch { return $false }
        }
        RevertFn = {
            param($snap)
            try {
                if (-not $snap) { return $false }
                if (-not (Test-Path $snap.Path)) { return $true }
                # Aktuelle TslGame-Eintraege loeschen
                $props = Get-ItemProperty -Path $snap.Path -ErrorAction SilentlyContinue
                if ($props) {
                    foreach ($prop in ($props.PSObject.Properties | Where-Object { $_.Name -match 'TslGame.*\.exe$' })) {
                        Remove-ItemProperty -Path $snap.Path -Name $prop.Name -ErrorAction SilentlyContinue
                    }
                }
                # Pre-State wiederherstellen
                foreach ($e in $snap.Entries) {
                    Set-ItemProperty -Path $snap.Path -Name $e.Name -Value $e.OldValue -Type String -ErrorAction SilentlyContinue
                }
                return $true
            } catch { return $false }
        }
    },
    [PSCustomObject]@{
        Id='engineini'; Cat='PUBG'; Name='Engine.ini Tweaks (Sharpen + Streaming + Pacing + AllowTearing)'; Admin=$false
        Desc='Spotting-Buff + bessere 1%-Lows + Hardware Independent Flip. BattlEye-safe. Datei wird Read-Only damit PUBG sie beim naechsten Start nicht ueberschreibt.'; Impact='GERING'; ImpactDetail='Engine.ini ist nach Apply read-only - PUBG-interne r.setres-Aenderungen werden geblockt (kein Game-Crash, nur Reset-via-PUBG-Menue funktioniert nicht mehr bis Revert).'
        Changes = @(
            'Datei: %LOCALAPPDATA%\TslGame\Saved\Config\WindowsNoEditor\Engine.ini',
            'Backup vor Aenderung als .bak_<timestamp>',
            '[SystemSettings] r.Tonemapper.Sharpen=0.7  (Spotting auf Distanz)',
            '[SystemSettings] r.GTSyncType=1            (glattere Frametimes)',
            '[SystemSettings] r.OneFrameThreadLag=0     (Frame-Pacing)',
            '[SystemSettings] r.FinishCurrentFrame=0    (Frame-Pacing)',
            '[SystemSettings] r.D3D11.UseAllowTearing=1 (DXGI Flip-Model: Hardware Independent Flip)',
            '[/Script/Engine.RendererSettings] r.Streaming.PoolSize=4096',
            '[/Script/Engine.RendererSettings] r.Streaming.HLODStrategy=2',
            '[/Script/Engine.RendererSettings] r.Streaming.FramesForFullUpdate=1',
            'Nach Apply: Datei-Attribut ReadOnly (PUBG ueberschreibt sonst beim Spielstart)'
        )
        StatusFn = {
            $eng = Get-PUBGEnginePath
            if (-not (Test-Path $eng)) { return 'SKIP' }
            $c = Get-Content $eng -Raw
            $hasSharpen = $c -match 'r\.Tonemapper\.Sharpen\s*=\s*0\.7'
            $hasStreaming = $c -match 'r\.Streaming\.PoolSize\s*=\s*4096'
            $hasGTSync = $c -match 'r\.GTSyncType\s*=\s*1'
            $hasTearing = $c -match 'r\.D3D11\.UseAllowTearing\s*=\s*1'
            if ($hasSharpen -and $hasStreaming -and $hasGTSync -and $hasTearing) { 'OK' } else { 'WARN' }
        }
        SnapshotFn = {
            $eng = Get-PUBGEnginePath
            if (Test-Path $eng) {
                $wasReadOnly = $false
                try {
                    $attr = (Get-Item $eng -Force).Attributes
                    $wasReadOnly = ($attr -band [System.IO.FileAttributes]::ReadOnly) -ne 0
                } catch {}
                $bak = Copy-FileToBackup -SourcePath $eng
                return @{ BackupPath = $bak; OriginalPath = $eng; WasReadOnly = $wasReadOnly }
            }
            return $null
        }
        ApplyFn = {
            try {
                $eng = Get-PUBGEnginePath
                if (-not (Test-Path $eng)) { return $false }
                # Falls Datei aus vorherigem Apply noch read-only ist: erst writable machen
                try {
                    $f = Get-Item $eng -Force
                    if (($f.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
                        $f.Attributes = $f.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
                    }
                } catch {}
                $tweaks = @{
                    'SystemSettings' = @{
                        'r.Tonemapper.Sharpen' = '0.7'
                        'r.OneFrameThreadLag' = '0'
                        'r.FinishCurrentFrame' = '0'
                        'r.GTSyncType' = '1'
                        'r.D3D11.UseAllowTearing' = '1'
                    }
                    '/Script/Engine.RendererSettings' = @{
                        'r.Streaming.PoolSize' = '4096'
                        'r.Streaming.HLODStrategy' = '2'
                        'r.Streaming.FramesForFullUpdate' = '1'
                    }
                }
                foreach ($sec in $tweaks.Keys) {
                    foreach ($k in $tweaks[$sec].Keys) {
                        $ok = Update-IniValue -Path $eng -Section $sec -Key $k -Value $tweaks[$sec][$k]
                        if (-not $ok) { return $false }
                    }
                }
                # SCHUTZ gegen PUBG-Overwrite: Datei nach erfolgreichem Write read-only setzen
                try {
                    $f2 = Get-Item $eng -Force
                    $f2.Attributes = $f2.Attributes -bor [System.IO.FileAttributes]::ReadOnly
                    Write-SuiteLog "Engine.ini: ReadOnly-Attribut gesetzt (PUBG-Overwrite-Schutz)" 'INFO'
                } catch {
                    Write-SuiteLog "Engine.ini: ReadOnly konnte nicht gesetzt werden - PUBG ueberschreibt eventuell: $($_.Exception.Message)" 'WARN'
                }
                return $true
            } catch { return $false }
        }
        RevertFn = {
            param($snap)
            if ($snap -and $snap.BackupPath -and $snap.OriginalPath) {
                # ReadOnly entfernen bevor wir die Datei ersetzen
                try {
                    if (Test-Path $snap.OriginalPath) {
                        $f = Get-Item $snap.OriginalPath -Force
                        if (($f.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
                            $f.Attributes = $f.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
                        }
                    }
                } catch {}
                return (Restore-FileFromBackup -BackupPath $snap.BackupPath -TargetPath $snap.OriginalPath)
            }
            return $false
        }
    },
    [PSCustomObject]@{
        Id='fpscap'; Cat='PUBG'; Name='PUBG FPS-Cap = Monitor-Hz minus 3'; Admin=$false
        Desc='Auto-Cap basierend auf Monitor-Hz fuer G-Sync/Reflex Window'; Impact='KEIN'; ImpactDetail=''
        Changes = @(
            'Datei: %LOCALAPPDATA%\TslGame\Saved\Config\WindowsNoEditor\GameUserSettings.ini',
            'Backup vor Aenderung als .bak_<timestamp>',
            'Cap wird dynamisch berechnet: aktuelle Primary-Monitor-Hz minus 3',
            'Beispiele: 240Hz -> 237, 165Hz -> 162, 144Hz -> 141, 360Hz -> 357'
        )
        StatusFn = {
            $gus = Get-PUBGGameUserPath
            if (-not (Test-Path $gus)) { return 'SKIP' }
            $target = Get-OptimalFpsCap
            $c = Get-Content $gus -Raw
            if ($c -match '(?m)^FrameRateLimit=([\d.]+)') {
                $v = [int][math]::Floor([double]$matches[1])
                if ($v -eq $target) { 'OK' } else { 'WARN' }
            } else { 'WARN' }
        }
        SnapshotFn = {
            $gus = Get-PUBGGameUserPath
            if (Test-Path $gus) {
                $bak = Copy-FileToBackup -SourcePath $gus
                return @{ BackupPath = $bak; OriginalPath = $gus }
            }
            return $null
        }
        ApplyFn = {
            try {
                $gus = Get-PUBGGameUserPath
                if (-not (Test-Path $gus)) { return $false }
                $target = Get-OptimalFpsCap
                $c = Get-Content $gus -Raw
                $newVal = "$target.000000"
                if ($c -match '(?m)^FrameRateLimit=') {
                    $c = $c -replace '(?m)^FrameRateLimit=[^\r\n]+',"FrameRateLimit=$newVal"
                } else {
                    $c += "`r`nFrameRateLimit=$newVal`r`n"
                }
                Set-Content $gus -Value $c -NoNewline -ErrorAction Stop
                return $true
            } catch { return $false }
        }
        RevertFn = {
            param($snap)
            if ($snap -and $snap.BackupPath -and $snap.OriginalPath) {
                return (Restore-FileFromBackup -BackupPath $snap.BackupPath -TargetPath $snap.OriginalPath)
            }
            return $false
        }
    },
    [PSCustomObject]@{
        Id='defender'; Cat='System'; Name='Defender Exclusion fuer PUBG-Ordner'; Admin=$true
        Desc='1-4% FPS + besseres Map-Streaming'; Impact='GERING'
        ImpactDetail='Risiko nur bei Mods/Cheats im Ordner'
        Changes = @(
            'Add-MpPreference -ExclusionPath <PUBG-Pfad aus Steam-Manifest>',
            'Bewirkt: Windows Defender Real-Time Scan ueberspringt PUBG-Ordner'
        )
        StatusFn = {
            try {
                $excl = @((Get-MpPreference -ErrorAction Stop).ExclusionPath)
                if ($excl -and ($excl -match 'PUBG|TslGame')) { 'OK' } else { 'WARN' }
            } catch { 'SKIP' }
        }
        SnapshotFn = {
            try {
                $excl = @((Get-MpPreference -ErrorAction Stop).ExclusionPath)
                $pubgExcl = $excl | Where-Object { $_ -match 'PUBG|TslGame' }
                return @{ PreExisting = @($pubgExcl) }
            } catch { return $null }
        }
        ApplyFn = {
            try {
                $steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
                if (-not $steamPath) { return $false }
                $libContent = Get-Content "$steamPath\steamapps\libraryfolders.vdf" -Raw
                $libs = [regex]::Matches($libContent, '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\','\' }
                foreach ($lib in $libs) {
                    $pubg = Join-Path $lib 'steamapps\common\PUBG'
                    if (Test-Path $pubg) {
                        Add-MpPreference -ExclusionPath $pubg -ErrorAction Stop
                        return $true
                    }
                }
                return $false
            } catch { return $false }
        }
        RevertFn = {
            param($snap)
            try {
                $cur = @((Get-MpPreference -ErrorAction Stop).ExclusionPath)
                $pubgNow = @($cur | Where-Object { $_ -match 'PUBG|TslGame' })
                $preExisting = if ($snap -and $snap.PreExisting) { @($snap.PreExisting) } else { @() }
                # Loesche nur die Exclusions die NICHT vor Apply schon da waren
                foreach ($e in $pubgNow) {
                    if ($e -notin $preExisting) {
                        Remove-MpPreference -ExclusionPath $e -ErrorAction SilentlyContinue
                    }
                }
                return $true
            } catch { return $false }
        }
    },
    [PSCustomObject]@{
        Id='hvci'; Cat='System'; Name='Virtualization Security (VBS + HVCI): AUS'; Admin=$true
        Desc='5-10% FPS in CPU-bound Games (Toms Hardware Benchmark). Erfordert Reboot. Win11 24H2 reaktiviert VBS sonst bei Feature-Updates.'; Impact='MITTEL'
        ImpactDetail='Senkt OS-Security: kein Memory Integrity (HVCI), kein Credential Guard, kein Hyper-V-Hypervisor. Bei Solo-Gaming + bewusster Auswahl ok - bei Multi-User-PC ueberlegen.'
        Changes = @(
            'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\EnableVirtualizationBasedSecurity = 0',
            'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity\Enabled = 0',
            'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard\Enabled = 0',
            'bcdedit /set hypervisorlaunchtype off  (kritisch fuer 24H2 - sonst reaktiviert Windows VBS)',
            'WICHTIG: greift erst nach REBOOT'
        )
        StatusFn = {
            try {
                $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
                # Korrekte Logik:
                # - HVCI oder CredGuard laufen -> BAD (volle 5-10% Penalty)
                # - Nur Hypervisor laeuft, Services aus -> WARN (~1-3% SLAT, nur via UEFI/bcdedit komplett aus)
                # - Alles aus -> OK
                $running = @($dg.SecurityServicesRunning)
                $hvciOn = $running -contains 2
                $credGuardOn = $running -contains 1
                $hyperVUp = ($dg.VirtualizationBasedSecurityStatus -eq 2)
                if ($hvciOn -or $credGuardOn) { 'BAD' }
                elseif ($hyperVUp) { 'WARN' }
                else { 'OK' }
            } catch { 'SKIP' }
        }
        SnapshotFn = {
            $rootDG = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
            $hvciKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
            $credGuardKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard'
            # bcdedit-State auslesen
            $hvLaunchType = 'auto'
            try {
                $bcdOut = & bcdedit /enum '{current}' 2>$null | Out-String
                if ($bcdOut -match '(?im)^\s*hypervisorlaunchtype\s+(\w+)') { $hvLaunchType = $matches[1] }
            } catch {}
            return @{
                Vbs = (Get-RegistrySnapshot -Path $rootDG -Name 'EnableVirtualizationBasedSecurity')
                Hvci = (Get-RegistrySnapshot -Path $hvciKey -Name 'Enabled')
                CredGuard = (Get-RegistrySnapshot -Path $credGuardKey -Name 'Enabled')
                HvLaunchType = $hvLaunchType
            }
        }
        ApplyFn = {
            try {
                $rootDG = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
                $hvciKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
                $credGuardKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard'
                foreach ($p in @($rootDG,$hvciKey,$credGuardKey)) {
                    if (-not (Test-Path $p)) { New-Item $p -Force -ErrorAction Stop | Out-Null }
                }
                Set-ItemProperty $rootDG -Name 'EnableVirtualizationBasedSecurity' -Value 0 -Type DWord -ErrorAction Stop
                Set-ItemProperty $hvciKey -Name 'Enabled' -Value 0 -Type DWord -ErrorAction Stop
                Set-ItemProperty $credGuardKey -Name 'Enabled' -Value 0 -Type DWord -ErrorAction Stop
                # Hypervisor-Launch-Type aus - kritisch fuer 24H2, sonst reaktiviert Windows VBS automatisch
                $bcdOut = & bcdedit /set hypervisorlaunchtype off 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-SuiteLog "bcdedit failed: $bcdOut" 'WARN'
                    # nicht hart abbrechen - die Registry-Aenderungen helfen schon
                }
                return $true
            } catch { return $false }
        }
        RevertFn = {
            param($snap)
            $ok = $true
            if ($snap.Vbs)        { $ok = (Restore-RegistrySnapshot $snap.Vbs)        -and $ok }
            if ($snap.Hvci)       { $ok = (Restore-RegistrySnapshot $snap.Hvci)       -and $ok }
            if ($snap.CredGuard)  { $ok = (Restore-RegistrySnapshot $snap.CredGuard)  -and $ok }
            # bcdedit zurueck auf vorherigen Wert (default = auto)
            if ($snap.HvLaunchType) {
                try {
                    & bcdedit /set hypervisorlaunchtype $snap.HvLaunchType 2>&1 | Out-Null
                } catch { $ok = $false }
            }
            return $ok
        }
    },
    [PSCustomObject]@{
        Id='hags'; Cat='System'; Name='Hardware-accelerated GPU Scheduling (HAGS): AN'; Admin=$true
        Desc='Verschiebt GPU-Queue-Submit + VRAM-Management auf dedizierten GPU-MCU. Voraussetzung fuer DLSS-Frame-Generation und voll funktionsfaehigen NVIDIA Reflex.'; Impact='GERING'
        ImpactDetail='PUBG-spezifisch unklar - kein publizierter A/B-Test. UE4 hatte in einigen Titeln Shader-Compile-Stutter mit HAGS=ON. PUBG hat keine DLSS-FG, der Hauptvorteil entfaellt also. Aber: schadet meist auch nicht. Default: nicht in Apply-All - manuell testen.'
        Changes = @(
            'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\HwSchMode',
            'HwSchMode = 2 (0=disabled, 2=enabled, REG_DWORD)',
            'WICHTIG: greift erst nach REBOOT'
        )
        StatusFn = {
            try {
                $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -ErrorAction SilentlyContinue).HwSchMode
                if ($null -eq $v) { 'SKIP' }
                elseif ($v -eq 2) { 'OK' }
                else { 'WARN' }
            } catch { 'SKIP' }
        }
        SnapshotFn = { Get-RegistrySnapshot -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' }
        ApplyFn = {
            try {
                $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
                if (-not (Test-Path $key)) { New-Item $key -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty $key -Name 'HwSchMode' -Value 2 -Type DWord -ErrorAction Stop
                return $true
            } catch { return $false }
        }
        RevertFn = { param($snap) Restore-RegistrySnapshot $snap }
    },
    [PSCustomObject]@{
        Id='mmcss'; Cat='System'; Name='MMCSS Gaming-Profil'; Admin=$true
        Desc='Gibt Multimedia-Threads mehr CPU, stoppt Network-Throttle'; Impact='KEIN'; ImpactDetail=''
        Changes = @(
            'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile',
            'SystemResponsiveness = 10 (statt 20 Default)',
            'NetworkThrottlingIndex = 0xFFFFFFFF (deaktiviert 10ms-Throttle)'
        )
        StatusFn = {
            $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            $r = (Get-ItemProperty $k -Name 'SystemResponsiveness' -ErrorAction SilentlyContinue).SystemResponsiveness
            $n = (Get-ItemProperty $k -Name 'NetworkThrottlingIndex' -ErrorAction SilentlyContinue).NetworkThrottlingIndex
            # Robuster Vergleich: 0xFFFFFFFF kommt als String "4294967295" (UInt32) ODER -1 (Int32, signed) zurueck
            # je nach PS-Version. String-Cast macht beides gleich vergleichbar.
            $nStr = "$n"
            $nOk = ($nStr -eq '-1') -or ($nStr -eq '4294967295')
            if ($r -le 10 -and $nOk) { 'OK' } else { 'WARN' }
        }
        SnapshotFn = {
            $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            @{
                SysResp = (Get-RegistrySnapshot -Path $k -Name 'SystemResponsiveness')
                NetThrot = (Get-RegistrySnapshot -Path $k -Name 'NetworkThrottlingIndex')
            }
        }
        ApplyFn = {
            try {
                $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
                Set-ItemProperty $k -Name 'SystemResponsiveness' -Value 10 -Type DWord -ErrorAction Stop
                & reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' /v 'NetworkThrottlingIndex' /t REG_DWORD /d 0xFFFFFFFF /f | Out-Null
                if ($LASTEXITCODE -ne 0) { return $false }
                return $true
            } catch { return $false }
        }
        RevertFn = {
            param($snap)
            $ok = $true
            if ($snap.SysResp) { $ok = (Restore-RegistrySnapshot $snap.SysResp) -and $ok }
            if ($snap.NetThrot) { $ok = (Restore-RegistrySnapshot $snap.NetThrot) -and $ok }
            return $ok
        }
    },
    [PSCustomObject]@{
        Id='services'; Cat='System'; Name='Game-unfriendly Services disablen'; Admin=$true
        Desc='Stoppt Background-Scan/Indexer/Telemetry waehrend Match'; Impact='GERING'
        ImpactDetail='Windows-Suche ohne WSearch langsamer (paar Sek), Indexierung-Files bleiben verfuegbar'
        Changes = @(
            'sc.exe / Set-Service: SysMain (SuperFetch/Prefetch)',
            'sc.exe / Set-Service: WSearch (Windows Search Indexer)',
            'sc.exe / Set-Service: DiagTrack (Connected User Experiences and Telemetry)',
            'sc.exe / Set-Service: MapsBroker',
            'Aktion: StartupType = Disabled + Stop-Service'
        )
        StatusFn = {
            $svcs = 'SysMain','WSearch','DiagTrack','MapsBroker'
            $running = @($svcs | ForEach-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue } | Where-Object { $_.Status -eq 'Running' })
            if ($running.Count -eq 0) { 'OK' } else { 'WARN' }
        }
        SnapshotFn = {
            $states = @()
            foreach ($s in 'SysMain','WSearch','DiagTrack','MapsBroker') {
                $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
                if ($svc) {
                    $states += @{ Name = $s; StartType = [string]$svc.StartType; Status = [string]$svc.Status }
                }
            }
            return @{ Services = $states }
        }
        ApplyFn = {
            try {
                $fails = 0
                foreach ($s in 'SysMain','WSearch','DiagTrack','MapsBroker') {
                    try {
                        Set-Service -Name $s -StartupType Disabled -ErrorAction Stop
                        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
                    } catch { $fails++ }
                }
                return ($fails -eq 0)
            } catch { return $false }
        }
        RevertFn = {
            param($snap)
            $ok = $true
            if ($snap -and $snap.Services) {
                foreach ($s in $snap.Services) {
                    try {
                        Set-Service -Name $s.Name -StartupType $s.StartType -ErrorAction Stop
                        if ($s.Status -eq 'Running') {
                            Start-Service -Name $s.Name -ErrorAction SilentlyContinue
                        }
                    } catch { $ok = $false }
                }
            }
            return $ok
        }
    },
    [PSCustomObject]@{
        Id='nicoffload'; Cat='System'; Name='NIC Offloads (LSO, RSC) deaktivieren'; Admin=$true
        Desc='Reduziert Network-Latency fuer Gaming (UDP)'; Impact='KEIN'; ImpactDetail=''
        Changes = @(
            'Disable-NetAdapterLso -IPv4 -IPv6 (Large Send Offload aus)',
            'Disable-NetAdapterRsc -IPv4 -IPv6 (Receive Segment Coalescing aus)',
            'Aktiv aktiver Adapter (erster Up/Non-Virtual)'
        )
        StatusFn = {
            $nic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual } | Select-Object -First 1
            if (-not $nic) { return 'SKIP' }
            $lso = Get-NetAdapterLso -Name $nic.Name -ErrorAction SilentlyContinue
            $rsc = Get-NetAdapterRsc -Name $nic.Name -ErrorAction SilentlyContinue
            $bad = $false
            if ($lso -and ($lso.V2IPv4Enabled -or $lso.V2IPv6Enabled)) { $bad = $true }
            if ($rsc -and ($rsc.IPv4Enabled -or $rsc.IPv6Enabled)) { $bad = $true }
            if ($bad) { 'WARN' } else { 'OK' }
        }
        SnapshotFn = {
            $nic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual } | Select-Object -First 1
            if (-not $nic) { return $null }
            $lso = Get-NetAdapterLso -Name $nic.Name -ErrorAction SilentlyContinue
            $rsc = Get-NetAdapterRsc -Name $nic.Name -ErrorAction SilentlyContinue
            return @{
                NicName = $nic.Name
                LsoV4 = if ($lso) { $lso.V2IPv4Enabled } else { $null }
                LsoV6 = if ($lso) { $lso.V2IPv6Enabled } else { $null }
                RscV4 = if ($rsc) { $rsc.IPv4Enabled } else { $null }
                RscV6 = if ($rsc) { $rsc.IPv6Enabled } else { $null }
            }
        }
        ApplyFn = {
            try {
                $nic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual } | Select-Object -First 1
                if (-not $nic) { return $false }
                Disable-NetAdapterLso -Name $nic.Name -IPv4 -IPv6 -ErrorAction Stop
                Disable-NetAdapterRsc -Name $nic.Name -IPv4 -IPv6 -ErrorAction Stop
                return $true
            } catch { return $false }
        }
        RevertFn = {
            param($snap)
            try {
                if (-not $snap -or -not $snap.NicName) { return $false }
                if ($snap.LsoV4) { Enable-NetAdapterLso -Name $snap.NicName -IPv4 -ErrorAction SilentlyContinue }
                if ($snap.LsoV6) { Enable-NetAdapterLso -Name $snap.NicName -IPv6 -ErrorAction SilentlyContinue }
                if ($snap.RscV4) { Enable-NetAdapterRsc -Name $snap.NicName -IPv4 -ErrorAction SilentlyContinue }
                if ($snap.RscV6) { Enable-NetAdapterRsc -Name $snap.NicName -IPv6 -ErrorAction SilentlyContinue }
                return $true
            } catch { return $false }
        }
    },
    [PSCustomObject]@{
        Id='nvprofile'; Cat='PUBG'; Name='NVIDIA PUBG-Profil (Low Latency, Power Max, etc.)'; Admin=$false
        Desc='Setzt 6 NV-Treiber-Werte fuer PUBG-Profil via NPI'
        Impact='KEIN'; ImpactDetail='NPI wird auto-installiert falls fehlt'
        Changes = @(
            'Tool: NVIDIA Profile Inspector (auto-Install nach C:\Tools\nvidiaProfileInspector\)',
            'Profil-Name: PLAYERUNKNOWN''S BATTLEGROUNDS',
            'Power Management Mode = Prefer Max Performance',
            'Vertical Sync = Force OFF',
            'Texture Filtering Quality = High Performance',
            'Threaded Optimization = ON',
            'Low Latency Mode = Ultra (Reflex-equivalent)',
            'Frame Rate Limiter v3 = 237 FPS',
            'Antialiasing Mode = Application Controlled',
            'Stamp-File: %LOCALAPPDATA%\PUBGDiag\npi-applied.stamp'
        )
        StatusFn = {
            if (Test-Path $Global:Suite.NPIStamp) {
                $age = (Get-Date) - (Get-Item $Global:Suite.NPIStamp).LastWriteTime
                if ($age.TotalDays -lt 60) { return 'OK' }
            }
            return 'WARN'
        }
        ApplyFn = {
            try {
                $npi = Get-NPIPath
                if (-not $npi) {
                    $npi = Install-NPIFromGitHub
                    if (-not $npi) { return $false }
                }
                Invoke-NPIPubgProfile -NpiPath $npi
                return (Test-Path $Global:Suite.NPIStamp)
            } catch { return $false }
        }
    }
)

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
        [bool]$SetTimerResolution = $false,
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
        if ($mmt) {
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

    # 4. Timer Resolution (optional, falls SetTimerResolution.exe vorhanden)
    if ($SetTimerResolution) {
        & $LogCallback "Timer Resolution: PoC noch nicht implementiert" 'WARN'
    }

    # 5. PUBG launchen
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

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PUBG Performance Suite" Height="700" Width="1050"
        Background="#0f1115" WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <Style TargetType="TabItem">
            <Setter Property="Background" Value="#1a1d23"/>
            <Setter Property="Foreground" Value="#e5e7eb"/>
            <Setter Property="BorderBrush" Value="#2d3139"/>
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border Name="Border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="0,0,0,2" Padding="{TemplateBinding Padding}">
                            <ContentPresenter ContentSource="Header" RecognizesAccessKey="True" HorizontalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="BorderBrush" Value="#60a5fa"/>
                                <Setter Property="Foreground" Value="#60a5fa"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="#93c5fd"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#2563eb"/>
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
                    <Setter Property="Background" Value="#3b82f6"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="#374151"/>
                    <Setter Property="Foreground" Value="#9ca3af"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="SectionHeader" TargetType="TextBlock">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="#93c5fd"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
        </Style>
        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="#1a1d23"/>
            <Setter Property="BorderBrush" Value="#2d3139"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="6"/>
            <Setter Property="Padding" Value="16"/>
            <Setter Property="Margin" Value="0,0,0,14"/>
        </Style>
        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#dc2626"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#ef4444"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="SuccessButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#16a34a"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#22c55e"/>
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
        <Border Grid.Row="0" Background="#1a1d23" BorderBrush="#2d3139" BorderThickness="0,0,0,1" Padding="20,10">
            <Grid>
                <StackPanel HorizontalAlignment="Left" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="PUBG PERFORMANCE SUITE" FontSize="17" FontWeight="Bold" Foreground="#60a5fa" VerticalAlignment="Center"/>
                    <Border Background="#0f1115" CornerRadius="3" Padding="6,2" Margin="10,0,0,0" VerticalAlignment="Center">
                        <TextBlock x:Name="lblVersion" Text="v?" FontSize="10" Foreground="#9ca3af" FontWeight="SemiBold"/>
                    </Border>
                </StackPanel>
                <StackPanel HorizontalAlignment="Right" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border x:Name="adminBadge" Background="#374151" CornerRadius="3" Padding="8,3" VerticalAlignment="Center" Margin="0,0,8,0">
                        <TextBlock x:Name="lblAdmin" Text="Admin: ?" Foreground="#e5e7eb" FontSize="10" FontWeight="SemiBold"/>
                    </Border>
                    <Border Background="#0f1115" CornerRadius="3" Padding="8,3" VerticalAlignment="Center" Margin="0,0,12,0">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Status: " Foreground="#9ca3af" FontSize="11" VerticalAlignment="Center"/>
                            <TextBlock x:Name="lblTopStatus" Text="-/-" Foreground="#e5e7eb" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Border>
                    <Button x:Name="btnRefresh" Content="↻ Refresh" Width="100"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Tabs -->
        <TabControl x:Name="mainTabs" Grid.Row="1" Background="#0f1115" BorderThickness="0" Padding="0">
            <!-- TAB 1: DASHBOARD -->
            <TabItem Header="Dashboard">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Background="#0f1115">
                    <StackPanel Margin="20">
                        <Grid Margin="0,0,0,10">
                            <TextBlock Text="Live Status" FontSize="14" FontWeight="Bold" Foreground="#93c5fd" HorizontalAlignment="Left"/>
                            <TextBlock x:Name="lblStatusSubtitle" Text="" FontSize="11" Foreground="#6b7280" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <ItemsControl x:Name="statusItems">
                            <ItemsControl.ItemsPanel>
                                <ItemsPanelTemplate>
                                    <UniformGrid Columns="4"/>
                                </ItemsPanelTemplate>
                            </ItemsControl.ItemsPanel>
                            <ItemsControl.ItemTemplate>
                                <DataTemplate>
                                    <Border Background="#1a1d23" BorderBrush="{Binding BorderColor}" BorderThickness="0,0,0,3" Padding="14,10" Margin="6" CornerRadius="3">
                                        <StackPanel>
                                            <TextBlock Text="{Binding Label}" Foreground="#9ca3af" FontSize="11"/>
                                            <TextBlock Text="{Binding Value}" Foreground="{Binding TextColor}" FontSize="14" FontWeight="SemiBold" Margin="0,4,0,0" TextWrapping="Wrap"/>
                                        </StackPanel>
                                    </Border>
                                </DataTemplate>
                            </ItemsControl.ItemTemplate>
                        </ItemsControl>

                        <TextBlock Text="Schnell-Aktionen" FontSize="14" FontWeight="Bold" Foreground="#93c5fd" Margin="0,24,0,10"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Button x:Name="btnStartGameMode" Grid.Column="0" Content="🎯 START GAME MODE" Style="{StaticResource SuccessButton}" Height="60" FontSize="15" FontWeight="Bold" Margin="6"/>
                            <Button x:Name="btnExitGameMode" Grid.Column="1" Content="🛑 EXIT GAME MODE" Style="{StaticResource DangerButton}" Height="60" FontSize="15" FontWeight="Bold" Margin="6"/>
                        </Grid>

                        <TextBlock Text="Empfehlungen" FontSize="14" FontWeight="Bold" Foreground="#93c5fd" Margin="0,24,0,10"/>
                        <StackPanel x:Name="recoList"/>
                        <Border x:Name="recoEmptyState" Background="#0f3a23" BorderBrush="#4ade80" BorderThickness="0,0,0,2" Padding="14,10" CornerRadius="3" Visibility="Collapsed">
                            <TextBlock Text="✓ Alle Live-Checks gruen. Setup ist sauber - viel Erfolg im Match." Foreground="#4ade80" FontWeight="SemiBold"/>
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
                    <TextBlock Grid.Row="0" Text="Full System Diagnose (v6)" FontSize="14" FontWeight="Bold" Foreground="#93c5fd" Margin="0,0,0,10"/>
                    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,12">
                        <Button x:Name="btnRunDiag" Content="📊 Run Full Diagnose" Width="200" Height="38"/>
                        <Button x:Name="btnOpenHTML" Content="🌐 Open Last Report" Width="200" Height="38" Margin="10,0,0,0"/>
                        <Button x:Name="btnOpenReports" Content="📁 Reports Folder" Width="160" Height="38" Margin="10,0,0,0"/>
                    </StackPanel>
                    <Border Grid.Row="2" Background="#1a1d23" BorderBrush="#2d3139" BorderThickness="1" CornerRadius="4">
                        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="10">
                            <TextBlock x:Name="txtDiagOutput" Text="" Foreground="#d1d5db" FontFamily="Consolas" FontSize="12" TextWrapping="Wrap"/>
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
                                <TextBlock Foreground="#9ca3af" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8">
                                    <Run Text="Misst Frametimes via Intel PresentMon - passiv via ETW, kein DLL-Hook, kein RTSS."/>
                                    <LineBreak/>
                                    <Run Text="Voraussetzungen: PUBG laeuft, du bist im Match. Game Mode (Monitore solo + RTSS aus) empfohlen davor."/>
                                </TextBlock>

                                <Grid Margin="0,4,0,0">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="PresentMon: " Foreground="#e5e7eb" FontSize="12" VerticalAlignment="Center"/>
                                    <TextBlock Grid.Column="1" x:Name="lblCapToolStatus" Text="pruefe..." Foreground="#9ca3af" FontSize="12" VerticalAlignment="Center"/>
                                </Grid>

                                <StackPanel Orientation="Horizontal" Margin="0,12,0,0">
                                    <Button x:Name="btnCapStart" Content="▶ START 60s CAPTURE" Style="{StaticResource SuccessButton}" Width="220" Height="44" FontWeight="Bold"/>
                                    <Button x:Name="btnCapStop" Content="Stop" Style="{StaticResource DangerButton}" Width="100" Height="44" Margin="8,0,0,0" IsEnabled="False"/>
                                </StackPanel>

                                <TextBlock x:Name="lblCapPhase" Text="Bereit." Foreground="#60a5fa" FontSize="12" FontWeight="SemiBold" Margin="0,12,0,0"/>
                            </StackPanel>
                        </Border>

                        <!-- Last Result Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Letzte Messung" Style="{StaticResource SectionHeader}"/>
                                <TextBlock x:Name="lblCapLastInfo" Text="Noch keine Messung gemacht." Foreground="#9ca3af" FontSize="11" Margin="0,0,0,8"/>

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
                                    <Border Grid.Row="0" Grid.Column="0" Background="#0f1115" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="AVG FPS" Foreground="#9ca3af" FontSize="10"/>
                                            <TextBlock x:Name="lblCapAvg" Text="-" Foreground="#4ade80" FontSize="22" FontWeight="Bold"/>
                                            <TextBlock Text="Durchschnitt ueber Capture" Foreground="#6b7280" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="0" Grid.Column="1" Background="#0f1115" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="1% LOW" Foreground="#9ca3af" FontSize="10"/>
                                            <TextBlock x:Name="lblCap1Low" Text="-" Foreground="#fbbf24" FontSize="22" FontWeight="Bold"/>
                                            <TextBlock Text="schlechteste 1% der Frames" Foreground="#6b7280" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="0" Grid.Column="2" Background="#0f1115" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="0.1% LOW" Foreground="#9ca3af" FontSize="10"/>
                                            <TextBlock x:Name="lblCap01Low" Text="-" Foreground="#f87171" FontSize="22" FontWeight="Bold"/>
                                            <TextBlock Text="worst-case Stutter-Floor" Foreground="#6b7280" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="0" Grid.Column="3" Background="#0f1115" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="STDDEV (Frame Pacing)" Foreground="#9ca3af" FontSize="10"/>
                                            <TextBlock x:Name="lblCapStdDev" Text="-" Foreground="#60a5fa" FontSize="22" FontWeight="Bold"/>
                                            <TextBlock x:Name="lblCapStability" Text="-" Foreground="#6b7280" FontSize="9"/>
                                        </StackPanel>
                                    </Border>

                                    <!-- Row 1: Bottleneck-Analyse -->
                                    <Border Grid.Row="1" Grid.Column="0" Background="#0f1115" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="BOTTLENECK" Foreground="#9ca3af" FontSize="10"/>
                                            <TextBlock x:Name="lblCapBottleneck" Text="-" Foreground="#e5e7eb" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="wer limitiert?" Foreground="#6b7280" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="1" Grid.Column="1" Background="#0f1115" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="CPU BUSY" Foreground="#9ca3af" FontSize="10"/>
                                            <TextBlock x:Name="lblCapCpuBusy" Text="-" Foreground="#e5e7eb" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="ms CPU pro Frame" Foreground="#6b7280" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="1" Grid.Column="2" Background="#0f1115" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="GPU BUSY" Foreground="#9ca3af" FontSize="10"/>
                                            <TextBlock x:Name="lblCapGpuBusy" Text="-" Foreground="#e5e7eb" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="ms GPU pro Frame" Foreground="#6b7280" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="1" Grid.Column="3" Background="#0f1115" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="RENDER LATENCY" Foreground="#9ca3af" FontSize="10"/>
                                            <TextBlock x:Name="lblCapRenderLat" Text="-" Foreground="#e5e7eb" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="Render -> Present" Foreground="#6b7280" FontSize="9"/>
                                        </StackPanel>
                                    </Border>

                                    <!-- Row 2: Latency-Details -->
                                    <Border Grid.Row="2" Grid.Column="0" Background="#0f1115" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="UNTIL DISPLAYED" Foreground="#9ca3af" FontSize="10"/>
                                            <TextBlock x:Name="lblCapUntilDisp" Text="-" Foreground="#e5e7eb" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="Frame -> Photon" Foreground="#6b7280" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="2" Grid.Column="1" Background="#0f1115" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="CLICK->PHOTON" Foreground="#9ca3af" FontSize="10"/>
                                            <TextBlock x:Name="lblCapClickPhoton" Text="-" Foreground="#e5e7eb" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="nur mit Reflex" Foreground="#6b7280" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="2" Grid.Column="2" Background="#0f1115" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="G-SYNC" Foreground="#9ca3af" FontSize="10"/>
                                            <TextBlock x:Name="lblCapGSync" Text="-" Foreground="#e5e7eb" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="AllowsTearing-Flag" Foreground="#6b7280" FontSize="9"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Row="2" Grid.Column="3" Background="#0f1115" CornerRadius="4" Padding="10,8" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="STUTTER" Foreground="#9ca3af" FontSize="10"/>
                                            <TextBlock x:Name="lblCapStutter" Text="-" Foreground="#e5e7eb" FontSize="14" FontWeight="Bold"/>
                                            <TextBlock Text="Frames &gt; 2x Avg" Foreground="#6b7280" FontSize="9"/>
                                        </StackPanel>
                                    </Border>

                                    <!-- Row 3: Present Mode mit Erklaerung (volle Breite) -->
                                    <Border Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="4" Background="#0f1115" CornerRadius="4" Padding="12,10" Margin="4">
                                        <StackPanel>
                                            <TextBlock Text="PRESENT MODE   (Independent / Legacy Flip = OPTIMAL    -    Composed Copy = BAD, ~3-5ms DWM-Overhead)" Foreground="#9ca3af" FontSize="10"/>
                                            <TextBlock x:Name="lblCapPresentMode" Text="-" Foreground="#e5e7eb" FontSize="15" FontWeight="Bold" TextWrapping="Wrap" Margin="0,3,0,0"/>
                                            <TextBlock x:Name="lblCapPresentExplain" Text="" Foreground="#6b7280" FontSize="11" TextWrapping="Wrap" Margin="0,2,0,0"/>
                                        </StackPanel>
                                    </Border>

                                    <!-- Row 4: Metriken-Erklaerung (Expander) -->
                                    <Expander Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="4" Header="Was bedeuten diese Metriken?" Foreground="#93c5fd" FontSize="11" Margin="4,4,4,0">
                                        <Border Background="#0f1115" CornerRadius="4" Padding="12,10" Margin="0,6,0,0">
                                            <StackPanel>
                                                <TextBlock TextWrapping="Wrap" Foreground="#cbd5e1" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="#4ade80">AVG FPS</Run>
                                                    <Run> - Durchschnittliche Bilder/Sekunde. Hauptkennzahl, aber sagt nichts ueber Konsistenz aus.</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="#cbd5e1" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="#fbbf24">1% LOW</Run>
                                                    <Run> - FPS-Wert den die schlechtesten 1% der Frames erreichen. Wichtiger als AVG fuer Spielgefuehl. Gap zum AVG &gt; 30% = Stutter-Problem.</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="#cbd5e1" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="#f87171">0.1% LOW</Run>
                                                    <Run> - Die schlimmsten 0.1% der Frames - der "Floor" bei dem es richtig haengt. Niedriger Wert = sichtbare Hakler / Shadertompilations / Background-CPU-Spikes.</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="#cbd5e1" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="#60a5fa">STDDEV (ms)</Run>
                                                    <Run> - Standardabweichung der Frametimes in Millisekunden. Misst Frame-Pacing-Konsistenz: niedriger = gleichmaessig fluessig, hoeher = ruckelt selbst bei hoher AVG. Faustregel bei 200+ FPS: &lt; 0.5ms top, 0.5-1.5ms ok, &gt; 2ms unrund.</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="#cbd5e1" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="#e5e7eb">BOTTLENECK</Run>
                                                    <Run> - Wer limitiert die FPS: CPU-Bound (CPU rechnet zu lange pro Frame - mehr GPU-Last unkritisch), GPU-Bound (GPU am Limit - Settings reduzieren bringt FPS), Balanced (beide gleich ausgelastet, idealer Zustand fuer competitive).</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="#cbd5e1" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="#e5e7eb">CPU/GPU BUSY (ms)</Run>
                                                    <Run> - Wie viele Millisekunden CPU bzw. GPU pro Frame aktiv waren. Bei 200 FPS = 5ms Budget. Wer drueber ist = Bottleneck.</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="#cbd5e1" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="#e5e7eb">RENDER LATENCY</Run>
                                                    <Run> - Zeit vom Render-Start bis der Frame "Present"-ed wird. Niedrig = direkte Pipeline. UNTIL DISPLAYED ergaenzt das: Zeit bis Pixel tatsaechlich auf dem Monitor sichtbar sind (Frame-to-Photon).</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="#cbd5e1" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="#e5e7eb">CLICK -&gt; PHOTON</Run>
                                                    <Run> - Vollstaendige End-to-End-Latency Maus-Click bis sichtbare Reaktion. Nur verfuegbar bei NVIDIA Reflex (PUBG hat keinen direkten Reflex-Support - daher meist "NA").</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="#cbd5e1" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="#22c55e">PRESENT MODE</Run>
                                                    <Run> - Wie Windows den Frame an den Monitor uebergibt. Hierarchie:</Run>
                                                    <LineBreak/>
                                                    <Run FontWeight="Bold" Foreground="#22c55e">  - Hardware: Independent Flip  /  Hardware: Legacy Flip  =  OPTIMAL</Run>
                                                    <Run Foreground="#9ca3af"> (kein DWM-Compositor zwischendrin)</Run>
                                                    <LineBreak/>
                                                    <Run FontWeight="Bold" Foreground="#4ade80">  - Hardware Composed: Flip  /  Hardware: Legacy Copy  =  OK</Run>
                                                    <Run Foreground="#9ca3af"> (geringer DWM-Overhead)</Run>
                                                    <LineBreak/>
                                                    <Run FontWeight="Bold" Foreground="#f87171">  - Composed: Copy with GPU GDI  =  BAD</Run>
                                                    <Run Foreground="#9ca3af"> (~3-5ms zusaetzliche Latenz - meist durch laufendes RTSS, falsche DPI-Skalierung oder Multi-Monitor-Setup)</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="#cbd5e1" FontSize="11" Margin="0,0,0,6">
                                                    <Run FontWeight="Bold" Foreground="#e5e7eb">G-SYNC</Run>
                                                    <Run> - "AllowsTearing" Flag in &gt; 50% der Frames. Zeigt ob Variable Refresh Rate (G-Sync/FreeSync) aktiv arbeitet.</Run>
                                                </TextBlock>
                                                <TextBlock TextWrapping="Wrap" Foreground="#cbd5e1" FontSize="11">
                                                    <Run FontWeight="Bold" Foreground="#e5e7eb">STUTTER</Run>
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

                        <!-- History/Trend Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Trend (letzte Messungen)" Style="{StaticResource SectionHeader}"/>
                                <TextBlock x:Name="lblCapHistInfo" Text="" Foreground="#9ca3af" FontSize="11" Margin="0,0,0,8"/>
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

                    <TextBlock Grid.Row="0" Text="Aktionen die 'Start Game Mode' ausfuehrt" FontSize="14" FontWeight="Bold" Foreground="#93c5fd" Margin="0,0,0,10"/>

                    <StackPanel Grid.Row="1" Margin="0,0,0,16">
                        <CheckBox x:Name="cbMonitors" Content="Monitore: nur OLED aktiv (Acer XB271HU deaktivieren)" Foreground="#e5e7eb" Margin="0,4" IsChecked="True"/>
                        <CheckBox x:Name="cbRTSS" Content="RTSS Prozesse beenden (kritisch fuer Mode 3/1)" Foreground="#e5e7eb" Margin="0,4" IsChecked="True"/>
                        <CheckBox x:Name="cbBackground" Content="Hintergrund-Apps schliessen (Chrome, Spotify, Battle.net, Epic, OBS - Discord bleibt fuer Voice)" Foreground="#e5e7eb" Margin="0,4" IsChecked="True"/>
                        <CheckBox x:Name="cbTimer" Content="Timer Resolution 0.5 ms (SetTimerResolutionService - nicht im PoC)" Foreground="#6b7280" Margin="0,4" IsEnabled="False"/>
                        <CheckBox x:Name="cbLaunch" Content="PUBG via Steam direkt starten" Foreground="#e5e7eb" Margin="0,4" IsChecked="False"/>
                    </StackPanel>

                    <Grid Grid.Row="2" Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button x:Name="btnGMStart" Grid.Column="0" Content="🎯 START GAME MODE" Style="{StaticResource SuccessButton}" Height="44" FontSize="14" FontWeight="Bold" Margin="0,0,6,0"/>
                        <Button x:Name="btnGMExit" Grid.Column="1" Content="🛑 EXIT GAME MODE" Style="{StaticResource DangerButton}" Height="44" FontSize="14" FontWeight="Bold" Margin="6,0,0,0"/>
                    </Grid>

                    <Border Grid.Row="3" Background="#1a1d23" BorderBrush="#2d3139" BorderThickness="1" CornerRadius="4">
                        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="10">
                            <TextBlock x:Name="txtGMLog" Text="Log:&#x0a;" Foreground="#d1d5db" FontFamily="Consolas" FontSize="12"/>
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
                            <Button x:Name="btnSelectNone" Content="Clear" Width="80" Height="32"/>
                        </StackPanel>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Filter:" Foreground="#9ca3af" FontSize="11" VerticalAlignment="Center" Margin="0,0,8,0"/>
                            <Button x:Name="btnFilterAll" Content="Alle" Width="80" Height="26" Margin="0,0,4,0"/>
                            <Button x:Name="btnFilterOpen" Content="Offen" Width="80" Height="26" Margin="0,0,4,0"/>
                            <Button x:Name="btnFilterDone" Content="Angewendet" Width="120" Height="26"/>
                        </StackPanel>
                    </StackPanel>
                    <TextBlock Grid.Row="1" x:Name="lblTweakInfo" Text="" Foreground="#9ca3af" FontSize="11" Margin="0,0,0,4" TextWrapping="Wrap"/>
                    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
                        <StackPanel x:Name="tweakContainer"/>
                    </ScrollViewer>
                </Grid>
            </TabItem>

            <!-- TAB 5: SETTINGS -->
            <TabItem Header="Settings">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <!-- System Info Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Erkanntes System" Style="{StaticResource SectionHeader}"/>
                                <TextBlock x:Name="lblDetectedHw" Foreground="#d1d5db" FontFamily="Consolas" FontSize="11" TextWrapping="Wrap" LineHeight="18"/>
                            </StackPanel>
                        </Border>

                        <!-- Monitor Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <Grid>
                                    <TextBlock Text="Monitor-Setup" Style="{StaticResource SectionHeader}"/>
                                    <Button x:Name="btnDetectMonitors" Content="Erneut scannen" HorizontalAlignment="Right" Width="140" Margin="0,-4,0,0"/>
                                </Grid>
                                <TextBlock Text="Erkannte Displays:" Foreground="#9ca3af" FontSize="11" Margin="0,4,0,4"/>
                                <StackPanel x:Name="monitorList"/>

                                <TextBlock Text="Monitor-Pattern (Game-Mode)" Foreground="#e5e7eb" FontWeight="SemiBold" FontSize="12" Margin="0,18,0,4"/>
                                <TextBlock Foreground="#9ca3af" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8">
                                    <Run Text="Regex - matcht Monitor-Namen die im Game Mode deaktiviert werden."/>
                                    <LineBreak/>
                                    <Run Text="Tipp: 'Detect &amp; Fill' generiert den Pattern automatisch aus deinen Sekundaer-Monitoren."/>
                                </TextBlock>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="140"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="tbMonitorPattern" Grid.Column="0" Background="#0f1115" Foreground="#e5e7eb" BorderBrush="#2d3139" Padding="8,6" FontFamily="Consolas" VerticalContentAlignment="Center"/>
                                    <Button x:Name="btnAutoPattern" Grid.Column="1" Content="Detect &amp; Fill" Margin="8,0,0,0"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <!-- Tools Pfade Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Pfade (Tools &amp; State)" Style="{StaticResource SectionHeader}"/>
                                <TextBlock x:Name="lblPaths" Foreground="#d1d5db" FontFamily="Consolas" FontSize="10" TextWrapping="Wrap" LineHeight="16"/>
                            </StackPanel>
                        </Border>

                        <!-- Storage & Logs Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Storage / Logs / Backups" Style="{StaticResource SectionHeader}"/>
                                <TextBlock Foreground="#9ca3af" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8">
                                    <Run Text="Alle Apply/Revert-Aktionen werden geloggt. Snapshots erlauben Revert via Tweak-Button."/>
                                </TextBlock>
                                <StackPanel Orientation="Horizontal">
                                    <Button x:Name="btnOpenLogs" Content="Logs oeffnen" Width="140" Margin="0,0,8,0"/>
                                    <Button x:Name="btnOpenBackups" Content="Backups oeffnen" Width="160" Margin="0,0,8,0"/>
                                    <Button x:Name="btnClearHistory" Content="History loeschen" Width="160" Style="{StaticResource DangerButton}"/>
                                </StackPanel>
                                <TextBlock x:Name="lblHistoryStat" Foreground="#9ca3af" FontSize="11" Margin="0,8,0,0"/>
                            </StackPanel>
                        </Border>

                        <!-- About Card -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="About" Style="{StaticResource SectionHeader}"/>
                                <TextBlock Foreground="#d1d5db" TextWrapping="Wrap" LineHeight="20">
                                    <Run Text="PUBG Performance Suite" FontWeight="SemiBold"/>
                                    <Run Text="  -  v1.0.0-PoC (Local Build)"/>
                                    <LineBreak/><LineBreak/>
                                    <Run Text="Diese Suite konsolidiert alle PUBG-Competitive-Tweaks die wir in der Diagnose v6 identifiziert haben." Foreground="#9ca3af"/>
                                    <LineBreak/>
                                    <Run Text="Geplant: GitHub-Release fuer Multi-User-Distribution mit irm | iex Bootstrap." Foreground="#9ca3af"/>
                                    <LineBreak/><LineBreak/>
                                    <Run Text="Auto-Detection:" FontWeight="SemiBold" Foreground="#93c5fd"/>
                                    <Run Text="  Monitor-Hz, PUBG-Steam-Pfad, dedizierte GPU, Energieplan, NPI-Apply-Stamp"/>
                                    <LineBreak/>
                                    <Run Text="Backups:" FontWeight="SemiBold" Foreground="#93c5fd"/>
                                    <Run Text="  Tweaks legen .bak_&lt;timestamp&gt; neben das Original an"/>
                                    <LineBreak/>
                                    <Run Text="Sicher:" FontWeight="SemiBold" Foreground="#93c5fd"/>
                                    <Run Text="  Keine BattlEye-Risk-Tweaks (kein Special K, ReShade, DXVK, ban-bait Engine.ini)"/>
                                </TextBlock>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- Footer -->
        <Border Grid.Row="2" Background="#1a1d23" BorderBrush="#2d3139" BorderThickness="0,1,0,0" Padding="20,8">
            <TextBlock x:Name="lblFooter" Text="Bereit." Foreground="#6b7280" FontSize="11"/>
        </Border>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Control-Refs
$ctrls = @{}
foreach ($name in @('mainTabs','lblVersion','lblAdmin','adminBadge','lblTopStatus','btnRefresh','statusItems','lblStatusSubtitle','recoList','recoEmptyState','btnStartGameMode','btnExitGameMode',
    'btnApplySelected','btnApplyAll','btnRefreshTweaks','btnSelectAll','btnSelectNone','lblTweakInfo','tweakContainer',
    'btnFilterAll','btnFilterOpen','btnFilterDone',
    'lblDetectedHw','monitorList','btnDetectMonitors','btnAutoPattern',
    'btnOpenLogs','btnOpenBackups','btnClearHistory','lblHistoryStat',
    'lblCapToolStatus','btnCapStart','btnCapStop','lblCapPhase',
    'lblCapLastInfo','capResultGrid','lblCapAvg','lblCap1Low','lblCap01Low','lblCapStdDev','lblCapStability',
    'lblCapBottleneck','lblCapCpuBusy','lblCapGpuBusy','lblCapRenderLat',
    'lblCapUntilDisp','lblCapClickPhoton','lblCapGSync','lblCapStutter',
    'lblCapPresentMode','lblCapPresentExplain',
    'btnCapOpenCsv','btnCapOpenFolder','btnCapCompare','btnCapRebuild','btnCapClearHist','lblCapHistInfo','capHistoryList',
    'btnRunDiag','btnOpenHTML','btnOpenReports','txtDiagOutput',
    'cbMonitors','cbRTSS','cbBackground','cbTimer','cbLaunch','btnGMStart','btnGMExit','txtGMLog',
    'lblPaths','tbMonitorPattern','lblFooter')) {
    $ctrls[$name] = $window.FindName($name)
}

# ==================== UI HELPERS ====================
$colorByStatus = @{
    'OK'   = @{ Border='#4ade80'; Text='#4ade80' }
    'WARN' = @{ Border='#fbbf24'; Text='#fbbf24' }
    'BAD'  = @{ Border='#f87171'; Text='#f87171' }
    'INFO' = @{ Border='#60a5fa'; Text='#e5e7eb' }
    'SKIP' = @{ Border='#9ca3af'; Text='#9ca3af' }
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

    $ctrls.recoList.Children.Clear()
    if ($recos.Count -eq 0) {
        $ctrls.recoEmptyState.Visibility = 'Visible'
    } else {
        $ctrls.recoEmptyState.Visibility = 'Collapsed'
        foreach ($r in $recos) {
            $border = New-Object System.Windows.Controls.Border
            $border.Background = '#1a1d23'
            $border.BorderBrush = if ($r.Sev -eq 'BAD') { '#f87171' } else { '#fbbf24' }
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
            $sevColor = if ($r.Sev -eq 'BAD') { '#f87171' } else { '#fbbf24' }

            $titleSp = New-Object System.Windows.Controls.StackPanel
            $titleSp.Orientation = 'Horizontal'
            $tbIcon = New-Object System.Windows.Controls.TextBlock
            $tbIcon.Text = $sevIcon; $tbIcon.Foreground = $sevColor; $tbIcon.FontWeight = 'Bold'; $tbIcon.FontSize = 13
            $tbIcon.Margin = New-Object System.Windows.Thickness 0,0,6,0
            $titleSp.Children.Add($tbIcon) | Out-Null
            $tbTitle = New-Object System.Windows.Controls.TextBlock
            $tbTitle.Text = $r.Title; $tbTitle.Foreground = '#e5e7eb'; $tbTitle.FontWeight = 'SemiBold'; $tbTitle.FontSize = 12
            $titleSp.Children.Add($tbTitle) | Out-Null
            $sp.Children.Add($titleSp) | Out-Null

            $tbDetail = New-Object System.Windows.Controls.TextBlock
            $tbDetail.Text = $r.Detail; $tbDetail.Foreground = '#9ca3af'; $tbDetail.FontSize = 11
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
    $tweakKeys = @('HVCI','Energieplan','GameDVR','Monitore','RTSS','Engine.ini','NV Profil','Defender')
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
    } catch {}
    $footerParts = @("Status: $(Get-Date -Format 'HH:mm:ss')")
    if ($lastApply) { $footerParts += $lastApply }
    $ctrls.lblFooter.Text = ($footerParts -join '   |   ')
}

function Write-GMLog {
    param([string]$Msg, [string]$Level = 'INFO')
    $color = switch ($Level) {
        'OK'   { '#4ade80' }
        'WARN' { '#fbbf24' }
        'BAD'  { '#f87171' }
        default { '#d1d5db' }
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
                   -KillBackground $ctrls.cbBackground.IsChecked -SetTimerResolution $ctrls.cbTimer.IsChecked `
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
            } catch {}
        }
    }
    if (-not $vramTxt -and $dGpu -and $dGpu.AdapterRAM) {
        $vramTxt = "  ($([math]::Round($dGpu.AdapterRAM / 1GB, 1)) GB VRAM)"
    }

    $ctrls.lblDetectedHw.Text = @"
CPU:             $cpu
GPU:             $gpuName$vramTxt
RAM:             $ram GB
Monitor (Hz):    $hz Hz  (dynamischer FPS-Cap: $cap)
Aktive Displays: $([System.Windows.Forms.Screen]::AllScreens.Count) (vom DWM genutzt)
"@
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
            $monitors += [PSCustomObject]@{
                'Monitor Name' = "$manu $model"
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
        $tb.Foreground = '#9ca3af'; $tb.FontSize = 11
        $ctrls.monitorList.Children.Add($tb) | Out-Null
        return
    }

    foreach ($m in $monitors) {
        $isActive = ($m.Active -eq 'Yes')
        $isPrimary = ($m.Primary -eq 'Yes')

        $b = New-Object System.Windows.Controls.Border
        $b.Background = '#0f1115'
        $b.Padding = (New-Object System.Windows.Thickness 10,6,10,6)
        $b.Margin = (New-Object System.Windows.Thickness 0,3,0,0)
        $b.CornerRadius = (New-Object System.Windows.CornerRadius 4)
        $b.BorderBrush = if ($isPrimary) { '#60a5fa' } elseif ($isActive) { '#4ade80' } else { '#374151' }
        $b.BorderThickness = (New-Object System.Windows.Thickness 0,0,0,2)

        $grid = New-Object System.Windows.Controls.Grid
        $b.Child = $grid
        foreach ($w in 70,140,'*',80) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            if ($w -eq '*') { $cd.Width = '*' } else { $cd.Width = $w }
            $grid.ColumnDefinitions.Add($cd) | Out-Null
        }

        $stTxt = New-Object System.Windows.Controls.TextBlock
        $col = if ($isActive) { '#4ade80' } else { '#9ca3af' }
        $stTxt.Text = if ($isActive) { 'AKTIV' } else { 'inaktiv' }
        $stTxt.Foreground = $col; $stTxt.FontWeight = 'Bold'; $stTxt.FontSize = 10
        $stTxt.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($stTxt, 0)
        $grid.Children.Add($stTxt) | Out-Null

        $idTxt = New-Object System.Windows.Controls.TextBlock
        $id = $m.'Short Monitor ID'; if (-not $id) { $id = '-' }
        $idTxt.Text = $id; $idTxt.Foreground = '#9ca3af'; $idTxt.FontSize = 10
        $idTxt.FontFamily = (New-Object System.Windows.Media.FontFamily 'Consolas')
        $idTxt.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($idTxt, 1)
        $grid.Children.Add($idTxt) | Out-Null

        $nmTxt = New-Object System.Windows.Controls.TextBlock
        $nm = $m.'Monitor Name'
        if (-not $nm) {
            # Falls Name leer - oft bei OLED via DisplayPort - via Manu+Product zeigen
            $manu = $m.'Monitor Serial Number'
            if (-not $manu) { $manu = '(EDID liefert kein Friendly-Name - vermutlich OLED ueber DP)' }
            $nm = $manu
        }
        $nmTxt.Text = $nm; $nmTxt.Foreground = '#e5e7eb'; $nmTxt.FontSize = 11
        $nmTxt.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($nmTxt, 2)
        $grid.Children.Add($nmTxt) | Out-Null

        if ($isPrimary) {
            $pBadge = New-Object System.Windows.Controls.Border
            $pBadge.Background = '#1e3a8a'; $pBadge.CornerRadius = (New-Object System.Windows.CornerRadius 3)
            $pBadge.Padding = (New-Object System.Windows.Thickness 6,2,6,2)
            $pBadge.VerticalAlignment = 'Center'; $pBadge.HorizontalAlignment = 'Right'
            $pTxt = New-Object System.Windows.Controls.TextBlock
            $pTxt.Text = 'PRIMARY'; $pTxt.Foreground = '#bfdbfe'; $pTxt.FontSize = 9; $pTxt.FontWeight = 'Bold'
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
        $ctrls.lblHistoryStat.Text = "History: $($entries.Count) Eintraege - $applies Apply, $reverts Revert, $errors Fehler"
    } catch { $ctrls.lblHistoryStat.Text = '' }
}

$ctrls.btnOpenLogs.Add_Click({
    Initialize-SuiteStorage
    Start-Process explorer.exe -ArgumentList $Global:Suite.LogDir
})
$ctrls.btnOpenBackups.Add_Click({
    Initialize-SuiteStorage
    Start-Process explorer.exe -ArgumentList $Global:Suite.BackupDir
})
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

# ==================== NPI (NVIDIA Profile Inspector) ====================
$Global:NPIDefaultDir = 'C:\Tools\nvidiaProfileInspector'

function Get-NPIPath {
    $candidates = @(
        "$Global:NPIDefaultDir\nvidiaProfileInspector.exe",
        "$env:USERPROFILE\Tools\nvidiaProfileInspector\nvidiaProfileInspector.exe",
        "$env:USERPROFILE\Downloads\nvidiaProfileInspector\nvidiaProfileInspector.exe",
        "$env:USERPROFILE\Downloads\nvidiaProfileInspector.exe"
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

function Install-NPIFromGitHub {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Write-SuiteLog "NPI-Install: hole Release-Info von GitHub..."
        $apiUrl = 'https://api.github.com/repos/Orbmu2k/nvidiaProfileInspector/releases/latest'
        $headers = @{ 'User-Agent' = 'PUBG-Suite' }
        $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
        $zipAsset = $release.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
        if (-not $zipAsset) { throw 'Kein ZIP-Asset im NPI-Release gefunden' }

        $target = $Global:NPIDefaultDir
        try {
            if (-not (Test-Path $target)) { New-Item -Path $target -ItemType Directory -Force -ErrorAction Stop | Out-Null }
        } catch {
            $target = Join-Path $env:USERPROFILE 'Tools\nvidiaProfileInspector'
            Write-SuiteLog "NPI-Install fallback target: $target" 'WARN'
            if (-not (Test-Path $target)) { New-Item -Path $target -ItemType Directory -Force | Out-Null }
        }
        $zipPath = Join-Path $env:TEMP "npi_$($release.tag_name)_$(Get-Random).zip"
        try {
            Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
            Expand-Archive -Path $zipPath -DestinationPath $target -Force -ErrorAction Stop
        } finally {
            if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
        }
        $npiExe = Join-Path $target 'nvidiaProfileInspector.exe'
        if (-not (Test-Path $npiExe)) {
            $found = Get-ChildItem -Path $target -Recurse -Filter 'nvidiaProfileInspector.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $npiExe = $found.FullName }
        }
        if (Test-Path $npiExe) {
            Write-SuiteLog "NPI installiert: $npiExe ($($release.tag_name))" 'INFO'
            return $npiExe
        }
        Write-SuiteLog "NPI-Install: Executable nicht im Archiv" 'ERROR'
        return $null
    } catch {
        Write-SuiteLog "NPI-Install Fehler: $($_.Exception.Message)" 'ERROR'
        return $null
    }
}

function Invoke-NPIPubgProfile {
    param([string]$NpiPath)
    if (-not $NpiPath -or -not (Test-Path $NpiPath)) {
        Write-SuiteLog "Invoke-NPIPubgProfile: NPI-Pfad ungueltig: $NpiPath" 'ERROR'
        return $false
    }
    $profileName = "PLAYERUNKNOWN'S BATTLEGROUNDS"
    $settings = @(
        @{ Id='0x1033DCD2'; Val='0x00000001'; Desc='Power Management Mode = Prefer Max Performance' }
        @{ Id='0x00A879CF'; Val='0x00000000'; Desc='Vertical Sync = Force OFF' }
        @{ Id='0x00CE0E32'; Val='0x00000000'; Desc='Texture Filtering Quality = High Performance' }
        @{ Id='0x20FF7493'; Val='0x00000001'; Desc='Threaded Optimization = ON' }
        @{ Id='0x10835000'; Val='0x00000002'; Desc='Low Latency Mode = Ultra' }
        @{ Id='0x10835013'; Val='0x000000ED'; Desc='Frame Rate Limiter v3 = 237 FPS' }
        @{ Id='0x00D55F7D'; Val='0x00000000'; Desc='Antialiasing Mode = Application Controlled' }
        @{ Id='0x101E61A9'; Val='0x00000002'; Desc='Anisotropic Filtering = Use Global' }
    )
    $ok = 0; $fail = 0
    foreach ($s in $settings) {
        try {
            $null = & $NpiPath '-setProfileSetting' $profileName $s.Id $s.Val 2>&1
            if ($null -eq $LASTEXITCODE -or $LASTEXITCODE -eq 0) {
                $ok++
                Write-SuiteLog "NPI OK: $($s.Desc)"
            } else {
                $fail++
                Write-SuiteLog "NPI FAIL: $($s.Desc) (Exit $LASTEXITCODE)" 'WARN'
            }
        } catch {
            $fail++
            Write-SuiteLog "NPI ERR: $($s.Desc) - $($_.Exception.Message)" 'ERROR'
        }
    }
    # Stamp setzen
    try {
        $sd = Split-Path $Global:Suite.NPIStamp -Parent
        if (-not (Test-Path $sd)) { New-Item -Path $sd -ItemType Directory -Force | Out-Null }
        Get-Date | Out-File $Global:Suite.NPIStamp -Force
    } catch {}
    Write-SuiteLog "NPI Apply: $ok ok, $fail fail" 'INFO'
    return ($ok -gt 0 -and $fail -eq 0)
}

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
    if (-not (Test-Path $CsvPath)) { return $null }
    try {
        $data = Import-Csv $CsvPath
        if ($data.Count -lt 10) {
            return @{ Error = "CSV zu klein ($($data.Count) Zeilen) - PUBG lief nicht?" }
        }

        $ft = @($data | ForEach-Object {
            try { [double]$_.MsBetweenPresents } catch { 0 }
        } | Where-Object { $_ -gt 0 })

        if ($ft.Count -lt 10) {
            return @{ Error = "Keine validen Frametimes in CSV" }
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
function Invoke-TweakApply {
    param($Tweak)
    Write-SuiteLog "Apply START: $($Tweak.Id) ($($Tweak.Name))"
    try {
        $snapshot = $null
        if ($Tweak.SnapshotFn) {
            try { $snapshot = & $Tweak.SnapshotFn } catch { Write-SuiteLog "Snapshot fail $($Tweak.Id): $($_.Exception.Message)" 'WARN' }
        }
        $result = & $Tweak.ApplyFn
        if ($result) {
            Add-HistoryEntry -Action 'Apply' -TweakId $Tweak.Id -Snapshot $snapshot -Success $true
            Write-SuiteLog "Apply OK: $($Tweak.Id)" 'INFO'
        } else {
            Add-HistoryEntry -Action 'Apply' -TweakId $Tweak.Id -Snapshot $snapshot -Success $false -ErrorMsg 'ApplyFn returned false'
            Write-SuiteLog "Apply FAIL: $($Tweak.Id) (ApplyFn returned false)" 'ERROR'
        }
        return $result
    } catch {
        $msg = $_.Exception.Message
        Add-HistoryEntry -Action 'Apply' -TweakId $Tweak.Id -Success $false -ErrorMsg $msg
        Write-SuiteLog "Apply EXCEPTION: $($Tweak.Id) - $msg" 'ERROR'
        return $false
    }
}

function Invoke-TweakRevert {
    param($Tweak)
    Write-SuiteLog "Revert START: $($Tweak.Id)"
    if (-not $Tweak.RevertFn) {
        Write-SuiteLog "Revert FAIL: $($Tweak.Id) - keine RevertFn implementiert" 'WARN'
        return $false
    }
    $snapshot = Get-LastSnapshot -TweakId $Tweak.Id
    if (-not $snapshot) {
        Write-SuiteLog "Revert FAIL: $($Tweak.Id) - kein Snapshot in History" 'WARN'
        return $false
    }
    try {
        $result = & $Tweak.RevertFn $snapshot
        if ($result) {
            Add-HistoryEntry -Action 'Revert' -TweakId $Tweak.Id -Success $true
            Write-SuiteLog "Revert OK: $($Tweak.Id)" 'INFO'
        } else {
            Add-HistoryEntry -Action 'Revert' -TweakId $Tweak.Id -Success $false -ErrorMsg 'RevertFn returned false'
            Write-SuiteLog "Revert FAIL: $($Tweak.Id) (RevertFn returned false)" 'ERROR'
        }
        return $result
    } catch {
        $msg = $_.Exception.Message
        Add-HistoryEntry -Action 'Revert' -TweakId $Tweak.Id -Success $false -ErrorMsg $msg
        Write-SuiteLog "Revert EXCEPTION: $($Tweak.Id) - $msg" 'ERROR'
        return $false
    }
}

function Test-TweakRevertable {
    param($Tweak)
    if (-not $Tweak.RevertFn) { return $false }
    return ($null -ne (Get-LastSnapshot -TweakId $Tweak.Id))
}

# ==================== TWEAKS TAB UI ====================
$Global:TweakSelection = @{}  # Id -> bool
$Global:TweakFilter = 'open'   # 'all' / 'open' / 'done' - default: zeige nur was zu tun ist

function Build-TweakRow {
    param($Tweak)

    $status = & $Tweak.StatusFn
    $statusColors = @{ 'OK' = '#4ade80'; 'WARN' = '#fbbf24'; 'BAD' = '#f87171'; 'SKIP' = '#9ca3af' }
    $color = $statusColors[$status]; if (-not $color) { $color = '#9ca3af' }

    # Outer Border
    $row = New-Object System.Windows.Controls.Border
    $row.Background = '#1a1d23'
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
    $stBorder.Background = '#0f1115'; $stBorder.CornerRadius = (New-Object System.Windows.CornerRadius 3)
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
        $btn.Background = '#ea580c'  # orange
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
    $catBg.Background = '#374151'; $catBg.CornerRadius = (New-Object System.Windows.CornerRadius 3)
    $catBg.Padding = (New-Object System.Windows.Thickness 6,2,6,2)
    $catBg.VerticalAlignment = 'Center'; $catBg.Margin = (New-Object System.Windows.Thickness 0,0,10,0)
    $catTxt = New-Object System.Windows.Controls.TextBlock
    $catTxt.Text = $Tweak.Cat.ToUpper(); $catTxt.Foreground = '#e5e7eb'
    $catTxt.FontSize = 9; $catTxt.FontWeight = 'SemiBold'
    $catBg.Child = $catTxt
    $leftSp.Children.Add($catBg) | Out-Null

    $nameTxt = New-Object System.Windows.Controls.TextBlock
    $nameTxt.Text = $Tweak.Name; $nameTxt.Foreground = '#e5e7eb'; $nameTxt.FontSize = 12; $nameTxt.FontWeight = 'SemiBold'
    $nameTxt.VerticalAlignment = 'Center'
    $leftSp.Children.Add($nameTxt) | Out-Null

    $hdr.Children.Add($leftSp) | Out-Null

    # Desc + Impact line
    $detailLine = New-Object System.Windows.Controls.TextBlock
    $impTxt = "Alltag: $($Tweak.Impact)"
    if ($Tweak.ImpactDetail) { $impTxt += " - $($Tweak.ImpactDetail)" }
    $detailLine.Text = "$($Tweak.Desc)  |  $impTxt"
    $detailLine.Foreground = '#9ca3af'; $detailLine.FontSize = 10
    $detailLine.TextWrapping = 'Wrap'
    $detailLine.Margin = (New-Object System.Windows.Thickness 30,4,0,0)
    $vsp.Children.Add($detailLine) | Out-Null

    # Expander mit Changes-Details
    if ($Tweak.Changes -and $Tweak.Changes.Count -gt 0) {
        $exp = New-Object System.Windows.Controls.Expander
        $exp.Header = 'Was wird veraendert? (Details anzeigen)'
        $exp.Foreground = '#60a5fa'; $exp.FontSize = 10
        $exp.Margin = (New-Object System.Windows.Thickness 30,4,0,0)

        $chSp = New-Object System.Windows.Controls.StackPanel
        $chSp.Margin = (New-Object System.Windows.Thickness 0,4,0,4)
        foreach ($ch in $Tweak.Changes) {
            $chTxt = New-Object System.Windows.Controls.TextBlock
            $chTxt.Text = "* $ch"
            $chTxt.Foreground = '#d1d5db'; $chTxt.FontSize = 10
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
            $btns[$key].Background = '#2563eb'
        } else {
            $btns[$key].Background = '#374151'
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

    $catOrder = @('Windows','PUBG','System')
    $foundCats = $filteredTweaks | ForEach-Object { $_.Cat } | Sort-Object -Unique
    $cats = @($catOrder | Where-Object { $_ -in $foundCats }) + @($foundCats | Where-Object { $_ -notin $catOrder })

    if ($filteredTweaks.Count -eq 0) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = switch ($Global:TweakFilter) {
            'open' { '+ Alle Tweaks angewendet. Nichts mehr zu tun!' }
            'done' { 'Noch keine Tweaks angewendet.' }
            default { 'Keine Tweaks definiert.' }
        }
        $empty.Foreground = if ($Global:TweakFilter -eq 'open') { '#4ade80' } else { '#9ca3af' }
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
            $header.Foreground = '#93c5fd'; $header.FontSize = 13; $header.FontWeight = 'Bold'
            $header.Margin = (New-Object System.Windows.Thickness 0,12,0,6)
            $ctrls.tweakContainer.Children.Add($header) | Out-Null

            foreach ($t in $catTweaks) {
                $row = Build-TweakRow -Tweak $t
                $ctrls.tweakContainer.Children.Add($row) | Out-Null
            }
        }
    }

    $total = $Global:Tweaks.Count
    $okCnt = @($tweakStatuses.Values | Where-Object { $_ -eq 'OK' }).Count
    $needCnt = @($tweakStatuses.Values | Where-Object { $_ -eq 'WARN' -or $_ -eq 'BAD' }).Count
    $sel = @($Global:TweakSelection.GetEnumerator() | Where-Object { $_.Value }).Count

    # Filter-Button-Labels mit Counts
    $ctrls.btnFilterAll.Content = "Alle ($total)"
    $ctrls.btnFilterOpen.Content = "Offen ($needCnt)"
    $ctrls.btnFilterDone.Content = "Angewendet ($okCnt)"

    Update-FilterButtonStyles

    # Info-Zeile (vorhandene Last-Apply-Info aus Global state behalten)
    $base = "$okCnt von $total angewendet  |  $needCnt offen  |  $sel selektiert  |  Filter: $($Global:TweakFilter)"
    if ($Global:LastApplyInfo) {
        $ctrls.lblTweakInfo.Text = "$base`n$($Global:LastApplyInfo)"
    } else {
        $ctrls.lblTweakInfo.Text = $base
    }
}

$ctrls.btnRefreshTweaks.Add_Click({ Update-TweaksTab; Update-StatusGrid })

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
        $ctrls.lblCapToolStatus.Foreground = '#4ade80'
    } else {
        $ctrls.lblCapToolStatus.Text = 'NICHT installiert - wird beim Start automatisch geladen'
        $ctrls.lblCapToolStatus.Foreground = '#fbbf24'
    }
}

function Show-CapResult {
    param($Result)
    if (-not $Result -or $Result.Error) {
        $errMsg = if ($Result) { $Result.Error } else { 'unbekannt' }
        $ctrls.lblCapLastInfo.Text = "Fehler: $errMsg"
        $ctrls.lblCapLastInfo.Foreground = '#f87171'
        $ctrls.capResultGrid.Visibility = 'Collapsed'
        return
    }
    $timeStr = if ($Result.CaptureTime -is [datetime]) { $Result.CaptureTime.ToString('yyyy-MM-dd HH:mm:ss') } else { [string]$Result.CaptureTime }
    $ctrls.lblCapLastInfo.Text = "$timeStr  -  $($Result.Frames) Frames in $($Result.DurationSec)s  -  $($Result.FileName)"
    $ctrls.lblCapLastInfo.Foreground = '#9ca3af'
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
        'BEST' { '#22c55e' }   # knalliges Gruen (Bestnote)
        'OK'   { '#4ade80' }   # normales Gruen
        'WARN' { '#fbbf24' }
        'BAD'  { '#f87171' }
        default{ '#e5e7eb' }
    }
    $ctrls.lblCapPresentMode.Foreground = $modeColor
    # Erklaerungstext in passender Severity-Farbe (BEST/OK gruen-ish, sonst normal grau)
    $ctrls.lblCapPresentExplain.Text = if ($Result.PresentModeExplain) { $Result.PresentModeExplain } else { '' }
    $ctrls.lblCapPresentExplain.Foreground = switch ($Result.PresentModeQuality) {
        'BEST' { '#86efac' }
        'OK'   { '#86efac' }
        'WARN' { '#fcd34d' }
        'BAD'  { '#fca5a5' }
        default{ '#9ca3af' }
    }

    # Bottleneck mit Farbcode
    if ($Result.Bottleneck) {
        $ctrls.lblCapBottleneck.Text = $Result.Bottleneck
        $ctrls.lblCapBottleneck.Foreground = switch ($Result.Bottleneck) {
            'Balanced'   { '#4ade80' }
            'GPU-Bound'  { '#fbbf24' }
            'CPU-Bound'  { '#fbbf24' }
            default      { '#9ca3af' }
        }
    } else {
        $ctrls.lblCapBottleneck.Text = '-'
        $ctrls.lblCapBottleneck.Foreground = '#9ca3af'
    }

    # CPU/GPU Busy Werte
    $ctrls.lblCapCpuBusy.Text = if ($null -ne $Result.CpuBusyMs) { "$($Result.CpuBusyMs) ms" } else { 'NA' }
    $ctrls.lblCapGpuBusy.Text = if ($null -ne $Result.GpuBusyMs) { "$($Result.GpuBusyMs) ms" } else { 'NA' }
    # Hoeherer Wert in gelb, anderer neutral
    if ($null -ne $Result.CpuBusyMs -and $null -ne $Result.GpuBusyMs) {
        if ($Result.CpuBusyMs -gt $Result.GpuBusyMs) {
            $ctrls.lblCapCpuBusy.Foreground = '#fbbf24'
            $ctrls.lblCapGpuBusy.Foreground = '#e5e7eb'
        } elseif ($Result.GpuBusyMs -gt $Result.CpuBusyMs) {
            $ctrls.lblCapGpuBusy.Foreground = '#fbbf24'
            $ctrls.lblCapCpuBusy.Foreground = '#e5e7eb'
        } else {
            $ctrls.lblCapCpuBusy.Foreground = '#e5e7eb'
            $ctrls.lblCapGpuBusy.Foreground = '#e5e7eb'
        }
    } else {
        $ctrls.lblCapCpuBusy.Foreground = '#9ca3af'
        $ctrls.lblCapGpuBusy.Foreground = '#9ca3af'
    }

    # Render Latency + Until Displayed + Click-to-Photon
    $ctrls.lblCapRenderLat.Text = if ($null -ne $Result.RenderLatencyMs) { "$($Result.RenderLatencyMs) ms" } else { 'NA' }
    $ctrls.lblCapRenderLat.Foreground = if ($null -ne $Result.RenderLatencyMs) {
        if ($Result.RenderLatencyMs -lt 8) { '#4ade80' }
        elseif ($Result.RenderLatencyMs -lt 16) { '#fbbf24' }
        else { '#f87171' }
    } else { '#9ca3af' }

    $ctrls.lblCapUntilDisp.Text = if ($null -ne $Result.UntilDisplayedMs) { "$($Result.UntilDisplayedMs) ms" } else { 'NA' }
    $ctrls.lblCapUntilDisp.Foreground = if ($null -ne $Result.UntilDisplayedMs) { '#e5e7eb' } else { '#9ca3af' }

    $ctrls.lblCapClickPhoton.Text = if ($null -ne $Result.ClickToPhotonMs) { "$($Result.ClickToPhotonMs) ms" } else { 'NA' }
    $ctrls.lblCapClickPhoton.Foreground = if ($null -ne $Result.ClickToPhotonMs) { '#e5e7eb' } else { '#6b7280' }

    if ($Result.GSyncActive) {
        $ctrls.lblCapGSync.Text = 'AKTIV'
        $ctrls.lblCapGSync.Foreground = '#4ade80'
    } else {
        $ctrls.lblCapGSync.Text = 'inaktiv'
        $ctrls.lblCapGSync.Foreground = '#9ca3af'
    }

    $ctrls.lblCapStutter.Text = "$($Result.StutterPct)%"
    $ctrls.lblCapStutter.Foreground = if ($Result.StutterPct -lt 0.2) { '#4ade80' } elseif ($Result.StutterPct -lt 0.5) { '#fbbf24' } else { '#f87171' }
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
        $hdr.Background = '#0f1115'; $hdr.Padding = (New-Object System.Windows.Thickness 8,4,8,4)
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
            $tb.Text = $hdrTexts[$i]; $tb.Foreground = '#9ca3af'; $tb.FontSize = 10; $tb.FontWeight = 'SemiBold'
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
                $row.Background = '#1a1d23'; $row.Padding = (New-Object System.Windows.Thickness 8,4,8,4)
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
                $delta = ''; $deltaColor = '#9ca3af'
                if ($baselineAvg -gt 0 -and $null -ne $e.AvgFps -and $e -ne $baseline) {
                    $diff = [double]$e.AvgFps - $baselineAvg
                    $sign = if ($diff -ge 0) { '+' } else { '' }
                    $delta = "$sign$([math]::Round($diff, 1))"
                    if ($diff -gt 2) { $deltaColor = '#4ade80' }
                    elseif ($diff -lt -2) { $deltaColor = '#f87171' }
                    else { $deltaColor = '#fbbf24' }
                }

                # Mode-Label: PresentMon v2 schreibt schon Strings wie "Hardware: Legacy Flip".
                # Alte History-Eintraege koennten "Mode " hardcoded davor haben - kuerze das raus.
                $modeStr = if ($e.PresentModeLabel) { [string]$e.PresentModeLabel }
                           elseif ($e.PresentMode) { [string]$e.PresentMode }
                           else { '?' }
                $modeStr = $modeStr -replace '^Mode\s+',''
                # Mode-Farbe nach Quality (BEST=knall-gruen, OK=gruen, WARN=gelb, BAD=rot)
                $modeColor = switch -Wildcard ($modeStr) {
                    '*Independent Flip*'  { '#22c55e' }
                    '*Legacy Flip*'       { '#22c55e' }
                    '*Composed Flip*'     { '#4ade80' }
                    '*Legacy Copy*'       { '#4ade80' }
                    '*Composed Copy*'     { '#f87171' }
                    '*Composition Atlas*' { '#fbbf24' }
                    default               { '#e5e7eb' }
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
                $cols = @('#d1d5db','#4ade80','#fbbf24','#f87171','#60a5fa',$modeColor,$deltaColor)
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
                $row.Add_MouseEnter({ $this.Background = '#252830' })
                $row.Add_MouseLeave({ $this.Background = '#1a1d23' })

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
        try { $Global:CaptureState.Timer.Stop() } catch {}
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
        $ctrls.lblCapPhase.Foreground = '#fbbf24'
        Write-SuiteLog "PresentMon nicht gefunden - starte Auto-Install" 'INFO'
        $pm = Install-PresentMonFromGitHub
        Update-CapToolStatus
        if (-not $pm) {
            $ctrls.lblCapPhase.Text = 'PresentMon-Install fehlgeschlagen - Logs pruefen'
            $ctrls.lblCapPhase.Foreground = '#f87171'
            return
        }
    }

    # PUBG laeuft?
    $pubg = @(Get-Process -Name 'TslGame' -ErrorAction SilentlyContinue)
    if ($pubg.Count -eq 0) {
        $ctrls.lblCapPhase.Text = 'PUBG (TslGame.exe) laeuft nicht - erst Spiel starten + ins Match'
        $ctrls.lblCapPhase.Foreground = '#f87171'
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
                    $ctrls.lblCapPhase.Foreground = '#fbbf24'
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
                        $ctrls.lblCapPhase.Foreground = '#4ade80'
                        Write-SuiteLog "PresentMon gestartet PID $($proc.Id)"
                    } catch {
                        $ctrls.lblCapPhase.Text = "Fehler beim PresentMon-Start: $($_.Exception.Message)"
                        $ctrls.lblCapPhase.Foreground = '#f87171'
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
                    $ctrls.lblCapPhase.Foreground = '#60a5fa'
                }
            } elseif ($state.Phase -eq 'analyzing') {
                Stop-CaptureTimer
                # CSV analysieren
                $result = Analyze-CaptureCSV -CsvPath $state.OutputCsv
                if ($result.Error) {
                    $ctrls.lblCapPhase.Text = "Analyse-Fehler: $($result.Error)"
                    $ctrls.lblCapPhase.Foreground = '#f87171'
                    Write-SuiteLog "Capture Analyse Fehler: $($result.Error)" 'ERROR'
                } else {
                    Show-CapResult $result
                    Add-CaptureEntry $result
                    Update-CapHistory
                    $ctrls.lblCapPhase.Text = "Fertig - $($result.Frames) Frames erfasst, AvgFps $($result.AvgFps)"
                    $ctrls.lblCapPhase.Foreground = '#4ade80'
                    Write-SuiteLog "Capture fertig: AvgFps=$($result.AvgFps) 1%=$($result.OnePctLow) Mode=$($result.PresentMode)"
                    $Global:CaptureState.LastResult = $result
                }
                Cleanup-CapState
            }
        } catch {
            Write-SuiteLog "Capture-Timer Fehler: $($_.Exception.Message)" 'ERROR'
            $ctrls.lblCapPhase.Text = "Timer-Fehler: $($_.Exception.Message)"
            $ctrls.lblCapPhase.Foreground = '#f87171'
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
    $ctrls.lblCapPhase.Foreground = '#fbbf24'
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
    $color = if ([math]::Abs($pct) -lt 1) { '#9ca3af' } elseif ($isPositive) { '#4ade80' } else { '#f87171' }
    return @{ Text = "$diffStr $pctStr"; Color = $color }
}

$ctrls.btnCapCompare.Add_Click({
    $hist = @(Get-CaptureHistory)
    if ($hist.Count -lt 2) {
        [System.Windows.MessageBox]::Show('Mindestens 2 Messungen noetig fuer Vergleich. Aktuell vorhanden: ' + $hist.Count, 'Compare', 'OK', 'Information') | Out-Null
        return
    }
    $current = $hist[-1]
    $previous = $hist[-2]

    $deltaAvg   = Format-Delta -Current ([double]$current.AvgFps) -Previous ([double]$previous.AvgFps)
    $delta1     = Format-Delta -Current ([double]$current.OnePctLow) -Previous ([double]$previous.OnePctLow)
    $delta01    = Format-Delta -Current ([double]$current.ZeroOnePctLow) -Previous ([double]$previous.ZeroOnePctLow)
    $deltaStd   = Format-Delta -Current ([double]$current.StdDevMs) -Previous ([double]$previous.StdDevMs) -Unit ' ms' -LowerIsBetter $true
    $deltaStut  = Format-Delta -Current ([double]$current.StutterPct) -Previous ([double]$previous.StutterPct) -Unit ' %' -LowerIsBetter $true

    $curTime = Format-CapTimeShort $current.CaptureTime
    $prevTime = Format-CapTimeShort $previous.CaptureTime

    $modeChange = ''
    if ($current.PresentMode -ne $previous.PresentMode) {
        $modeChange = "`n`nPresent Mode geaendert: $($previous.PresentMode) -> $($current.PresentMode)"
    }

    $msg = @"
Vergleich aktuelle vs. vorherige Messung

$prevTime  ->  $curTime

   AVG FPS:     $($previous.AvgFps) -> $($current.AvgFps)   $($deltaAvg.Text)
   1% Low:      $($previous.OnePctLow) -> $($current.OnePctLow)   $($delta1.Text)
   0.1% Low:    $($previous.ZeroOnePctLow) -> $($current.ZeroOnePctLow)   $($delta01.Text)
   StdDev:      $($previous.StdDevMs) -> $($current.StdDevMs) ms   $($deltaStd.Text)
   Stutter:     $($previous.StutterPct) -> $($current.StutterPct) %   $($deltaStut.Text)$modeChange

Tipp: gruene Deltas = Verbesserung, rote = Verschlechterung
"@
    [System.Windows.MessageBox]::Show($msg, 'Capture-Vergleich', 'OK', 'Information') | Out-Null
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
        $ctrls.lblCapLastInfo.Text = 'History geloescht.'
        $ctrls.lblCapLastInfo.Foreground = '#9ca3af'
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
        try { $freshResult = Analyze-CaptureCSV -CsvPath $lastEntry.CsvPath } catch {}
    }
    $displayResult = if ($freshResult -and -not $freshResult.Error) { $freshResult } else { $lastEntry }
    $Global:CaptureState.LastResult = $displayResult
    Show-CapResult $displayResult
}

# Version im Header dynamisch (aus $Global:Suite.Version statt hardcoded)
$ctrls.lblVersion.Text = "v$($Global:Suite.Version)"
$window.Title = "PUBG Performance Suite v$($Global:Suite.Version)"

# Admin-Badge initial setzen
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    $ctrls.lblAdmin.Text = 'Admin: JA'
    $ctrls.adminBadge.Background = '#16a34a'
} else {
    $ctrls.lblAdmin.Text = 'Admin: NEIN'
    $ctrls.adminBadge.Background = '#dc2626'
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

# Cleanup beim Schliessen - Timer stoppen, ggf. laufenden PresentMon killen
$window.Add_Closing({
    try {
        if ($Global:CaptureState -and $Global:CaptureState.IsRunning) {
            Write-SuiteLog "Window-Close: stoppe laufende Capture" 'INFO'
            Cleanup-CapState
        }
    } catch {}
})

# Show
$window.ShowDialog() | Out-Null
