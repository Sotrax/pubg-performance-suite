# PUBG Performance Suite

> Windows-native PowerShell-WPF tool to diagnose and tune PUBG for competitive play. BattlEye-safe, fully reversible, no external dependencies beyond auto-installed open-source helpers.

![Version](https://img.shields.io/badge/version-0.9.0--beta-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![Windows](https://img.shields.io/badge/Windows-10%2F11-blue)
![BattlEye](https://img.shields.io/badge/BattlEye-safe-brightgreen)
![License](https://img.shields.io/badge/license-MIT-green)

## What it does

Modern PUBG runs into the **same five problems** on most setups: HVCI overhead, wrong present mode (RTSS + multi-monitor), missing Engine.ini tweaks, default NVIDIA driver profile, and DPI/Game Bar misconfigurations.

This suite **detects all of them live**, lets you **apply fixes individually** with a **revert button per tweak**, and provides a **one-click "Game Mode"** that disables secondary monitors + kills overlay processes before launch.

## Screenshots

> Coming soon — placeholders.

```
TODO: docs/screenshots/dashboard.png
TODO: docs/screenshots/tweaks.png
TODO: docs/screenshots/game-mode.png
```

## Features

- **Live Dashboard** — HVCI, Power Plan, GameDVR, Monitors, RTSS, Engine.ini, NVIDIA Profile, Defender exclusion, PUBG state
- **14 Tweaks** with per-tweak Apply / Revert — all reversible via snapshot system
  - Windows: Power Plan, Game Mode, Game DVR, Mouse 1:1 Mapping (Speed + Slider)
  - PUBG: FSO Disable (TslGame.exe), Engine.ini (Sharpening + Streaming + Pacing), FPS Cap (auto-Hz-based), NVIDIA Profile (via NPI auto-install)
  - System: Defender Exclusion, HVCI Disable, MMCSS, Service Disable, NIC Offloads
- **Game Mode** — one-click pre-game prep
  - Disables secondary monitors via MultiMonitorTool (auto-installed)
  - Kills RTSS / RivaTuner (forces PresentMode 5 → 1)
  - Closes background apps (Chrome, Spotify, Battle.net, Epic, OBS — Discord stays for voice)
  - Optional: launches PUBG via Steam URI
- **Auto-Detection**
  - Primary monitor refresh rate → dynamic FPS cap (Hz − 3)
  - PUBG Steam install path via library manifest
  - Dedicated GPU (filters iGPU)
  - "Detect & Fill" to auto-populate monitor regex
- **Diagnose** — runs the full v6 diagnostic engine in non-interactive mode, generates an HTML report
- **Transparent**
  - Each tweak shows exact registry keys / file paths changed
  - All actions logged to `%LOCALAPPDATA%\PUBGSuite\logs\<date>.log`
  - Pre-change snapshots in `history.json`
  - File-tweak backups in `backups\` folder

## Safety

**Intentionally excluded** to avoid BattlEye ban-bait:
- ❌ Special K (DLL injection)
- ❌ ReShade
- ❌ DXVK / Vulkan-Layer
- ❌ Engine.ini `r.Fog=0`, `r.Atmosphere=0`, sub-UI shadow values
- ❌ Negative `r.MipMapLODBias`
- ❌ Process Lasso affinity on `BEService.exe`

Every tweak in the suite either modifies user-controllable UI settings, files in the user's own AppData, or system-level Windows settings that don't touch the game process.

## Requirements

- Windows 10 (1909+) or Windows 11
- PowerShell 5.1 (built-in on modern Windows)
- Administrator rights (for HKLM tweaks; non-Admin still works for HKCU + PUBG tweaks)
- Optional: NVIDIA GPU for NPI profile features

## Installation

### One-line install (recommended)

In an Administrator PowerShell:

```powershell
irm "https://raw.githubusercontent.com/<YOUR-USERNAME>/pubg-performance-suite/main/launch.ps1" | iex
```

This downloads, installs, and launches the suite. Repeat the command anytime to update.

> Replace `<YOUR-USERNAME>` with the actual GitHub username after pushing.

### Manual install

1. Download the latest [release ZIP](https://github.com/<YOUR-USERNAME>/pubg-performance-suite/releases) or clone the repo
2. Extract to a folder of your choice
3. Right-click `PUBG-Suite.bat` → **Run as administrator**

## Quick Start

1. **Launch via `PUBG-Suite.bat`** (the `.ps1` directly won't self-elevate)
2. **Dashboard tab** — see your current state at a glance
3. **Tweaks tab** — pick what to apply
   - Click `Apply` on individual rows, or
   - Use checkboxes + `Apply Selected`, or
   - `Apply All` (with confirmation)
4. **Game Mode tab** — before each PUBG session:
   - Click `START GAME MODE` → monitors switch, RTSS dies, background apps close
   - Play your match
   - Click `EXIT GAME MODE` → everything reverts
5. **Settings tab** — adjust monitor pattern, view logs/backups, see detected hardware

## How Revert works

Every Apply captures a **pre-change snapshot** (registry values, file copies, service states) stored in `history.json`. The Apply button transforms into an orange **Revert** button after success. Clicking it restores the pre-Apply state.

Revert is supported for **13 of 14** tweaks (NVIDIA profile uses NPI's own reset — currently no automated revert).

## Architecture

```
pubg-performance-suite/
├── PUBG-Suite.ps1           # Main GUI (WPF, ~2100 lines)
├── PUBG-Suite.bat           # Self-elevating launcher
├── launch.ps1               # GitHub bootstrap (irm | iex target)
├── diagnose/
│   └── PUBG-Diagnose-v6.ps1 # Full diagnostic backend, generates HTML report
├── helpers/                 # Optional standalone helpers
│   ├── Nur-OLED.ps1
│   ├── Alle-Monitore.ps1
│   └── PUBG-Capture.bat
└── docs/
    ├── TWEAKS.md            # Full reference of all 14 tweaks
    ├── INSTALL.md           # Detailed install/uninstall
    └── TROUBLESHOOTING.md
```

## State storage

All user data stays local in `%LOCALAPPDATA%\PUBGSuite\`:
- `config.json` — user preferences (monitor pattern, etc.)
- `history.json` — apply/revert history with snapshots
- `logs\YYYY-MM-DD.log` — daily action log
- `backups\` — pre-change file copies

Nothing is sent externally except:
- One-time download of NPI from `github.com/Orbmu2k/nvidiaProfileInspector` (only if you opt in)
- One-time download of MultiMonitorTool from `nirsoft.net` (only if Game Mode is used)
- ICMP ping tests to `1.1.1.1` / `8.8.8.8` / `steamcommunity.com` during diagnose

## Contributing

PRs welcome. Areas where help is appreciated:
- Testing on AMD GPU / Intel CPU / Win10 systems
- Additional tweaks (audio enhancements, Steam launch options, etc.)
- Translations (currently German UI strings; English would be next)

## License

MIT — see [LICENSE](LICENSE)

## Acknowledgments

- [Orbmu2k/nvidiaProfileInspector](https://github.com/Orbmu2k/nvidiaProfileInspector) — NPI for NVIDIA driver profile manipulation
- [NirSoft MultiMonitorTool](https://www.nirsoft.net/utils/multi_monitor_tool.html) — monitor enable/disable via CLI
- [Intel GameTechDev/PresentMon](https://github.com/GameTechDev/PresentMon) — ETW-based frame capture
- [valleyofdoom/TimerResolution](https://github.com/valleyofdoom/TimerResolution) — referenced for timer-resolution advice
- Community wisdom from r/PUBATTLEGROUNDS, BlurBusters Forum, and competitive guides

---

**Status**: Beta `0.9.0` — feature-complete for single-user workflow, validated on Win11 25H2 + RTX 5080 + Ryzen 7950X3D. Needs cross-setup testing on AMD GPU / Intel CPU / Win10 systems before 1.0.
