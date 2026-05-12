# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Planned
- Cross-system validation (AMD GPU / Intel CPU / Win10)
- Backup-Manager UI (browse + restore historical backups)
- Auto-update check at startup
- English UI localization
- GitHub Actions release pipeline

## [0.9.0-beta] - 2026-05-12
### Added — Trust Foundation
- Storage layer with JSON-based config + history + per-day file logging
- Snapshot/Revert system for 13 of 14 tweaks (registry, file, service, NIC offload state)
- Revert-Button replaces Apply-Button after successful apply
- Settings tab: "Open Logs / Open Backups / Clear History" actions
- Config persistence — MonitorPattern survives suite restart

### Added — Tweaks (14 total)
- Windows: Power Plan, Game Mode, Game DVR, Mouse Enhanced Pointer Precision, Mouse Slider
- PUBG: FSO Disable, Engine.ini (Sharpening + Streaming + Pacing), FPS Cap (Hz-based dynamic), NVIDIA Profile via NPI
- System (Admin): Defender Exclusion, HVCI Disable, MMCSS, Service Disable, NIC Offloads

### Added — UI
- Live Dashboard with 9 status cards + recommendation engine
- Game Mode tab: one-click pre/post-game prep
- Diagnose tab integrates with PUBG-Diagnose-v6.ps1 (non-interactive mode)
- Settings tab with hardware auto-detection, monitor list, MonitorPattern auto-fill
- WPF dark-theme with card-based layout

### Fixed
- GPU detection now filters integrated GPUs (was showing AMD Radeon iGPU instead of dedicated RTX)
- FPS cap now derives from primary monitor refresh rate (was hardcoded 237)
- MMCSS NetworkThrottlingIndex written via reg.exe (PS 5.1 int32-overflow workaround)
- ApplyFn returns now reflect actual failure (was silently returning $true)
- Monitor count via `[System.Windows.Forms.Screen]::AllScreens` instead of WMI cache
- Defender exclusion check no longer false-positives without admin

### Documentation
- README with install/usage/safety/architecture sections
- LICENSE (MIT)
- Per-tweak transparency: each tweak lists exact registry keys / file paths changed
- Backup files in `%LOCALAPPDATA%\PUBGSuite\backups\`

## [0.x] Pre-Suite Iterations (Diagnose-Script v2-v6)
See `diagnose/PUBG-Diagnose-v6.ps1` for the original diagnostic backend.

- v6: Engine.ini auto-tweaks, MMCSS, NIC offloads, Multi-Monitor/RTSS/HDR checks
- v5: Correct NPI hex IDs + verification
- v4: Auto-fix loop, HTML report polish, alltagsauswirkung field, NPI auto-install
- v3: First HTML report version, 6 diagnostic sections
- v2: Plain-text diagnostic, initial PUBG-specific checks
