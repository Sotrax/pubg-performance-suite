# =============================================================================
#  PUBGTweakRegistry.psm1  -  Zentrale Registry aller System-/PUBG-Tweaks
# =============================================================================
#
#  Single Source of Truth fuer jeden ausfuehrbaren Tweak. BEIDE Komponenten
#  nutzen dieses Modul:
#    - PUBG-Suite.ps1        rendert den Tweaks-Tab daraus, ruft Apply/Revert
#    - PUBG-Diagnose-v7.ps1  iteriert die Tweaks und ruft pro Tweak Check auf
#
#  Damit ist die Architektur-Regel mechanisch erzwungen: jeder Diagnose-Befund
#  mit Status TWEAK hat hier einen Tweak mit ausfuehrbarer Apply-Funktion.
#
#  Geladen via  Import-Module .\config\PUBGTweakRegistry.psm1
#  Exportiert ausschliesslich:  Get-PUBGTweakRegistry
#
#  Das Modul ist SELBSTSTAENDIG - alle Helfer (Registry-Snapshot, INI-Writer,
#  Datei-Backup, NPI) sind privat im Modul enthalten. Die Check/Apply/Revert-
#  Scriptbloecke bleiben an den Modul-Scope gebunden und sehen diese Helfer
#  auch dann, wenn sie von aussen (Suite/Diagnose) per & aufgerufen werden.
#
#  ---------------------------------------------------------------------------
#  Tweak-Struktur (jedes Element von Get-PUBGTweakRegistry):
#    Id            [string]  stabiler Bezeichner (= Key in history.json)
#    Category      [string]  Windows | GPU | Network | PUBG
#    Label         [string]  Anzeigename
#    Description   [string]  Kurzbeschreibung
#    Impact        [string]  KEIN | GERING | MITTEL | HOCH  (Alltags-Impact)
#    ImpactDetail  [string]  Erlaeuterung des Impacts
#    RequiresAdmin [bool]    Apply braucht Elevation
#    Changes       [string[]] konkrete Aenderungen (UI-Anzeige)
#    Check         [scriptblock] -> @{ Status; CurrentValue; Detail }
#                  Status: 'OK' | 'TWEAK' | 'SKIP'
#    Apply         [scriptblock] -> @{ Success; Message; Snapshot }
#    Revert        [scriptblock] param($Snapshot) -> @{ Success; Message }
# =============================================================================

Set-StrictMode -Off

# ---------------------------------------------------------------------------
#  Pfad-Konstanten (Modul-Scope). Bewusst identisch zur Suite, damit Backups
#  und der NPI-Stamp an einem Ort liegen. GetFolderPath ist null-sicher (auf
#  Windows = %LOCALAPPDATA%, auf Nicht-Windows-Dev-Boxen ein Fallback-Pfad),
#  damit das Modul auch fuer reine Parse-Checks ladbar bleibt.
# ---------------------------------------------------------------------------
$script:RegLocalAppData = $env:LOCALAPPDATA
if ([string]::IsNullOrWhiteSpace($script:RegLocalAppData)) {
    $script:RegLocalAppData = [Environment]::GetFolderPath('LocalApplicationData')
}
$script:RegBackupDir  = Join-Path $script:RegLocalAppData 'PUBGSuite\backups'
$script:RegLogDir     = Join-Path $script:RegLocalAppData 'PUBGSuite\logs'
$script:NpiStampPath  = Join-Path $script:RegLocalAppData 'PUBGDiag\npi-applied.stamp'
$script:GSyncStampPath = Join-Path $script:RegLocalAppData 'PUBGDiag\gsync-applied.stamp'
$script:NpiDefaultDir = 'C:\Tools\nvidiaProfileInspector'

# NVIDIA PUBG-Profil: Profilname + die Treiber-Settings. Modul-Scope, damit
# Apply (Invoke-NPIPubgProfile) und Revert (Revert-NPIPubgProfile) GENAU dieselbe
# Liste nutzen - eine einzige Quelle fuer Setzen und Zuruecksetzen.
#
# Setting-IDs + Werte gegen die offizielle nvidiaProfileInspector-Referenz
# verifiziert (nvidiaProfileInspector/CustomSettingNames.xml, Orbmu2k):
#   0x10835002 = Frame Rate Limiter V3   (Wert = FPS als DWORD, z.B. 237 = 0xED)
#   0x00A879CF = Vertical Sync           (Off=0x08416747, On=0x47814940)
#   0x10835000 = Ultra Low Latency       (Bool: 0=Off, 1=On)
#
# Aenderungen ggue. <=0.26.0-beta (G-SYNC-101-konform, doppelt recherchiert):
#  - Vertical Sync: war 0x00000000 (KEIN gueltiger Wert fuer dieses Setting!) ->
#    0x47814940 (On). Bei aktivem G-Sync + FPS-Cap unter Refresh fuegt V-Sync=On
#    KEINE Latenz hinzu, dient nur als Tearing-Fallback (Blur Busters G-SYNC 101).
#  - Ultra Low Latency: war 1 (On) -> 0 (Off). PUBG hat keinen Reflex; der
#    manuelle FPS-Cap ist wirksamer als ULL. ULL Ultra setzt zudem einen eigenen
#    Auto-Cap (~224 FPS @240Hz), der den 237er-Cap unterbieten wuerde, und kann
#    in CPU-bound Szenen (PUBG) Latenz sogar erhoehen.
#  - CPL-State 0x0005F543 entfernt (mit ULL=Off gegenstandslos).
#
# Dynamic='FpsCap': Val wird erst beim Apply aus Get-OptimalFpsCap (Monitor-Hz
# minus 3) berechnet - eine einzige Quelle fuer den Cap-Wert, kein Hardcoding.
$script:NpiPubgProfileName = "PLAYERUNKNOWN'S BATTLEGROUNDS"
$script:NpiPubgSettings = @(
    @{ Id='0x1033DCD2'; Val='0x00000001'; Desc='Power Management Mode = Prefer Max Performance' }
    @{ Id='0x00A879CF'; Val='0x47814940'; Desc='Vertical Sync = ON (G-SYNC-101: Tearing-Fallback, keine Latenz bei Cap unter Refresh)' }
    @{ Id='0x00CE0E32'; Val='0x00000000'; Desc='Texture Filtering Quality = High Performance' }
    @{ Id='0x20FF7493'; Val='0x00000001'; Desc='Threaded Optimization = ON' }
    @{ Id='0x10835000'; Val='0x00000000'; Desc='Ultra Low Latency = Off (manueller FPS-Cap ist wirksamer)' }
    @{ Id='0x10835002'; Val=$null; Dynamic='FpsCap'; Desc='Frame Rate Limiter V3 = Monitor-Hz minus 3' }
    @{ Id='0x00D55F7D'; Val='0x00000000'; Desc='Antialiasing Mode = Application Controlled' }
    @{ Id='0x101E61A9'; Val='0x00000002'; Desc='Anisotropic Filtering = Use Global' }
)

# G-Sync-Settings (eigener Tweak). IDs + Werte gegen die nvidiaProfileInspector-
# Referenz (CustomSettingNames.xml) verifiziert:
#   0x1094F157 GSYNC Global Feature    (0=Off, 1=On)
#   0x1094F1F7 GSYNC Global Mode       (0=Off, 1=Fullscreen only, 2=FS+Windowed)
#   0x1194F158 GSYNC Application Mode  (0=Off, 1=Fullscreen only, 2=FS+Windowed)
#   0x10A879CF GSYNC Application State (0=Allow, 1=Force Off, 2=Disallow)
# PUBG laeuft im Exklusiv-Vollbild -> 'Fullscreen only' genuegt und ist die
# latenzaermste Wahl.
#  - Base-Settings gehen ins globale Treiberprofil ('Base Profile') = der
#    Master-G-Sync-Schalter der NVIDIA-Systemsteuerung.
#  - App-Settings gehen ins PUBG-Profil.
# Greift nur, wenn im Monitor-OSD VRR/Adaptive-Sync aktiv ist.
$script:NpiGSyncBaseSettings = @(
    @{ Id='0x1094F157'; Val='0x00000001'; Desc='G-SYNC Global Feature = On' }
    @{ Id='0x1094F1F7'; Val='0x00000001'; Desc='G-SYNC Global Mode = Fullscreen only' }
)
$script:NpiGSyncAppSettings = @(
    @{ Id='0x1194F158'; Val='0x00000001'; Desc='G-SYNC Application Mode = Fullscreen only' }
    @{ Id='0x10A879CF'; Val='0x00000000'; Desc='G-SYNC Application State = Allow' }
)
$script:NpiBaseProfileName = 'Base Profile'   # globales Treiberprofil in der .nip

# ===========================================================================
#  PRIVATE HELFER
# ===========================================================================

function Write-RegLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        if (-not (Test-Path $script:RegLogDir)) {
            New-Item -Path $script:RegLogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        $logFile = Join-Path $script:RegLogDir "$(Get-Date -Format 'yyyy-MM-dd').log"
        "[$(Get-Date -Format 'HH:mm:ss.fff')] [$Level] [Registry] $Message" |
            Add-Content -Path $logFile -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

function Get-RegistrySnapshot {
    param([string]$Path, [string]$Name)
    try {
        if (-not (Test-Path $Path)) {
            return @{ Path=$Path; Name=$Name; HadKey=$false; HadValue=$false; OldValue=$null; ValueKind='None' }
        }
        $key  = Get-Item -Path $Path -ErrorAction Stop
        $val  = $key.GetValue($Name, $null)
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
            if (Test-Path $Snap.Path) {
                Remove-ItemProperty -Path $Snap.Path -Name $Snap.Name -ErrorAction SilentlyContinue
            }
            return $true
        }
        $type = switch ($Snap.ValueKind) {
            'DWord'        { 'DWord' }
            'QWord'        { 'QWord' }
            'String'       { 'String' }
            'ExpandString' { 'ExpandString' }
            'MultiString'  { 'MultiString' }
            'Binary'       { 'Binary' }
            default        { 'String' }
        }
        if (-not (Test-Path $Snap.Path)) { New-Item -Path $Snap.Path -Force -ErrorAction Stop | Out-Null }
        Set-ItemProperty -Path $Snap.Path -Name $Snap.Name -Value $Snap.OldValue -Type $type -ErrorAction Stop
        return $true
    } catch {
        Write-RegLog "Restore-RegistrySnapshot Fehler: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

# Liest die aktuell aktive System-Timer-Resolution in Millisekunden via ntdll
# (NtQueryTimerResolution). Gibt $null zurueck, wenn die Messung nicht moeglich
# ist. Der Typ wird einmalig (prozessweit) per Add-Type angelegt.
function Get-CurrentTimerResolutionMs {
    try {
        if (-not ('PubgTimerNative' -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PubgTimerNative {
    [DllImport("ntdll.dll", SetLastError=true)]
    public static extern int NtQueryTimerResolution(out uint Minimum, out uint Maximum, out uint Current);
}
'@
        }
        $mn = 0; $mx = 0; $cu = 0
        $st = [PubgTimerNative]::NtQueryTimerResolution([ref]$mn, [ref]$mx, [ref]$cu)
        if ($st -ne 0 -or $cu -le 0) { return $null }
        return [math]::Round($cu / 10000.0, 2)
    } catch { return $null }
}

function Copy-FileToBackup {
    param([string]$SourcePath)
    if (-not (Test-Path $SourcePath)) { return $null }
    try {
        if (-not (Test-Path $script:RegBackupDir)) {
            New-Item -Path $script:RegBackupDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        $name = [System.IO.Path]::GetFileName($SourcePath)
        $ts   = Get-Date -Format 'yyyy-MM-dd_HHmmss_fff'
        $dest = Join-Path $script:RegBackupDir "$name.bak_$ts"
        Copy-Item -Path $SourcePath -Destination $dest -Force -ErrorAction Stop
        return $dest
    } catch {
        Write-RegLog "Copy-FileToBackup Fehler: $($_.Exception.Message)" 'WARN'
        return $null
    }
}

function Restore-FileFromBackup {
    param([string]$BackupPath, [string]$TargetPath)
    if (-not $BackupPath -or -not (Test-Path $BackupPath)) { return $false }
    try {
        # ReadOnly auf dem Ziel entfernen, sonst schlaegt das Ueberschreiben fehl
        if (Test-Path $TargetPath) {
            $f = Get-Item $TargetPath -Force
            if (($f.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
                $f.Attributes = $f.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
            }
        }
        Copy-Item -Path $BackupPath -Destination $TargetPath -Force -ErrorAction Stop
        return $true
    } catch {
        Write-RegLog "Restore-FileFromBackup Fehler: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

# INI-Writer - identisch zur Suite-Logik. Schreibt nie $null, legt Sektion an
# falls fehlend, behandelt ReadOnly-Dateien (kurz writable, danach Flag zurueck).
function Update-IniValue {
    param([string]$Path, [string]$Section, [string]$Key, [string]$Value)
    if (-not (Test-Path $Path)) {
        Write-RegLog "Update-IniValue: Datei nicht gefunden: $Path" 'WARN'
        return $false
    }
    try {
        $content = Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-RegLog "Update-IniValue: Read-Fehler $($_.Exception.Message)" 'ERROR'
        return $false
    }
    if ($null -eq $content) {
        Write-RegLog "Update-IniValue: Datei leer/null: $Path - kein Write" 'WARN'
        return $false
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
    if ([string]::IsNullOrWhiteSpace($content) -or $content.Length -lt 5) {
        Write-RegLog "Update-IniValue: Berechnetes Content zu klein/leer - kein Write" 'ERROR'
        return $false
    }
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
        if ($wasReadOnly) {
            try {
                $fi2 = Get-Item $Path -Force
                $fi2.Attributes = $fi2.Attributes -bor [System.IO.FileAttributes]::ReadOnly
            } catch {}
        }
        return $true
    } catch {
        Write-RegLog "Update-IniValue: Write-Fehler $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Get-PUBGEnginePath   { "$env:LOCALAPPDATA\TslGame\Saved\Config\WindowsNoEditor\Engine.ini" }
function Get-PUBGGameUserPath { "$env:LOCALAPPDATA\TslGame\Saved\Config\WindowsNoEditor\GameUserSettings.ini" }

function Get-PrimaryMonitorHz {
    try {
        $hz = (Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
            Where-Object { $_.CurrentRefreshRate -gt 0 } |
            Sort-Object -Property CurrentRefreshRate -Descending |
            Select-Object -First 1).CurrentRefreshRate
        if ($hz -and $hz -gt 0) { return [int]$hz }
    } catch {}
    return 240
}

function Get-OptimalFpsCap { (Get-PrimaryMonitorHz) - 3 }

function Get-NPIPath {
    $candidates = @(
        "$script:NpiDefaultDir\nvidiaProfileInspector.exe",
        "$env:USERPROFILE\Tools\nvidiaProfileInspector\nvidiaProfileInspector.exe",
        "$env:USERPROFILE\Downloads\nvidiaProfileInspector\nvidiaProfileInspector.exe",
        "$env:USERPROFILE\Downloads\nvidiaProfileInspector.exe"
    )
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    try {
        $found = (& where.exe nvidiaProfileInspector.exe 2>$null) | Select-Object -First 1
        if ($found -and (Test-Path $found)) { return $found }
    } catch {}
    return $null
}

function Install-NPIFromGitHub {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Write-RegLog 'NPI-Install: hole Release-Info von GitHub...'
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Orbmu2k/nvidiaProfileInspector/releases/latest' `
            -Headers @{ 'User-Agent' = 'PUBG-Suite' } -ErrorAction Stop
        $zipAsset = $release.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
        if (-not $zipAsset) { throw 'Kein ZIP-Asset im NPI-Release gefunden' }

        $target = $script:NpiDefaultDir
        try {
            if (-not (Test-Path $target)) { New-Item -Path $target -ItemType Directory -Force -ErrorAction Stop | Out-Null }
        } catch {
            $target = Join-Path $env:USERPROFILE 'Tools\nvidiaProfileInspector'
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
            Write-RegLog "NPI installiert: $npiExe ($($release.tag_name))"
            return $npiExe
        }
        return $null
    } catch {
        Write-RegLog "NPI-Install Fehler: $($_.Exception.Message)" 'ERROR'
        return $null
    }
}

# ===========================================================================
#  NVIDIA-Treibereinstellungen via .nip-Import
# ---------------------------------------------------------------------------
# Das aktuelle nvidiaProfileInspector kennt KEIN -setProfileSetting (das war
# das alte, separate "nVidia Inspector"). Der dokumentierte und einzig
# funktionierende CLI-Weg ist der Import einer .nip-Profildatei via
# -silentImport; der Import schreibt via NVAPI DRS_SaveSettings in die
# Treiber-Datenbank (im NVPI-Quellcode verifiziert: DrsImportService).
#
# WICHTIG: Der Import ERSETZT die Settings eines Profils - Settings, die nicht
# in der .nip stehen, werden geloescht. Deshalb Read-Modify-Write: zuerst den
# Ist-Zustand via -exportCustomized exportieren, die gewuenschten Werte
# einmischen, dann importieren. So gehen keine fremden Treibereinstellungen
# (auch nicht im globalen 'Base Profile') verloren.
# ===========================================================================

# Loest den konkreten Hex-Wert fuer ein NPI-Setting auf. Bei Dynamic='FpsCap'
# wird der Wert aus Get-OptimalFpsCap (Monitor-Hz minus 3) berechnet und auf
# den von Frame Rate Limiter V3 unterstuetzten Bereich (20..1000 FPS) geklemmt.
function Resolve-NpiSettingValue {
    param($Setting)
    if ($Setting.Dynamic -eq 'FpsCap') {
        $cap = [int](Get-OptimalFpsCap)
        if ($cap -lt 20)   { $cap = 20 }
        if ($cap -gt 1000) { $cap = 1000 }
        return ('0x{0:X8}' -f $cap)
    }
    return $Setting.Val
}

# Hex-String ('0x10835002' / '0xED') -> dezimaler uint (.nip nutzt Dezimalwerte).
function ConvertFrom-NpiHex {
    param([string]$Hex)
    return [Convert]::ToUInt32(($Hex -replace '^0x',''), 16)
}

# Exportiert alle kundenspezifischen Treiberprofile via -exportCustomized und
# gibt den Pfad der erzeugten .nip zurueck ($null bei Fehler). NVPI beendet
# sich nach dem Export selbst (im Quellcode verifiziert).
function Export-NpiProfiles {
    param([string]$NpiPath)
    if (-not $NpiPath -or -not (Test-Path $NpiPath)) { return $null }
    $dir = Split-Path $NpiPath -Parent
    $before = @(Get-ChildItem -Path $dir -Filter 'CustomProfiles_*.nip' -ErrorAction SilentlyContinue | ForEach-Object FullName)
    try {
        $null = Start-Process -FilePath $NpiPath -ArgumentList '-exportCustomized' -WorkingDirectory $dir -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
    } catch {
        Write-RegLog "NPI Export Fehler: $($_.Exception.Message)" 'ERROR'
        return $null
    }
    $after = @(Get-ChildItem -Path $dir -Filter 'CustomProfiles_*.nip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    $new = $after | Where-Object { $_.FullName -notin $before } | Select-Object -Last 1
    if ($new) { return $new.FullName }
    if ($after) { return ($after | Select-Object -Last 1).FullName }
    return $null
}

# Parst eine .nip in eine Hashtable: ProfileName -> @{ Exe=@(...); Settings=@{
# <SettingID-dezimal-als-String> = @{ Value; Type; Name } } }.
function Read-NipProfiles {
    param([string]$Path)
    $result = @{}
    if (-not $Path -or -not (Test-Path $Path)) { return $result }
    try {
        $doc = New-Object System.Xml.XmlDocument
        $doc.Load($Path)
    } catch {
        Write-RegLog "Read-NipProfiles Parse-Fehler: $($_.Exception.Message)" 'WARN'
        return $result
    }
    if (-not $doc.ArrayOfProfile) { return $result }
    foreach ($p in @($doc.ArrayOfProfile.Profile)) {
        if (-not $p) { continue }
        $name = [string]$p.ProfileName
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $exes = @()
        if ($p.Executeables -and $p.Executeables.string) {
            $exes = @($p.Executeables.string | ForEach-Object { [string]$_ })
        }
        $settings = @{}
        if ($p.Settings -and $p.Settings.ProfileSetting) {
            foreach ($s in @($p.Settings.ProfileSetting)) {
                if ($null -eq $s.SettingID) { continue }
                $sid = [string]$s.SettingID
                $stype = if ($s.ValueType) { [string]$s.ValueType } else { 'Dword' }
                $sname = if ($s.SettingNameInfo) { [string]$s.SettingNameInfo } else { '' }
                $settings[$sid] = @{ Value=[string]$s.SettingValue; Type=$stype; Name=$sname }
            }
        }
        $result[$name] = @{ Exe=$exes; Settings=$settings }
    }
    return $result
}

# Schreibt eine Profil-Hashtable als .nip (UTF-16, wie NVPI sie selbst erzeugt).
function Write-NipProfiles {
    param([string]$Path, [hashtable]$Profiles)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-16"?>')
    [void]$sb.AppendLine('<ArrayOfProfile>')
    foreach ($name in $Profiles.Keys) {
        $pf = $Profiles[$name]
        [void]$sb.AppendLine('  <Profile>')
        [void]$sb.AppendLine('    <ProfileName>' + [System.Security.SecurityElement]::Escape([string]$name) + '</ProfileName>')
        if ($pf.Exe -and @($pf.Exe).Count -gt 0) {
            [void]$sb.AppendLine('    <Executeables>')
            foreach ($e in $pf.Exe) { [void]$sb.AppendLine('      <string>' + [System.Security.SecurityElement]::Escape([string]$e) + '</string>') }
            [void]$sb.AppendLine('    </Executeables>')
        } else {
            [void]$sb.AppendLine('    <Executeables />')
        }
        [void]$sb.AppendLine('    <Settings>')
        foreach ($sid in $pf.Settings.Keys) {
            $s = $pf.Settings[$sid]
            $t = if ($s.Type) { [string]$s.Type } else { 'Dword' }
            [void]$sb.AppendLine('      <ProfileSetting>')
            if ($s.Name) { [void]$sb.AppendLine('        <SettingNameInfo>' + [System.Security.SecurityElement]::Escape([string]$s.Name) + '</SettingNameInfo>') }
            [void]$sb.AppendLine('        <SettingID>' + $sid + '</SettingID>')
            [void]$sb.AppendLine('        <SettingValue>' + [string]$s.Value + '</SettingValue>')
            [void]$sb.AppendLine('        <ValueType>' + $t + '</ValueType>')
            [void]$sb.AppendLine('      </ProfileSetting>')
        }
        [void]$sb.AppendLine('    </Settings>')
        [void]$sb.AppendLine('  </Profile>')
    }
    [void]$sb.AppendLine('</ArrayOfProfile>')
    Set-Content -Path $Path -Value $sb.ToString() -Encoding Unicode
}

# Kern: Read-Modify-Write fuer Treiberprofile.
# $Changes = @( @{ Profile='<Name>'; Exe='<exe>'|$null; Set=@{ '<hexId>'='<hexVal>' };
#                  Remove=@('<hexId>',...) } )
# Rueckgabe: @{ Success; Message; Backup }  (Backup = Pre-Change-Export-Pfad)
function Set-NpiProfileSettings {
    param([string]$NpiPath, [array]$Changes)
    if (-not $NpiPath -or -not (Test-Path $NpiPath)) {
        return @{ Success=$false; Message='NVIDIA Profile Inspector nicht gefunden'; Backup=$null }
    }
    $backup = Export-NpiProfiles -NpiPath $NpiPath
    if (-not $backup) {
        return @{ Success=$false; Message='NVPI-Export fehlgeschlagen (NVIDIA-Treiber? Adminrechte?) - kein sicherer Read-Modify-Write moeglich'; Backup=$null }
    }
    $current = Read-NipProfiles -Path $backup
    $out = @{}
    foreach ($ch in $Changes) {
        $pname = [string]$ch.Profile
        $existing = if ($current.ContainsKey($pname)) { $current[$pname] } else { $null }
        $settings = @{}
        if ($existing) { foreach ($k in $existing.Settings.Keys) { $settings[$k] = $existing.Settings[$k] } }
        $exe = if ($ch.Exe) { @($ch.Exe) } elseif ($existing) { $existing.Exe } else { @() }
        if ($ch.Set) {
            foreach ($hid in $ch.Set.Keys) {
                $idDec  = [string](ConvertFrom-NpiHex $hid)
                $valDec = [string](ConvertFrom-NpiHex $ch.Set[$hid])
                $settings[$idDec] = @{ Value=$valDec; Type='Dword'; Name='' }
            }
        }
        if ($ch.Remove) {
            foreach ($hid in $ch.Remove) {
                $idDec = [string](ConvertFrom-NpiHex $hid)
                if ($settings.ContainsKey($idDec)) { $settings.Remove($idDec) }
            }
        }
        $out[$pname] = @{ Exe=$exe; Settings=$settings }
    }
    $importPath = Join-Path $script:RegBackupDir ("npi-import_{0}.nip" -f (Get-Date -Format 'yyyy-MM-dd_HHmmss_fff'))
    try {
        if (-not (Test-Path $script:RegBackupDir)) { New-Item -Path $script:RegBackupDir -ItemType Directory -Force | Out-Null }
        Write-NipProfiles -Path $importPath -Profiles $out
    } catch {
        return @{ Success=$false; Message="Erzeugen der .nip fehlgeschlagen: $($_.Exception.Message)"; Backup=$backup }
    }
    try {
        $proc = Start-Process -FilePath $NpiPath -ArgumentList @('-silentImport', $importPath) -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
        $rc = $proc.ExitCode
    } catch {
        Write-RegLog "NPI Import Fehler: $($_.Exception.Message)" 'ERROR'
        return @{ Success=$false; Message="NVPI-Import fehlgeschlagen: $($_.Exception.Message)"; Backup=$backup }
    } finally {
        if (Test-Path $importPath) { Remove-Item $importPath -Force -ErrorAction SilentlyContinue }
    }
    Write-RegLog "NPI Import ausgefuehrt (ExitCode $rc), Pre-Change-Backup: $backup"
    return @{ Success=$true; Message='NVIDIA-Profil(e) via .nip importiert'; Backup=$backup }
}

# --- High-Level Apply/Revert (von den Tweaks aufgerufen) -------------------

function Invoke-NPIPubgProfile {
    param([string]$NpiPath)
    $setMap = @{}
    foreach ($s in $script:NpiPubgSettings) { $setMap[$s.Id] = (Resolve-NpiSettingValue -Setting $s) }
    $res = Set-NpiProfileSettings -NpiPath $NpiPath -Changes @(
        @{ Profile=$script:NpiPubgProfileName; Exe='TslGame.exe'; Set=$setMap }
    )
    if ($res.Success) {
        try {
            $sd = Split-Path $script:NpiStampPath -Parent
            if (-not (Test-Path $sd)) { New-Item -Path $sd -ItemType Directory -Force | Out-Null }
            Get-Date | Out-File $script:NpiStampPath -Force
        } catch {}
    }
    return $res
}

function Revert-NPIPubgProfile {
    param([string]$NpiPath)
    $ids = @($script:NpiPubgSettings | ForEach-Object { $_.Id })
    $res = Set-NpiProfileSettings -NpiPath $NpiPath -Changes @(
        @{ Profile=$script:NpiPubgProfileName; Exe='TslGame.exe'; Remove=$ids }
    )
    if ($res.Success -and (Test-Path $script:NpiStampPath)) {
        Remove-Item $script:NpiStampPath -Force -ErrorAction SilentlyContinue
    }
    return $res
}

function Invoke-NPIGSync {
    param([string]$NpiPath)
    $baseMap = @{}; foreach ($s in $script:NpiGSyncBaseSettings) { $baseMap[$s.Id] = $s.Val }
    $appMap  = @{}; foreach ($s in $script:NpiGSyncAppSettings)  { $appMap[$s.Id]  = $s.Val }
    $res = Set-NpiProfileSettings -NpiPath $NpiPath -Changes @(
        @{ Profile=$script:NpiBaseProfileName; Exe=$null; Set=$baseMap }
        @{ Profile=$script:NpiPubgProfileName; Exe='TslGame.exe'; Set=$appMap }
    )
    if ($res.Success) {
        try {
            $sd = Split-Path $script:GSyncStampPath -Parent
            if (-not (Test-Path $sd)) { New-Item -Path $sd -ItemType Directory -Force | Out-Null }
            Get-Date | Out-File $script:GSyncStampPath -Force
        } catch {}
    }
    return $res
}

function Revert-NPIGSync {
    param([string]$NpiPath)
    $baseIds = @($script:NpiGSyncBaseSettings | ForEach-Object { $_.Id })
    $appIds  = @($script:NpiGSyncAppSettings  | ForEach-Object { $_.Id })
    $res = Set-NpiProfileSettings -NpiPath $NpiPath -Changes @(
        @{ Profile=$script:NpiBaseProfileName; Exe=$null; Remove=$baseIds }
        @{ Profile=$script:NpiPubgProfileName; Exe='TslGame.exe'; Remove=$appIds }
    )
    if ($res.Success -and (Test-Path $script:GSyncStampPath)) {
        Remove-Item $script:GSyncStampPath -Force -ErrorAction SilentlyContinue
    }
    return $res
}

# ===========================================================================
#  TWEAK-REGISTRY
# ===========================================================================
$script:PUBGTweaks = @(

    # ---- Windows: Energieplan -------------------------------------------------
    [PSCustomObject]@{
        Id='energieplan'; Category='Windows'; Label='Energieplan: Hoechstleistung'
        Description='CPU haelt volle Frequenz - kein Down-Clocking unter Last'
        Impact='GERING'; ImpactDetail='~5W mehr Idle-Verbrauch'; RequiresAdmin=$false
        Changes=@(
            'powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c',
            'Aktiver Energieplan -> Windows-Standard-Hoechstleistung'
        )
        Check={
            $a = powercfg /getactivescheme 2>$null
            if ($a -match '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c|e9a42b02-d5df-448d-aa00-03f14749eb61') {
                @{ Status='OK'; CurrentValue='Hoechstleistung'; Detail='' }
            } else {
                @{ Status='TWEAK'; CurrentValue='nicht Hoechstleistung'
                   Detail='Energieplan auf Hoechstleistung setzen - verhindert CPU-Down-Clocking' }
            }
        }
        Apply={
            $snap = $null
            $a = powercfg /getactivescheme 2>$null
            if ($a -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                $snap = @{ PreGuid = $matches[1] }
            }
            try {
                powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    @{ Success=$true;  Message='Energieplan auf Hoechstleistung gesetzt'; Snapshot=$snap }
                } else {
                    @{ Success=$false; Message='powercfg /setactive fehlgeschlagen'; Snapshot=$snap }
                }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$snap } }
        }
        Revert={
            param($Snapshot)
            if ($Snapshot -and $Snapshot.PreGuid) {
                powercfg /setactive $Snapshot.PreGuid 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { @{ Success=$true;  Message="Energieplan auf $($Snapshot.PreGuid) zurueckgesetzt" } }
                else                     { @{ Success=$false; Message='powercfg-Revert fehlgeschlagen' } }
            } else { @{ Success=$false; Message='Kein Snapshot vorhanden' } }
        }
    }

    # ---- Windows: Game Mode ---------------------------------------------------
    [PSCustomObject]@{
        Id='gamemode'; Category='Windows'; Label='Windows Game Mode: AN'
        Description='Priorisiert den Game-Prozess gegenueber Hintergrund-Tasks'
        Impact='KEIN'; ImpactDetail=''; RequiresAdmin=$false
        Changes=@('HKCU\Software\Microsoft\GameBar', 'AutoGameModeEnabled = 1 (DWord)')
        Check={
            $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -ErrorAction SilentlyContinue).AutoGameModeEnabled
            if ($v -eq 1) { @{ Status='OK'; CurrentValue='AN'; Detail='' } }
            else { @{ Status='TWEAK'; CurrentValue='AUS'; Detail='Windows Game Mode aktivieren' } }
        }
        Apply={
            try {
                $snap = Get-RegistrySnapshot -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled'
                if (-not (Test-Path 'HKCU:\Software\Microsoft\GameBar')) { New-Item 'HKCU:\Software\Microsoft\GameBar' -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1 -Type DWord -ErrorAction Stop
                @{ Success=$true; Message='Game Mode aktiviert'; Snapshot=$snap }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            if (Restore-RegistrySnapshot $Snapshot) { @{ Success=$true; Message='Game Mode zurueckgesetzt' } }
            else { @{ Success=$false; Message='Revert fehlgeschlagen' } }
        }
    }

    # ---- Windows: Xbox Game DVR ----------------------------------------------
    [PSCustomObject]@{
        Id='gamedvr'; Category='Windows'; Label='Xbox Game DVR: AUS'
        Description='Game DVR kostet messbar FPS - deaktivieren'
        Impact='KEIN'; ImpactDetail=''; RequiresAdmin=$false
        Changes=@('HKCU\System\GameConfigStore', 'GameDVR_Enabled = 0 (DWord)')
        Check={
            $v = (Get-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -ErrorAction SilentlyContinue).GameDVR_Enabled
            if ($v -eq 0) { @{ Status='OK'; CurrentValue='AUS'; Detail='' } }
            else { @{ Status='TWEAK'; CurrentValue='AN'; Detail='Xbox Game DVR deaktivieren - kostet FPS' } }
        }
        Apply={
            try {
                $snap = Get-RegistrySnapshot -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled'
                Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0 -Type DWord -ErrorAction Stop
                @{ Success=$true; Message='Game DVR deaktiviert'; Snapshot=$snap }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            if (Restore-RegistrySnapshot $Snapshot) { @{ Success=$true; Message='Game DVR zurueckgesetzt' } }
            else { @{ Success=$false; Message='Revert fehlgeschlagen' } }
        }
    }

    # ---- Windows: Enhanced Pointer Precision ---------------------------------
    [PSCustomObject]@{
        Id='mouseaccel'; Category='Windows'; Label='Maus: Enhanced Pointer Precision AUS'
        Description='1:1-Mapping ohne Software-Beschleunigung'
        Impact='KEIN'; ImpactDetail=''; RequiresAdmin=$false
        Changes=@('HKCU\Control Panel\Mouse', 'MouseSpeed = 0', 'MouseThreshold1 = 0', 'MouseThreshold2 = 0')
        Check={
            $v = (Get-ItemProperty 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -ErrorAction SilentlyContinue).MouseSpeed
            if ($v -eq '0') { @{ Status='OK'; CurrentValue='AUS'; Detail='' } }
            else { @{ Status='TWEAK'; CurrentValue='AN'; Detail='Mausbeschleunigung deaktivieren - 1:1-Aim' } }
        }
        Apply={
            try {
                $snap = @{
                    Speed = (Get-RegistrySnapshot -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed')
                    T1    = (Get-RegistrySnapshot -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1')
                    T2    = (Get-RegistrySnapshot -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2')
                }
                Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed'      -Value '0' -Type String -ErrorAction Stop
                Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0' -Type String -ErrorAction Stop
                Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0' -Type String -ErrorAction Stop
                @{ Success=$true; Message='Mausbeschleunigung deaktiviert'; Snapshot=$snap }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            $ok = $true
            if ($Snapshot.Speed) { $ok = (Restore-RegistrySnapshot $Snapshot.Speed) -and $ok }
            if ($Snapshot.T1)    { $ok = (Restore-RegistrySnapshot $Snapshot.T1)    -and $ok }
            if ($Snapshot.T2)    { $ok = (Restore-RegistrySnapshot $Snapshot.T2)    -and $ok }
            if ($ok) { @{ Success=$true; Message='Maus-Einstellungen zurueckgesetzt' } }
            else     { @{ Success=$false; Message='Revert teilweise fehlgeschlagen' } }
        }
    }

    # ---- Windows: Maus-Slider Mitte ------------------------------------------
    [PSCustomObject]@{
        Id='mouseslider'; Category='Windows'; Label='Maus: Slider Mitte (6/11)'
        Description='Slider-Mitte = 1:1-DPI-Mapping ohne Software-Skalierung'
        Impact='KEIN'; ImpactDetail=''; RequiresAdmin=$false
        Changes=@('HKCU\Control Panel\Mouse', 'MouseSensitivity = 10 (= Mitte)')
        Check={
            $v = (Get-ItemProperty 'HKCU:\Control Panel\Mouse' -Name 'MouseSensitivity' -ErrorAction SilentlyContinue).MouseSensitivity
            if ($v -eq '10') { @{ Status='OK'; CurrentValue='10 (Mitte)'; Detail='' } }
            else { @{ Status='TWEAK'; CurrentValue="$v"; Detail='Maus-Slider auf Mitte (6/11 = Wert 10) setzen' } }
        }
        Apply={
            try {
                $snap = Get-RegistrySnapshot -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSensitivity'
                Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name 'MouseSensitivity' -Value '10' -Type String -ErrorAction Stop
                @{ Success=$true; Message='Maus-Slider auf Mitte gesetzt'; Snapshot=$snap }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            if (Restore-RegistrySnapshot $Snapshot) { @{ Success=$true; Message='Maus-Slider zurueckgesetzt' } }
            else { @{ Success=$false; Message='Revert fehlgeschlagen' } }
        }
    }

    # ---- PUBG: Fullscreen-Optimierungen --------------------------------------
    [PSCustomObject]@{
        Id='fso'; Category='PUBG'; Label='Vollbildoptimierungen TslGame.exe: AUS'
        Description='Ermoeglicht Mode 3 (Hardware Independent Flip) statt Compose-Copy'
        Impact='KEIN'; ImpactDetail=''; RequiresAdmin=$false
        Changes=@(
            'HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
            'Wert: <PUBG-Pfad>\TslGame.exe = "~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE"',
            'PUBG-Pfad wird via Steam-Manifest (libraryfolders.vdf) automatisch erkannt'
        )
        Check={
            $layers = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -ErrorAction SilentlyContinue
            if (-not $layers) {
                return @{ Status='TWEAK'; CurrentValue='nicht gesetzt'; Detail='Vollbildoptimierungen fuer TslGame.exe deaktivieren' }
            }
            $tsl = $layers.PSObject.Properties | Where-Object { $_.Name -match 'TslGame.*\.exe$' } | Select-Object -First 1
            if ($tsl -and $tsl.Value -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE') {
                @{ Status='OK'; CurrentValue='deaktiviert'; Detail='' }
            } else {
                @{ Status='TWEAK'; CurrentValue='aktiv'; Detail='Vollbildoptimierungen fuer TslGame.exe deaktivieren' }
            }
        }
        Apply={
            try {
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
                $snap = @{ Path = $path; Entries = $existing }

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
                if (-not $tslExe) {
                    return @{ Success=$false; Message='TslGame.exe nicht gefunden (Steam-Manifest)'; Snapshot=$snap }
                }
                if (-not (Test-Path $path)) { New-Item $path -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty $path -Name $tslExe -Value '~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE' -Type String -ErrorAction Stop
                @{ Success=$true; Message='Vollbildoptimierungen deaktiviert'; Snapshot=$snap }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            try {
                if (-not $Snapshot) { return @{ Success=$false; Message='Kein Snapshot vorhanden' } }
                if (-not (Test-Path $Snapshot.Path)) { return @{ Success=$true; Message='Layers-Key existiert nicht mehr' } }
                $props = Get-ItemProperty -Path $Snapshot.Path -ErrorAction SilentlyContinue
                if ($props) {
                    foreach ($prop in ($props.PSObject.Properties | Where-Object { $_.Name -match 'TslGame.*\.exe$' })) {
                        Remove-ItemProperty -Path $Snapshot.Path -Name $prop.Name -ErrorAction SilentlyContinue
                    }
                }
                foreach ($e in $Snapshot.Entries) {
                    Set-ItemProperty -Path $Snapshot.Path -Name $e.Name -Value $e.OldValue -Type String -ErrorAction SilentlyContinue
                }
                @{ Success=$true; Message='Compat-Flags zurueckgesetzt' }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)" } }
        }
    }

    # ---- PUBG: Engine.ini Tweaks ---------------------------------------------
    [PSCustomObject]@{
        Id='engineini'; Category='PUBG'; Label='Engine.ini Tweaks (Sharpen + Streaming + Pacing + AllowTearing)'
        Description='Spotting-Buff + bessere 1%-Lows + Hardware Independent Flip. BattlEye-safe.'
        Impact='GERING'
        ImpactDetail='Engine.ini ist nach Apply read-only - PUBG-interne r.setres-Aenderungen werden geblockt (kein Crash, nur Reset via PUBG-Menue funktioniert nicht bis Revert).'
        RequiresAdmin=$false
        Changes=@(
            'Datei: %LOCALAPPDATA%\TslGame\Saved\Config\WindowsNoEditor\Engine.ini',
            'Backup vor Aenderung als .bak_<timestamp>',
            '[SystemSettings] r.Tonemapper.Sharpen=0.7  (Spotting auf Distanz)',
            '[SystemSettings] r.GTSyncType=1            (glattere Frametimes)',
            '[SystemSettings] r.OneFrameThreadLag=0     (Frame-Pacing)',
            '[SystemSettings] r.FinishCurrentFrame=0    (Frame-Pacing)',
            '[SystemSettings] r.D3D11.UseAllowTearing=1 (DXGI Flip-Model)',
            '[/Script/Engine.RendererSettings] r.Streaming.PoolSize=4096',
            '[/Script/Engine.RendererSettings] r.Streaming.HLODStrategy=2',
            '[/Script/Engine.RendererSettings] r.Streaming.FramesForFullUpdate=1',
            'Nach Apply: Datei-Attribut ReadOnly (PUBG ueberschreibt sonst beim Spielstart)'
        )
        Check={
            $eng = Get-PUBGEnginePath
            if (-not (Test-Path $eng)) {
                return @{ Status='SKIP'; CurrentValue='Engine.ini nicht gefunden'; Detail='PUBG mind. einmal starten und beenden' }
            }
            $c = Get-Content $eng -Raw
            $hasSharpen   = $c -match 'r\.Tonemapper\.Sharpen\s*=\s*0\.7'
            $hasStreaming = $c -match 'r\.Streaming\.PoolSize\s*=\s*4096'
            $hasGTSync    = $c -match 'r\.GTSyncType\s*=\s*1'
            $hasTearing   = $c -match 'r\.D3D11\.UseAllowTearing\s*=\s*1'
            if ($hasSharpen -and $hasStreaming -and $hasGTSync -and $hasTearing) {
                @{ Status='OK'; CurrentValue='Tweaks vorhanden'; Detail='' }
            } else {
                @{ Status='TWEAK'; CurrentValue='Tweaks fehlen/unvollstaendig'; Detail='Engine.ini-Tweaks anwenden' }
            }
        }
        Apply={
            try {
                $eng = Get-PUBGEnginePath
                if (-not (Test-Path $eng)) {
                    return @{ Success=$false; Message='Engine.ini nicht gefunden - PUBG erst starten/beenden'; Snapshot=$null }
                }
                $wasReadOnly = $false
                try {
                    $attr = (Get-Item $eng -Force).Attributes
                    $wasReadOnly = ($attr -band [System.IO.FileAttributes]::ReadOnly) -ne 0
                } catch {}
                $bak  = Copy-FileToBackup -SourcePath $eng
                $snap = @{ BackupPath = $bak; OriginalPath = $eng; WasReadOnly = $wasReadOnly }

                try {
                    $f = Get-Item $eng -Force
                    if (($f.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
                        $f.Attributes = $f.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
                    }
                } catch {}
                $tweaks = @{
                    'SystemSettings' = @{
                        'r.Tonemapper.Sharpen'    = '0.7'
                        'r.OneFrameThreadLag'     = '0'
                        'r.FinishCurrentFrame'    = '0'
                        'r.GTSyncType'            = '1'
                        'r.D3D11.UseAllowTearing' = '1'
                    }
                    '/Script/Engine.RendererSettings' = @{
                        'r.Streaming.PoolSize'            = '4096'
                        'r.Streaming.HLODStrategy'        = '2'
                        'r.Streaming.FramesForFullUpdate' = '1'
                    }
                }
                foreach ($sec in $tweaks.Keys) {
                    foreach ($k in $tweaks[$sec].Keys) {
                        if (-not (Update-IniValue -Path $eng -Section $sec -Key $k -Value $tweaks[$sec][$k])) {
                            return @{ Success=$false; Message="Schreiben fehlgeschlagen bei [$sec] $k"; Snapshot=$snap }
                        }
                    }
                }
                try {
                    $f2 = Get-Item $eng -Force
                    $f2.Attributes = $f2.Attributes -bor [System.IO.FileAttributes]::ReadOnly
                } catch {}
                @{ Success=$true; Message='Engine.ini-Tweaks geschrieben (Datei read-only gesetzt)'; Snapshot=$snap }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            if ($Snapshot -and $Snapshot.BackupPath -and $Snapshot.OriginalPath) {
                if (Restore-FileFromBackup -BackupPath $Snapshot.BackupPath -TargetPath $Snapshot.OriginalPath) {
                    @{ Success=$true; Message='Engine.ini aus Backup wiederhergestellt' }
                } else { @{ Success=$false; Message='Restore aus Backup fehlgeschlagen' } }
            } else { @{ Success=$false; Message='Kein Backup-Snapshot vorhanden' } }
        }
    }

    # ---- PUBG: In-Game FPS-Cap ------------------------------------------------
    # Menuekonform: PUBGs In-Game-FPS-Cap kennt nur "Unlimited" und "Display
    # Based". "Display Based" = FrameRateLimit auf die Monitor-Hz. Ein krummer
    # Wert wie 237 ist ueber das Spiel-Menue NICHT erzeugbar und wuerde von PUBG
    # beim Start zurueckgesetzt - der eigentliche Competitive-Cap (Hz minus 3)
    # laeuft daher ueber den NVIDIA Frame Rate Limiter (Tweak 'nvprofile').
    # FrameRateLimit liegt in der Sektion [/Script/TslGame.TslGameUserSettings]
    # (gegen reale GameUserSettings.ini verifiziert).
    [PSCustomObject]@{
        Id='fpscap'; Category='PUBG'; Label='PUBG In-Game FPS-Cap = Display-Based (Monitor-Hz)'
        Description='Setzt PUBGs In-Game-FPS-Cap menuekonform auf "Display Based". Der scharfe Competitive-Cap (Hz minus 3) kommt vom NVIDIA-Treiber-Limiter.'
        Impact='KEIN'; ImpactDetail=''; RequiresAdmin=$false
        Changes=@(
            'Datei: %LOCALAPPDATA%\TslGame\Saved\Config\WindowsNoEditor\GameUserSettings.ini',
            'Backup vor Aenderung als .bak_<timestamp>',
            'FrameRateLimit in [/Script/TslGame.TslGameUserSettings] = aktuelle Primary-Monitor-Hz',
            'Menuekonform: entspricht der In-Game-Einstellung "FPS-Cap: Display Based"',
            'PUBG muss beim Anwenden geschlossen sein (sonst Overwrite beim Beenden)'
        )
        Check={
            $gus = Get-PUBGGameUserPath
            if (-not (Test-Path $gus)) {
                return @{ Status='SKIP'; CurrentValue='GameUserSettings.ini nicht gefunden'; Detail='PUBG mind. einmal starten/beenden' }
            }
            $hz = Get-PrimaryMonitorHz
            $c = Get-Content $gus -Raw
            if ($c -match '(?m)^\s*FrameRateLimit\s*=\s*([\d.]+)') {
                $v = [int][math]::Floor([double]$matches[1])
                if ($v -eq $hz) { @{ Status='OK'; CurrentValue="$v FPS (Display-Based)"; Detail='' } }
                else { @{ Status='TWEAK'; CurrentValue="$v FPS"; Detail="In-Game-Cap auf Display-Based ($hz) setzen" } }
            } else {
                @{ Status='TWEAK'; CurrentValue='kein Cap gesetzt'; Detail="In-Game-Cap auf Display-Based ($hz) setzen" }
            }
        }
        Apply={
            try {
                $gus = Get-PUBGGameUserPath
                if (-not (Test-Path $gus)) {
                    return @{ Success=$false; Message='GameUserSettings.ini nicht gefunden'; Snapshot=$null }
                }
                # PUBG darf nicht laufen - es ueberschreibt GameUserSettings.ini beim Beenden.
                if (@(Get-Process -Name 'TslGame' -ErrorAction SilentlyContinue).Count -gt 0) {
                    return @{ Success=$false; Message='PUBG laeuft - bitte erst komplett beenden, dann Apply'; Snapshot=$null }
                }
                $bak  = Copy-FileToBackup -SourcePath $gus
                $snap = @{ BackupPath = $bak; OriginalPath = $gus }
                $hz = Get-PrimaryMonitorHz
                if (-not (Update-IniValue -Path $gus -Section '/Script/TslGame.TslGameUserSettings' -Key 'FrameRateLimit' -Value ('{0}.000000' -f $hz))) {
                    return @{ Success=$false; Message='Schreiben von FrameRateLimit fehlgeschlagen'; Snapshot=$snap }
                }
                # Post-Apply-Verifikation: Wert zuruecklesen
                $verify = Get-Content $gus -Raw -ErrorAction SilentlyContinue
                if ($verify -match '(?m)^\s*FrameRateLimit\s*=\s*([\d.]+)' -and [int][math]::Floor([double]$matches[1]) -eq $hz) {
                    @{ Success=$true; Message="In-Game-FPS-Cap auf Display-Based ($hz) gesetzt - scharfer Cap via NVIDIA-Profil"; Snapshot=$snap }
                } else {
                    @{ Success=$false; Message='FrameRateLimit nach Apply nicht verifizierbar'; Snapshot=$snap }
                }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            if ($Snapshot -and $Snapshot.BackupPath -and $Snapshot.OriginalPath) {
                if (Restore-FileFromBackup -BackupPath $Snapshot.BackupPath -TargetPath $Snapshot.OriginalPath) {
                    @{ Success=$true; Message='GameUserSettings.ini aus Backup wiederhergestellt' }
                } else { @{ Success=$false; Message='Restore aus Backup fehlgeschlagen' } }
            } else { @{ Success=$false; Message='Kein Backup-Snapshot vorhanden' } }
        }
    }

    # ---- Windows: Defender Exclusion -----------------------------------------
    [PSCustomObject]@{
        Id='defender'; Category='Windows'; Label='Defender-Exclusion fuer PUBG-Ordner'
        Description='1-4% FPS + besseres Map-Streaming durch Skip des Real-Time-Scans'
        Impact='GERING'; ImpactDetail='Risiko nur bei Mods/fremden Dateien im PUBG-Ordner'
        RequiresAdmin=$true
        Changes=@(
            'Add-MpPreference -ExclusionPath <PUBG-Pfad aus Steam-Manifest>',
            'Windows Defender Real-Time Scan ueberspringt den PUBG-Ordner'
        )
        Check={
            try {
                $excl = @((Get-MpPreference -ErrorAction Stop).ExclusionPath)
                if ($excl -and ($excl -match 'PUBG|TslGame')) {
                    @{ Status='OK'; CurrentValue='PUBG exkludiert'; Detail='' }
                } else {
                    @{ Status='TWEAK'; CurrentValue='keine Exclusion'; Detail='PUBG-Ordner zu Defender-Exclusions hinzufuegen' }
                }
            } catch { @{ Status='SKIP'; CurrentValue='nicht auslesbar'; Detail='Get-MpPreference fehlgeschlagen (Admin?)' } }
        }
        Apply={
            try {
                $excl = @()
                try { $excl = @((Get-MpPreference -ErrorAction Stop).ExclusionPath) } catch {}
                $snap = @{ PreExisting = @($excl | Where-Object { $_ -match 'PUBG|TslGame' }) }

                $steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
                if (-not $steamPath) { return @{ Success=$false; Message='Steam-Pfad nicht gefunden'; Snapshot=$snap } }
                $libContent = Get-Content "$steamPath\steamapps\libraryfolders.vdf" -Raw
                $libs = [regex]::Matches($libContent, '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\','\' }
                foreach ($lib in $libs) {
                    $pubg = Join-Path $lib 'steamapps\common\PUBG'
                    if (Test-Path $pubg) {
                        Add-MpPreference -ExclusionPath $pubg -ErrorAction Stop
                        return @{ Success=$true; Message="Defender-Exclusion gesetzt: $pubg"; Snapshot=$snap }
                    }
                }
                @{ Success=$false; Message='PUBG-Ordner in keiner Steam-Library gefunden'; Snapshot=$snap }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            try {
                $cur = @((Get-MpPreference -ErrorAction Stop).ExclusionPath)
                $pubgNow = @($cur | Where-Object { $_ -match 'PUBG|TslGame' })
                $preExisting = if ($Snapshot -and $Snapshot.PreExisting) { @($Snapshot.PreExisting) } else { @() }
                foreach ($e in $pubgNow) {
                    if ($e -notin $preExisting) { Remove-MpPreference -ExclusionPath $e -ErrorAction SilentlyContinue }
                }
                @{ Success=$true; Message='Defender-Exclusion zurueckgesetzt' }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)" } }
        }
    }

    # ---- Windows: VBS + HVCI --------------------------------------------------
    [PSCustomObject]@{
        Id='hvci'; Category='Windows'; Label='Virtualization Security (VBS + HVCI): AUS'
        Description='5-10% FPS in CPU-bound Games. Erfordert Reboot.'
        Impact='MITTEL'
        ImpactDetail='Senkt OS-Security: kein Memory Integrity (HVCI), kein Credential Guard, kein Hyper-V-Hypervisor. Fuer Solo-Gaming-PC vertretbar.'
        RequiresAdmin=$true
        Changes=@(
            'HKLM\...\DeviceGuard\EnableVirtualizationBasedSecurity = 0',
            'HKLM\...\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity\Enabled = 0',
            'HKLM\...\DeviceGuard\Scenarios\CredentialGuard\Enabled = 0',
            'bcdedit /set hypervisorlaunchtype off  (kritisch fuer 24H2/25H2)',
            'WICHTIG: greift erst nach REBOOT'
        )
        Check={
            try {
                $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
                $running = @($dg.SecurityServicesRunning)
                $hvciOn = $running -contains 2
                $credGuardOn = $running -contains 1
                $hyperVUp = ($dg.VirtualizationBasedSecurityStatus -eq 2)
                if ($hvciOn -or $credGuardOn) {
                    $w = @(); if ($hvciOn) { $w += 'HVCI' }; if ($credGuardOn) { $w += 'CredGuard' }
                    @{ Status='TWEAK'; CurrentValue=($w -join ' + ') + ' aktiv'
                       Detail='VBS/HVCI deaktivieren (Reboot noetig) - 5-10% FPS in CPU-Last' }
                } elseif ($hyperVUp) {
                    @{ Status='TWEAK'; CurrentValue='Hypervisor an (Services aus)'
                       Detail='Hypervisor via bcdedit komplett abschalten' }
                } else {
                    @{ Status='OK'; CurrentValue='AUS'; Detail='' }
                }
            } catch { @{ Status='SKIP'; CurrentValue='nicht auslesbar'; Detail='Win32_DeviceGuard nicht verfuegbar' } }
        }
        Apply={
            try {
                $rootDG       = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
                $hvciKey      = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
                $credGuardKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard'
                $hvLaunchType = 'auto'
                try {
                    $bcdOut = & bcdedit /enum '{current}' 2>$null | Out-String
                    if ($bcdOut -match '(?im)^\s*hypervisorlaunchtype\s+(\w+)') { $hvLaunchType = $matches[1] }
                } catch {}
                $snap = @{
                    Vbs          = (Get-RegistrySnapshot -Path $rootDG -Name 'EnableVirtualizationBasedSecurity')
                    Hvci         = (Get-RegistrySnapshot -Path $hvciKey -Name 'Enabled')
                    CredGuard    = (Get-RegistrySnapshot -Path $credGuardKey -Name 'Enabled')
                    HvLaunchType = $hvLaunchType
                }
                foreach ($p in @($rootDG,$hvciKey,$credGuardKey)) {
                    if (-not (Test-Path $p)) { New-Item $p -Force -ErrorAction Stop | Out-Null }
                }
                Set-ItemProperty $rootDG       -Name 'EnableVirtualizationBasedSecurity' -Value 0 -Type DWord -ErrorAction Stop
                Set-ItemProperty $hvciKey      -Name 'Enabled' -Value 0 -Type DWord -ErrorAction Stop
                Set-ItemProperty $credGuardKey -Name 'Enabled' -Value 0 -Type DWord -ErrorAction Stop
                $bcdOut = & bcdedit /set hypervisorlaunchtype off 2>&1
                if ($LASTEXITCODE -ne 0) { Write-RegLog "bcdedit failed: $bcdOut" 'WARN' }
                @{ Success=$true; Message='VBS/HVCI deaktiviert - Reboot erforderlich'; Snapshot=$snap }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            $ok = $true
            if ($Snapshot.Vbs)       { $ok = (Restore-RegistrySnapshot $Snapshot.Vbs)       -and $ok }
            if ($Snapshot.Hvci)      { $ok = (Restore-RegistrySnapshot $Snapshot.Hvci)      -and $ok }
            if ($Snapshot.CredGuard) { $ok = (Restore-RegistrySnapshot $Snapshot.CredGuard) -and $ok }
            if ($Snapshot.HvLaunchType) {
                try { & bcdedit /set hypervisorlaunchtype $Snapshot.HvLaunchType 2>&1 | Out-Null } catch { $ok = $false }
            }
            if ($ok) { @{ Success=$true; Message='VBS/HVCI zurueckgesetzt - Reboot erforderlich' } }
            else     { @{ Success=$false; Message='Revert teilweise fehlgeschlagen' } }
        }
    }

    # ---- GPU: HAGS ------------------------------------------------------------
    [PSCustomObject]@{
        Id='hags'; Category='GPU'; Label='Hardware-accelerated GPU Scheduling (HAGS): AN'
        Description='Verschiebt GPU-Queue-Submit auf den GPU-MCU. Voraussetzung fuer voll funktionsfaehigen NVIDIA Reflex.'
        Impact='GERING'
        ImpactDetail='PUBG-spezifisch unklar - kein publizierter A/B-Test. Manuell testen, nicht in Apply-All.'
        RequiresAdmin=$true
        Changes=@(
            'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\HwSchMode',
            'HwSchMode = 2 (0=disabled, 2=enabled, REG_DWORD)',
            'WICHTIG: greift erst nach REBOOT'
        )
        Check={
            try {
                $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -ErrorAction SilentlyContinue).HwSchMode
                if ($null -eq $v)   { @{ Status='SKIP';  CurrentValue='nicht gesetzt'; Detail='HwSchMode-Wert nicht vorhanden' } }
                elseif ($v -eq 2)   { @{ Status='OK';    CurrentValue='AN'; Detail='' } }
                else                { @{ Status='TWEAK'; CurrentValue='AUS'; Detail='HAGS aktivieren (Reboot noetig)' } }
            } catch { @{ Status='SKIP'; CurrentValue='nicht auslesbar'; Detail='' } }
        }
        Apply={
            try {
                $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
                $snap = Get-RegistrySnapshot -Path $key -Name 'HwSchMode'
                if (-not (Test-Path $key)) { New-Item $key -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty $key -Name 'HwSchMode' -Value 2 -Type DWord -ErrorAction Stop
                @{ Success=$true; Message='HAGS aktiviert - Reboot erforderlich'; Snapshot=$snap }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            if (Restore-RegistrySnapshot $Snapshot) { @{ Success=$true; Message='HAGS zurueckgesetzt - Reboot erforderlich' } }
            else { @{ Success=$false; Message='Revert fehlgeschlagen' } }
        }
    }

    # ---- Windows: MMCSS Gaming-Profil ----------------------------------------
    [PSCustomObject]@{
        Id='mmcss'; Category='Windows'; Label='MMCSS Gaming-Profil'
        Description='Gibt Multimedia-Threads mehr CPU, stoppt den Network-Throttle'
        Impact='GERING'; ImpactDetail='Effekt 2026 modest, aber harmlos'; RequiresAdmin=$true
        Changes=@(
            'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile',
            'SystemResponsiveness = 10 (statt 20 Default)',
            'NetworkThrottlingIndex = 0xFFFFFFFF (deaktiviert 10ms-Throttle)'
        )
        Check={
            $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            $r = (Get-ItemProperty $k -Name 'SystemResponsiveness'  -ErrorAction SilentlyContinue).SystemResponsiveness
            $n = (Get-ItemProperty $k -Name 'NetworkThrottlingIndex' -ErrorAction SilentlyContinue).NetworkThrottlingIndex
            # 0xFFFFFFFF kommt je nach PS-Version als "4294967295" (UInt32) ODER -1 (Int32 signed)
            # zurueck. String-Cast macht beide Faelle vergleichbar.
            $nStr = "$n"
            $nOk  = ($nStr -eq '-1') -or ($nStr -eq '4294967295')
            $rOk  = ($null -ne $r) -and ([int]$r -le 10)
            if ($rOk -and $nOk) {
                @{ Status='OK'; CurrentValue="SystemResponsiveness=$r, NetworkThrottlingIndex=optimal"; Detail='' }
            } else {
                @{ Status='TWEAK'
                   CurrentValue="SystemResponsiveness=$r, NetworkThrottlingIndex=$nStr"
                   Detail='MMCSS-Gaming-Profil setzen (SystemResponsiveness=10, NetworkThrottlingIndex=FFFFFFFF)' }
            }
        }
        Apply={
            try {
                $k     = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
                $kReg  = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
                $snap  = @{
                    SysResp  = (Get-RegistrySnapshot -Path $k -Name 'SystemResponsiveness')
                    NetThrot = (Get-RegistrySnapshot -Path $k -Name 'NetworkThrottlingIndex')
                }
                Set-ItemProperty $k -Name 'SystemResponsiveness' -Value 10 -Type DWord -ErrorAction Stop
                & reg.exe add $kReg /v 'NetworkThrottlingIndex' /t REG_DWORD /d 0xFFFFFFFF /f | Out-Null
                if ($LASTEXITCODE -ne 0) { return @{ Success=$false; Message='reg.exe add NetworkThrottlingIndex fehlgeschlagen'; Snapshot=$snap } }
                @{ Success=$true; Message='MMCSS-Gaming-Profil gesetzt'; Snapshot=$snap }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            $ok = $true
            if ($Snapshot.SysResp)  { $ok = (Restore-RegistrySnapshot $Snapshot.SysResp)  -and $ok }
            if ($Snapshot.NetThrot) { $ok = (Restore-RegistrySnapshot $Snapshot.NetThrot) -and $ok }
            if ($ok) { @{ Success=$true; Message='MMCSS-Werte zurueckgesetzt' } }
            else     { @{ Success=$false; Message='Revert teilweise fehlgeschlagen' } }
        }
    }

    # ---- Windows: Game-unfreundliche Dienste ---------------------------------
    [PSCustomObject]@{
        Id='services'; Category='Windows'; Label='Game-unfreundliche Dienste deaktivieren'
        Description='Stoppt Background-Scan/Indexer/Telemetrie waehrend des Matches'
        Impact='GERING'; ImpactDetail='Windows-Suche ohne WSearch ein paar Sekunden langsamer'
        RequiresAdmin=$true
        Changes=@(
            'SysMain (SuperFetch/Prefetch)  -> Disabled + Stop',
            'WSearch (Windows Search Indexer) -> Disabled + Stop',
            'DiagTrack (Connected User Experiences & Telemetry) -> Disabled + Stop',
            'MapsBroker -> Disabled + Stop'
        )
        Check={
            $svcs = 'SysMain','WSearch','DiagTrack','MapsBroker'
            $running = @($svcs | ForEach-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue } | Where-Object { $_.Status -eq 'Running' })
            if ($running.Count -eq 0) {
                @{ Status='OK'; CurrentValue='alle gestoppt'; Detail='' }
            } else {
                @{ Status='TWEAK'; CurrentValue=($running.Name -join ', ') + ' aktiv'
                   Detail='Game-unfreundliche Dienste deaktivieren' }
            }
        }
        Apply={
            try {
                $states = @()
                foreach ($s in 'SysMain','WSearch','DiagTrack','MapsBroker') {
                    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
                    if ($svc) { $states += @{ Name=$s; StartType=[string]$svc.StartType; Status=[string]$svc.Status } }
                }
                $snap = @{ Services = $states }
                $fails = 0
                foreach ($s in 'SysMain','WSearch','DiagTrack','MapsBroker') {
                    try {
                        Set-Service -Name $s -StartupType Disabled -ErrorAction Stop
                        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
                    } catch { $fails++ }
                }
                if ($fails -eq 0) { @{ Success=$true; Message='Dienste deaktiviert und gestoppt'; Snapshot=$snap } }
                else { @{ Success=$false; Message="$fails Dienst(e) konnten nicht geaendert werden"; Snapshot=$snap } }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            $ok = $true
            if ($Snapshot -and $Snapshot.Services) {
                foreach ($s in $Snapshot.Services) {
                    try {
                        Set-Service -Name $s.Name -StartupType $s.StartType -ErrorAction Stop
                        if ($s.Status -eq 'Running') { Start-Service -Name $s.Name -ErrorAction SilentlyContinue }
                    } catch { $ok = $false }
                }
            }
            if ($ok) { @{ Success=$true; Message='Dienste-Starttyp zurueckgesetzt' } }
            else     { @{ Success=$false; Message='Revert teilweise fehlgeschlagen' } }
        }
    }

    # ---- Network: NIC Offloads -----------------------------------------------
    [PSCustomObject]@{
        Id='nicoffload'; Category='Network'; Label='NIC Offloads (LSO, RSC) deaktivieren'
        Description='Reduziert Netzwerk-Latenz fuer Gaming-UDP-Traffic'
        Impact='KEIN'; ImpactDetail=''; RequiresAdmin=$true
        Changes=@(
            'Disable-NetAdapterLso -IPv4 -IPv6 (Large Send Offload v2 aus)',
            'Disable-NetAdapterRsc -IPv4 -IPv6 (Receive Segment Coalescing aus)',
            'Betrifft den ersten aktiven (Up, non-Virtual) Adapter'
        )
        Check={
            $nic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual } | Select-Object -First 1
            if (-not $nic) { return @{ Status='SKIP'; CurrentValue='kein aktiver Adapter'; Detail='' } }
            $lso = Get-NetAdapterLso -Name $nic.Name -ErrorAction SilentlyContinue
            $rsc = Get-NetAdapterRsc -Name $nic.Name -ErrorAction SilentlyContinue
            $bad = $false
            if ($lso -and ($lso.V2IPv4Enabled -or $lso.V2IPv6Enabled)) { $bad = $true }
            if ($rsc -and ($rsc.IPv4Enabled  -or $rsc.IPv6Enabled))    { $bad = $true }
            if ($bad) {
                @{ Status='TWEAK'; CurrentValue="$($nic.Name): LSO/RSC aktiv"; Detail='LSO v2 und RSC am NIC deaktivieren' }
            } else {
                @{ Status='OK'; CurrentValue="$($nic.Name): LSO/RSC aus"; Detail='' }
            }
        }
        Apply={
            try {
                $nic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual } | Select-Object -First 1
                if (-not $nic) { return @{ Success=$false; Message='Kein aktiver Netzwerkadapter gefunden'; Snapshot=$null } }
                $lso = Get-NetAdapterLso -Name $nic.Name -ErrorAction SilentlyContinue
                $rsc = Get-NetAdapterRsc -Name $nic.Name -ErrorAction SilentlyContinue
                $snap = @{
                    NicName = $nic.Name
                    LsoV4 = if ($lso) { $lso.V2IPv4Enabled } else { $null }
                    LsoV6 = if ($lso) { $lso.V2IPv6Enabled } else { $null }
                    RscV4 = if ($rsc) { $rsc.IPv4Enabled } else { $null }
                    RscV6 = if ($rsc) { $rsc.IPv6Enabled } else { $null }
                }
                Disable-NetAdapterLso -Name $nic.Name -IPv4 -IPv6 -ErrorAction Stop
                Disable-NetAdapterRsc -Name $nic.Name -IPv4 -IPv6 -ErrorAction Stop
                @{ Success=$true; Message="LSO/RSC auf $($nic.Name) deaktiviert"; Snapshot=$snap }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            try {
                if (-not $Snapshot -or -not $Snapshot.NicName) { return @{ Success=$false; Message='Kein Snapshot vorhanden' } }
                if ($Snapshot.LsoV4) { Enable-NetAdapterLso -Name $Snapshot.NicName -IPv4 -ErrorAction SilentlyContinue }
                if ($Snapshot.LsoV6) { Enable-NetAdapterLso -Name $Snapshot.NicName -IPv6 -ErrorAction SilentlyContinue }
                if ($Snapshot.RscV4) { Enable-NetAdapterRsc -Name $Snapshot.NicName -IPv4 -ErrorAction SilentlyContinue }
                if ($Snapshot.RscV6) { Enable-NetAdapterRsc -Name $Snapshot.NicName -IPv6 -ErrorAction SilentlyContinue }
                @{ Success=$true; Message="LSO/RSC auf $($Snapshot.NicName) wiederhergestellt" }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)" } }
        }
    }

    # ---- GPU: NVIDIA PUBG-Profil ---------------------------------------------
    [PSCustomObject]@{
        Id='nvprofile'; Category='GPU'; Label='NVIDIA PUBG-Profil (Low Latency, Power Max, FPS-Cap)'
        Description='Setzt das PUBG-Treiberprofil via NVIDIA Profile Inspector (.nip-Import) - inkl. FPS-Cap auf Monitor-Hz minus 3 (Frame Rate Limiter V3)'
        Impact='KEIN'; ImpactDetail='NPI wird bei Bedarf automatisch installiert. Schreibt nur das PUBG-Profil; andere Treiberprofile bleiben unangetastet (Read-Modify-Write).'
        RequiresAdmin=$true
        Changes=@(
            'Tool: NVIDIA Profile Inspector (Auto-Install nach C:\Tools\nvidiaProfileInspector\)',
            "Profil: PLAYERUNKNOWN'S BATTLEGROUNDS (TslGame.exe)",
            'Power Management Mode = Prefer Max Performance',
            'Vertical Sync = ON (G-SYNC-101: Tearing-Fallback, keine Latenz solange Cap unter Refresh)',
            'Texture Filtering Quality = High Performance',
            'Threaded Optimization = ON',
            'Ultra Low Latency = Off (manueller FPS-Cap ist wirksamer; ULL kann CPU-bound Latenz erhoehen)',
            'Frame Rate Limiter V3 = Monitor-Hz minus 3 (dynamisch, der eigentliche Competitive-FPS-Cap)',
            'Mechanik: .nip-Datei generieren + nvidiaProfileInspector -silentImport (Read-Modify-Write)',
            'Stamp-File: %LOCALAPPDATA%\PUBGDiag\npi-applied.stamp'
        )
        Check={
            if (Test-Path $script:NpiStampPath) {
                $age = (Get-Date) - (Get-Item $script:NpiStampPath).LastWriteTime
                if ($age.TotalDays -lt 60) {
                    return @{ Status='OK'; CurrentValue="angewandt vor $([int]$age.TotalDays) Tagen"; Detail='' }
                }
                return @{ Status='TWEAK'; CurrentValue="angewandt vor $([int]$age.TotalDays) Tagen (>60d)"
                          Detail='NVIDIA PUBG-Profil erneut anwenden' }
            }
            @{ Status='TWEAK'; CurrentValue='nicht angewandt'; Detail='NVIDIA PUBG-Profil anwenden' }
        }
        Apply={
            try {
                $npi = Get-NPIPath
                if (-not $npi) {
                    $npi = Install-NPIFromGitHub
                    if (-not $npi) { return @{ Success=$false; Message='NVIDIA Profile Inspector konnte nicht installiert werden'; Snapshot=$null } }
                }
                $result = Invoke-NPIPubgProfile -NpiPath $npi
                if ($result.Success) {
                    @{ Success=$true; Message='NVIDIA PUBG-Profil angewandt (.nip-Import)'
                       Snapshot=@{ Method='npi-nip'; Backup=$result.Backup; AppliedAt=(Get-Date).ToString('o') } }
                } else {
                    @{ Success=$false; Message=$result.Message; Snapshot=$null }
                }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            # Read-Modify-Write: exportiert den Ist-Zustand, entfernt nur die vom
            # Tweak gesetzten Profil-Werte, importiert zurueck. Braucht NPI.
            $npi = Get-NPIPath
            if (-not $npi) {
                return @{ Success=$false; Message='NVIDIA Profile Inspector nicht gefunden - Profil-Werte manuell via NVIDIA-Systemsteuerung zuruecksetzen' }
            }
            $result = Revert-NPIPubgProfile -NpiPath $npi
            if ($result.Success) {
                @{ Success=$true; Message='NVIDIA PUBG-Profil zurueckgesetzt (Profil-Werte entfernt -> Treiber-Default)' }
            } else {
                @{ Success=$false; Message=$result.Message }
            }
        }
    }

    # ---- GPU: G-Sync aktivieren ----------------------------------------------
    # Aktiviert G-Sync/VRR: globales 'Base Profile' (= NVCP-Master-Schalter) +
    # PUBG-Profil. G-Sync ist die Voraussetzung fuer tearing-freies Spielen OHNE
    # V-Sync-Latenz: zusammen mit dem FPS-Cap unter Refresh (Tweak 'nvprofile')
    # bleibt die Framerate im VRR-Fenster -> kein Tearing, kein Stutter.
    [PSCustomObject]@{
        Id='gsync'; Category='GPU'; Label='G-Sync aktivieren (VRR, tearing-frei)'
        Description='Aktiviert G-Sync/VRR global + fuer PUBG via NVIDIA Profile Inspector (.nip-Import) - Voraussetzung fuer tearing-freies Spielen ohne V-Sync-Latenz'
        Impact='KEIN'; ImpactDetail='Benoetigt einen G-Sync-(Compatible-)Monitor mit aktiver VRR/Adaptive-Sync-Einstellung im Monitor-OSD. Setzt das globale Treiberprofil per Read-Modify-Write - vorhandene globale Einstellungen bleiben erhalten.'
        RequiresAdmin=$true
        Changes=@(
            'Tool: NVIDIA Profile Inspector (.nip-Import, Read-Modify-Write)',
            'Globales Profil (Base Profile = NVCP-Master-Schalter):',
            '  G-SYNC Global Feature = On, Global Mode = Fullscreen only',
            "PUBG-Profil (TslGame.exe):",
            '  G-SYNC Application Mode = Fullscreen only, Application State = Allow',
            'Stamp-File: %LOCALAPPDATA%\PUBGDiag\gsync-applied.stamp',
            'Voraussetzung: VRR/Adaptive-Sync muss im Monitor-OSD aktiv sein (kann die Suite nicht setzen)'
        )
        Check={
            if (Test-Path $script:GSyncStampPath) {
                $age = (Get-Date) - (Get-Item $script:GSyncStampPath).LastWriteTime
                return @{ Status='OK'; CurrentValue="aktiviert vor $([int]$age.TotalDays) Tagen"
                          Detail='Bestaetigung: VRR im Monitor-OSD pruefen, G-SYNC-Indikator in der NVIDIA-Systemsteuerung einschalten' }
            }
            @{ Status='TWEAK'; CurrentValue='nicht aktiviert'; Detail='G-Sync global + fuer PUBG aktivieren' }
        }
        Apply={
            try {
                $npi = Get-NPIPath
                if (-not $npi) {
                    $npi = Install-NPIFromGitHub
                    if (-not $npi) { return @{ Success=$false; Message='NVIDIA Profile Inspector konnte nicht installiert werden'; Snapshot=$null } }
                }
                $result = Invoke-NPIGSync -NpiPath $npi
                if ($result.Success) {
                    @{ Success=$true
                       Message='G-Sync aktiviert (global + PUBG). WICHTIG: im Monitor-OSD VRR/Adaptive-Sync einschalten; zur Kontrolle den G-SYNC-Indikator in der NVIDIA-Systemsteuerung aktivieren.'
                       Snapshot=@{ Method='npi-nip'; Backup=$result.Backup; AppliedAt=(Get-Date).ToString('o') } }
                } else {
                    @{ Success=$false; Message=$result.Message; Snapshot=$null }
                }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            $npi = Get-NPIPath
            if (-not $npi) {
                return @{ Success=$false; Message='NVIDIA Profile Inspector nicht gefunden - G-Sync-Werte manuell via NVIDIA-Systemsteuerung zuruecksetzen' }
            }
            $result = Revert-NPIGSync -NpiPath $npi
            if ($result.Success) {
                @{ Success=$true; Message='G-Sync-Profilwerte zurueckgesetzt (global + PUBG auf Treiber-Default)' }
            } else {
                @{ Success=$false; Message=$result.Message }
            }
        }
    }

    # ---- Windows: Globale Timer-Resolution-Requests --------------------------
    [PSCustomObject]@{
        Id='timerres'; Category='Windows'; Label='Globale Timer-Resolution-Requests: AN'
        Description='Stellt das systemweite Timer-Verhalten wieder her. Seit Windows 10 v2004 / Windows 11 wirkt eine Timer-Resolution-Anforderung nur noch pro Prozess - andere Prozesse fallen auf 15,625 ms zurueck, was Frame-Pacing-Ruckler und bei manchen Engines einen 64-FPS-Deckel verursacht.'
        Impact='GERING'
        ImpactDetail='Desktop empfohlen. Auf Laptop/Akku-Betrieb erhoehter Stromverbrauch - dort weglassen. Greift erst nach Reboot.'
        RequiresAdmin=$true
        Changes=@(
            'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel\GlobalTimerResolutionRequests',
            'GlobalTimerResolutionRequests = 1 (REG_DWORD)',
            'Danach wirkt timeBeginPeriod jedes Prozesses (auch PUBG) wieder systemweit',
            'WICHTIG: greift erst nach REBOOT (Kernel liest den Wert beim Start)'
        )
        Check={
            try {
                $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
                $v = (Get-ItemProperty $k -Name 'GlobalTimerResolutionRequests' -ErrorAction SilentlyContinue).GlobalTimerResolutionRequests
                # Live-Wert: aktuell aktive Timer-Resolution (kontextabhaengig - nur
                # hoch, solange ein Prozess sie anfordert). Der definitive Probe-Test
                # liegt im 'Timer-Res. pruefen'-Button im Tweaks-Tab.
                $ms = Get-CurrentTimerResolutionMs
                $live = if ($null -ne $ms) { 'Timer aktuell {0:0.00} ms' -f $ms } else { 'Timer-Messung n/v' }
                if ($v -eq 1) { @{ Status='OK';    CurrentValue="AN  -  $live";  Detail='' } }
                else          { @{ Status='TWEAK'; CurrentValue="AUS  -  $live"; Detail='Globale Timer-Requests aktivieren (Reboot noetig)' } }
            } catch { @{ Status='SKIP'; CurrentValue='nicht auslesbar'; Detail='' } }
        }
        Apply={
            try {
                $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
                $snap = Get-RegistrySnapshot -Path $k -Name 'GlobalTimerResolutionRequests'
                if (-not (Test-Path $k)) { New-Item $k -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty $k -Name 'GlobalTimerResolutionRequests' -Value 1 -Type DWord -ErrorAction Stop
                @{ Success=$true; Message='Globale Timer-Requests aktiviert - Reboot erforderlich'; Snapshot=$snap }
            } catch { @{ Success=$false; Message="Fehler: $($_.Exception.Message)"; Snapshot=$null } }
        }
        Revert={
            param($Snapshot)
            if (Restore-RegistrySnapshot $Snapshot) { @{ Success=$true; Message='Globale Timer-Requests zurueckgesetzt - Reboot erforderlich' } }
            else { @{ Success=$false; Message='Revert fehlgeschlagen' } }
        }
    }
)

# ===========================================================================
#  OEFFENTLICHE API
# ===========================================================================
function Get-PUBGTweakRegistry {
    <#
    .SYNOPSIS
        Liefert die vollstaendige Liste aller Tweaks (PSCustomObject-Array).
    .DESCRIPTION
        Jeder Tweak hat Id/Category/Label/Description/Impact/ImpactDetail/
        RequiresAdmin/Changes sowie die Scriptbloecke Check/Apply/Revert.
        Die Suite rendert daraus den Tweaks-Tab; die Diagnose ruft pro Tweak
        Check auf.
    #>
    return $script:PUBGTweaks
}

Export-ModuleMember -Function Get-PUBGTweakRegistry
