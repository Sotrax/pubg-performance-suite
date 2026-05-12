# Installation Guide

## Method 1: One-Line Bootstrap (Recommended)

Open an **Administrator PowerShell** and run:

```powershell
irm "https://raw.githubusercontent.com/Sotrax/pubg-performance-suite/main/launch.ps1" | iex
```

This will:
1. Download the latest version from GitHub `main` branch
2. Extract to `%LOCALAPPDATA%\PUBGSuite\app\`
3. Create a Desktop shortcut
4. Launch the suite

Re-run anytime to update.

### Customizing the source

If you forked the repo, point to your fork:

```powershell
$env:PUBGSUITE_REPO = 'your-username/your-fork-name'
irm "https://raw.githubusercontent.com/$env:PUBGSUITE_REPO/main/launch.ps1" | iex
```

## Method 2: Manual Install

1. Download the [latest release ZIP](https://github.com/Sotrax/pubg-performance-suite/releases) or clone the repo:
   ```bash
   git clone https://github.com/Sotrax/pubg-performance-suite.git
   ```
2. Move the folder somewhere stable (e.g. `C:\Tools\pubg-performance-suite\`)
3. Right-click `PUBG-Suite.bat` → **Run as administrator**
4. Confirm UAC

For ongoing use, create a Desktop shortcut to `PUBG-Suite.bat`.

## Method 3: Develop / Customize

```bash
git clone https://github.com/Sotrax/pubg-performance-suite.git
cd pubg-performance-suite
# edit PUBG-Suite.ps1
# run via:
.\PUBG-Suite.bat
```

PowerShell scripts are unsigned. The `.bat` wrapper handles `ExecutionPolicy Bypass` for the current process scope only.

## Updating

### Via Bootstrap
Just re-run the `irm | iex` command. It wipes `%LOCALAPPDATA%\PUBGSuite\app\` and replaces with latest.

### Manual
Pull the latest from `main`:
```bash
cd path\to\pubg-performance-suite
git pull
```

State (config, history, backups) lives in `%LOCALAPPDATA%\PUBGSuite\` and is **not** touched by updates. Backups are preserved across versions.

## Uninstall

The suite makes no system-level install (no MSI, no registry entries beyond user-applied tweaks). To remove:

1. **Revert all applied tweaks** first via the suite (Tweaks tab → orange Revert buttons)
2. Delete the install folder:
   - Bootstrap install: `%LOCALAPPDATA%\PUBGSuite\app\`
   - Manual install: wherever you put it
3. Delete state:
   - `%LOCALAPPDATA%\PUBGSuite\` (config + history + logs + backups)
   - `%LOCALAPPDATA%\PUBGDiag\` (NPI stamp, if used)
4. Delete Desktop shortcut: `PUBG Performance Suite.lnk`

Auto-installed helper tools stay where they were placed:
- `C:\Tools\nvidiaProfileInspector\` (NPI)
- `C:\Tools\MultiMonitorTool\` (MMT)

Delete those folders if you don't want them anymore. Neither tool installed itself into Windows beyond what's in their respective folders.

## Requirements

- Windows 10 (1909+) or Windows 11
- PowerShell 5.1+ (built into Windows since 2016)
- Administrator rights for HKLM tweaks (HVCI, MMCSS, Services, NIC Offloads). HKCU + PUBG tweaks work non-Admin.
- Optional: NVIDIA GPU for NPI features
- Optional: PUBG installed via Steam (Epic Games version path detection not yet supported)

## ExecutionPolicy

Windows blocks unsigned PowerShell scripts by default. The suite handles this via the `.bat` wrapper:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PUBG-Suite.ps1"
```

`-ExecutionPolicy Bypass` applies to the spawned process only — your system-wide policy is **not** modified.

If you want to run the `.ps1` directly without the `.bat`:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& "C:\path\to\PUBG-Suite.ps1"
```

The `-Scope Process` makes the change ephemeral (only for that PowerShell window).
