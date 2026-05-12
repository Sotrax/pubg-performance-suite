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
    Version    = '0.9.0-beta'
    StateDir   = "$env:LOCALAPPDATA\PUBGSuite"
    StateFile  = "$env:LOCALAPPDATA\PUBGSuite\state.json"
    ConfigFile = "$env:LOCALAPPDATA\PUBGSuite\config.json"
    HistoryFile= "$env:LOCALAPPDATA\PUBGSuite\history.json"
    LogDir     = "$env:LOCALAPPDATA\PUBGSuite\logs"
    BackupDir  = "$env:LOCALAPPDATA\PUBGSuite\backups"
    MonitorIDs = "$env:LOCALAPPDATA\PUBGSuite\disabled-monitors.txt"
    NPIStamp   = "$env:LOCALAPPDATA\PUBGDiag\npi-applied.stamp"
    DiagScript = "$env:USERPROFILE\Desktop\PUBG-Diagnose-v6.ps1"
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
    foreach ($d in $Global:Suite.StateDir, $Global:Suite.LogDir, $Global:Suite.BackupDir) {
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

function Get-HistoryEntries {
    if (Test-Path $Global:Suite.HistoryFile) {
        try { return @(Get-Content $Global:Suite.HistoryFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return @() }
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
        $entries | ConvertTo-Json -Depth 8 | Set-Content -Path $Global:Suite.HistoryFile -Encoding UTF8
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

    # HVCI
    try {
        $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
        $hvci = ($dg.SecurityServicesRunning -contains 2)
        $s['HVCI'] = if ($hvci) { @{ Value='AN'; Status='BAD' } } else { @{ Value='AUS'; Status='OK' } }
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

    # Engine.ini Tweaks
    $eng = "$env:LOCALAPPDATA\TslGame\Saved\Config\WindowsNoEditor\Engine.ini"
    if (Test-Path $eng) {
        $c = Get-Content $eng -Raw
        $hasSharpen = $c -match 'r\.Tonemapper\.Sharpen\s*=\s*0\.7'
        $hasStreaming = $c -match 'r\.Streaming\.PoolSize\s*=\s*4096'
        if ($hasSharpen -and $hasStreaming) {
            $s['Engine.ini'] = @{ Value='Tweaks drin'; Status='OK' }
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
    if (-not (Test-Path $Path)) { return $false }
    $bak = "$Path.bak_$timestamp"
    if (-not (Test-Path $bak)) { Copy-Item $Path $bak -Force }
    $content = Get-Content $Path -Raw
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
    Set-Content -Path $Path -Value $content -NoNewline
    return $true
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
        Id='engineini'; Cat='PUBG'; Name='Engine.ini Tweaks (Sharpen + Streaming + Pacing)'; Admin=$false
        Desc='Spotting-Buff + bessere 1%-Lows. BattlEye-safe'; Impact='KEIN'; ImpactDetail=''
        Changes = @(
            'Datei: %LOCALAPPDATA%\TslGame\Saved\Config\WindowsNoEditor\Engine.ini',
            'Backup vor Aenderung als .bak_<timestamp>',
            '[SystemSettings] r.Tonemapper.Sharpen=0.7  (Spotting auf Distanz)',
            '[SystemSettings] r.GTSyncType=1            (glattere Frametimes)',
            '[SystemSettings] r.OneFrameThreadLag=0     (Frame-Pacing)',
            '[SystemSettings] r.FinishCurrentFrame=0    (Frame-Pacing)',
            '[/Script/Engine.RendererSettings] r.Streaming.PoolSize=4096',
            '[/Script/Engine.RendererSettings] r.Streaming.HLODStrategy=2',
            '[/Script/Engine.RendererSettings] r.Streaming.FramesForFullUpdate=1'
        )
        StatusFn = {
            $eng = Get-PUBGEnginePath
            if (-not (Test-Path $eng)) { return 'SKIP' }
            $c = Get-Content $eng -Raw
            $hasSharpen = $c -match 'r\.Tonemapper\.Sharpen\s*=\s*0\.7'
            $hasStreaming = $c -match 'r\.Streaming\.PoolSize\s*=\s*4096'
            $hasGTSync = $c -match 'r\.GTSyncType\s*=\s*1'
            if ($hasSharpen -and $hasStreaming -and $hasGTSync) { 'OK' } else { 'WARN' }
        }
        SnapshotFn = {
            $eng = Get-PUBGEnginePath
            if (Test-Path $eng) {
                $bak = Copy-FileToBackup -SourcePath $eng
                return @{ BackupPath = $bak; OriginalPath = $eng }
            }
            return $null
        }
        ApplyFn = {
            try {
                $eng = Get-PUBGEnginePath
                if (-not (Test-Path $eng)) { return $false }
                $tweaks = @{
                    'SystemSettings' = @{
                        'r.Tonemapper.Sharpen' = '0.7'
                        'r.OneFrameThreadLag' = '0'
                        'r.FinishCurrentFrame' = '0'
                        'r.GTSyncType' = '1'
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
        Id='hvci'; Cat='System'; Name='Memory Integrity (HVCI): AUS'; Admin=$true
        Desc='5-8% FPS in CPU-bound Games. Erfordert Reboot'; Impact='MITTEL'
        ImpactDetail='Kernel-Schutz gegen unsignierte Treiber faellt weg - bei Solo-Gaming akzeptabel'
        Changes = @(
            'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity',
            'Enabled = 0 (DWord)',
            'WICHTIG: greift erst nach REBOOT'
        )
        StatusFn = {
            try {
                $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
                if ($dg.SecurityServicesRunning -contains 2) { 'BAD' } else { 'OK' }
            } catch { 'SKIP' }
        }
        SnapshotFn = { Get-RegistrySnapshot -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled' }
        ApplyFn = {
            try {
                $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
                if (-not (Test-Path $key)) { New-Item $key -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty $key -Name 'Enabled' -Value 0 -Type DWord -ErrorAction Stop
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
            if ($r -le 10 -and ($n -eq -1 -or $n -eq 0xFFFFFFFF -or $n -eq [int32]::MaxValue)) { 'OK' } else { 'WARN' }
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
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $target = Split-Path $Global:Suite.Tools.MMT -Parent
    try {
        if (-not (Test-Path $target)) { New-Item -Path $target -ItemType Directory -Force -ErrorAction Stop | Out-Null }
    } catch {
        $target = Join-Path $env:USERPROFILE 'Tools\MultiMonitorTool'
        if (-not (Test-Path $target)) { New-Item -Path $target -ItemType Directory -Force | Out-Null }
    }
    $zip = Join-Path $env:TEMP 'mmt.zip'
    & $LogCallback "  Lade MultiMonitorTool von NirSoft..."
    Invoke-WebRequest -Uri 'https://www.nirsoft.net/utils/multimonitortool-x64.zip' -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $target -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    $exe = Join-Path $target 'MultiMonitorTool.exe'
    & $LogCallback "  Installiert: $exe"
    return $exe
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
        $rtss = Get-Process -Name 'RTSS','RTSSHooksLoader64' -ErrorAction SilentlyContinue
        if ($rtss) {
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
            $p = Get-Process -Name $a -ErrorAction SilentlyContinue
            if ($p) {
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
        <Border Grid.Row="0" Background="#1a1d23" BorderBrush="#2d3139" BorderThickness="0,0,0,1" Padding="20,12">
            <Grid>
                <StackPanel HorizontalAlignment="Left">
                    <TextBlock Text="PUBG PERFORMANCE SUITE" FontSize="18" FontWeight="Bold" Foreground="#60a5fa"/>
                    <TextBlock x:Name="lblVersion" Text="v1.0.0-PoC" FontSize="11" Foreground="#6b7280"/>
                </StackPanel>
                <StackPanel HorizontalAlignment="Right" Orientation="Horizontal">
                    <Border x:Name="adminBadge" Background="#374151" CornerRadius="3" Padding="8,3" VerticalAlignment="Center" Margin="0,0,8,0">
                        <TextBlock x:Name="lblAdmin" Text="Admin: ?" Foreground="#e5e7eb" FontSize="10" FontWeight="SemiBold"/>
                    </Border>
                    <TextBlock x:Name="lblTopStatus" Text="" Foreground="#9ca3af" VerticalAlignment="Center" Margin="0,0,12,0"/>
                    <Button x:Name="btnRefresh" Content="Refresh" Width="100"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Tabs -->
        <TabControl Grid.Row="1" Background="#0f1115" BorderThickness="0" Padding="0">
            <!-- TAB 1: DASHBOARD -->
            <TabItem Header="Dashboard">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Background="#0f1115">
                    <StackPanel Margin="20">
                        <TextBlock Text="Live Status" FontSize="14" FontWeight="Bold" Foreground="#93c5fd" Margin="0,0,0,10"/>
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
                                            <TextBlock Text="{Binding Value}" Foreground="{Binding TextColor}" FontSize="14" FontWeight="SemiBold" Margin="0,4,0,0"/>
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
                        <Border Background="#1a1d23" Padding="14" CornerRadius="4">
                            <TextBlock x:Name="lblRecommendations" Text="Klick auf 'Run Diagnose' im naechsten Tab fuer detaillierte Analyse." Foreground="#e5e7eb" TextWrapping="Wrap"/>
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
                        <CheckBox x:Name="cbBackground" Content="Hintergrund-Apps schliessen (Chrome, Discord, Spotify, ...)" Foreground="#e5e7eb" Margin="0,4" IsChecked="True"/>
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
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                        <Button x:Name="btnApplySelected" Content="Apply Selected" Style="{StaticResource SuccessButton}" Width="160" Height="32" Margin="0,0,8,0"/>
                        <Button x:Name="btnApplyAll" Content="Apply All (auto-Status WARN/BAD)" Width="240" Height="32" Margin="0,0,8,0"/>
                        <Button x:Name="btnRefreshTweaks" Content="Refresh" Width="100" Height="32" Margin="0,0,8,0"/>
                        <Button x:Name="btnSelectAll" Content="Select All" Width="100" Height="32" Margin="0,0,8,0"/>
                        <Button x:Name="btnSelectNone" Content="Clear" Width="80" Height="32"/>
                    </StackPanel>
                    <TextBlock Grid.Row="1" x:Name="lblTweakInfo" Text="" Foreground="#9ca3af" FontSize="11" Margin="0,0,0,10"/>
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
foreach ($name in @('lblVersion','lblAdmin','adminBadge','lblTopStatus','btnRefresh','statusItems','lblRecommendations','btnStartGameMode','btnExitGameMode',
    'btnApplySelected','btnApplyAll','btnRefreshTweaks','btnSelectAll','btnSelectNone','lblTweakInfo','tweakContainer',
    'lblDetectedHw','monitorList','btnDetectMonitors','btnAutoPattern',
    'btnOpenLogs','btnOpenBackups','btnClearHistory','lblHistoryStat',
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

    # Recommendation logic
    $recos = @()
    if ($live['HVCI'].Status -ne 'OK') { $recos += 'HVCI ist AN - Memory Integrity deaktivieren (groesster FPS-Hebel)' }
    if ($live['Energieplan'].Status -ne 'OK') { $recos += 'Energieplan: auf Hoechstleistung wechseln' }
    if ($live['GameDVR'].Status -ne 'OK') { $recos += 'Xbox Game DVR: AUSSCHALTEN' }
    if ($live['RTSS'].Status -ne 'OK') { $recos += 'RTSS laeuft - vor PUBG-Start killen (sonst Mode 5)' }
    if ($live['Monitore'].Status -ne 'OK') { $recos += "Multi-Monitor aktiv - vor PUBG nur OLED aktivieren" }
    if ($live['Engine.ini'].Status -ne 'OK') { $recos += 'PUBG Engine.ini Tweaks fehlen - Diagnose laufen lassen + Auto-Fix' }
    if ($live['NV Profil'].Status -ne 'OK') { $recos += 'NVIDIA Profile noch nicht via NPI gesetzt' }

    if ($recos.Count -eq 0) {
        $ctrls.lblRecommendations.Text = "✓ Alle Live-Checks gruen. Setup ist auf einem guten Stand."
        $ctrls.lblRecommendations.Foreground = '#4ade80'
    } else {
        $ctrls.lblRecommendations.Text = "⚠ " + ($recos -join "`n⚠ ")
        $ctrls.lblRecommendations.Foreground = '#fbbf24'
    }

    # Top-Status
    $okCount = @($live.Values | Where-Object { $_.Status -eq 'OK' }).Count
    $totalCount = @($live.Values).Count
    $ctrls.lblTopStatus.Text = "$okCount / $totalCount OK"

    $ctrls.lblFooter.Text = "Status aktualisiert: $(Get-Date -Format 'HH:mm:ss')"
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
    if (-not (Test-Path $Global:Suite.DiagScript)) {
        Write-DiagLog "FEHLER: $($Global:Suite.DiagScript) nicht gefunden"
        Write-DiagLog "Bitte PUBG-Diagnose-v6.ps1 auf Desktop legen"
        return
    }
    Write-DiagLog "Starte v6-Diagnose in separatem Fenster (NonInteractive Mode)..."
    Write-DiagLog "Interaktive Fix-Phase wird uebersprungen - Tweaks werden im Tab 'Tweaks' verwaltet"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($Global:Suite.DiagScript)`" -NonInteractive"
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

$ctrls.lblPaths.Text = @"
StateDir:    $($Global:Suite.StateDir)
DiagScript:  $($Global:Suite.DiagScript)
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

function Update-TweaksTab {
    if (-not $ctrls.tweakContainer) { return }
    $ctrls.tweakContainer.Children.Clear()

    # Group manuell (Group-Object auf PSCustomObject geht, aber so haben wir definierte Reihenfolge)
    $catOrder = @('Windows','PUBG','System')
    $foundCats = $Global:Tweaks | ForEach-Object { $_.Cat } | Sort-Object -Unique
    $cats = @($catOrder | Where-Object { $_ -in $foundCats }) + @($foundCats | Where-Object { $_ -notin $catOrder })

    foreach ($catName in $cats) {
        $catTweaks = @($Global:Tweaks | Where-Object { $_.Cat -eq $catName })
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

    $total = $Global:Tweaks.Count
    $okCnt = 0; $needCnt = 0
    foreach ($t in $Global:Tweaks) {
        $st = & $t.StatusFn
        if ($st -eq 'OK') { $okCnt++ }
        elseif ($st -eq 'WARN' -or $st -eq 'BAD') { $needCnt++ }
    }
    $sel = @($Global:TweakSelection.GetEnumerator() | Where-Object { $_.Value }).Count
    $ctrls.lblTweakInfo.Text = "$okCnt von $total angewendet  |  $needCnt offen  |  $sel selektiert"
}

$ctrls.btnRefreshTweaks.Add_Click({ Update-TweaksTab; Update-StatusGrid })

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

$ctrls.btnApplySelected.Add_Click({
    $selectedIds = @($Global:TweakSelection.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key })
    if ($selectedIds.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Nichts ausgewaehlt. Erst Checkboxen setzen oder "Select All" benutzen.', 'Hinweis', 'OK', 'Information') | Out-Null
        return
    }
    $applied = 0; $failed = 0; $failedNames = @()
    foreach ($id in $selectedIds) {
        $tw = $Global:Tweaks | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if ($tw) {
            if (Invoke-TweakApply -Tweak $tw) { $applied++ } else { $failed++; $failedNames += $tw.Name }
        }
    }
    $msg = "$applied angewendet, $failed Fehler"
    if ($failedNames.Count -gt 0) { $msg += "`n`nFehler bei:`n" + ($failedNames -join "`n") + "`n`nDetails: Logs im Settings-Tab" }
    [System.Windows.MessageBox]::Show($msg, 'Apply Selected', 'OK', 'Information') | Out-Null
    Update-TweaksTab; Update-StatusGrid
})

$ctrls.btnApplyAll.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show("Wendet alle Tweaks mit Status WARN/BAD an (alle Kategorien).`n`nFuer jeden Tweak wird ein Snapshot vor Apply gespeichert (Revert spaeter moeglich).`n`nWeiter?", 'Apply All - Bestaetigung', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }
    $applied = 0; $failed = 0; $failedNames = @()
    foreach ($t in $Global:Tweaks) {
        $st = & $t.StatusFn
        if ($st -eq 'WARN' -or $st -eq 'BAD') {
            if (Invoke-TweakApply -Tweak $t) { $applied++ } else { $failed++; $failedNames += $t.Name }
        }
    }
    $msg = "$applied angewendet, $failed Fehler"
    if ($failedNames.Count -gt 0) { $msg += "`n`nFehler bei:`n" + ($failedNames -join "`n") }
    [System.Windows.MessageBox]::Show($msg, 'Apply All', 'OK', 'Information') | Out-Null
    Update-TweaksTab; Update-StatusGrid
})

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

# Initial Status
Update-StatusGrid
Update-TweaksTab

# Show
$window.ShowDialog() | Out-Null
