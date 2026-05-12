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
- Capture: comparison view (delta vs previous)

## [0.9.4-beta] - 2026-05-12
### Added — Tweaks-Tab UX
- Filter-Buttons: "Alle (X)" / "Offen (X)" / "Angewendet (X)" - aktiver Filter visuell markiert
- Default-Filter ist "Offen" beim Suite-Start - zeigt sofort was zu tun ist
- Apply-Resultat (Apply Selected / Apply All / per-Row Apply): MessageBox listet jetzt namentlich was angewendet wurde und was gefehlt hat
- Persistente "Letzte Apply-Session"-Zeile unter den Info-Statistiken bleibt sichtbar bis zum nächsten Tab-Wechsel
- "Apply All" Bestätigungs-Dialog listet vor der Aktion alle zu applizierenden Tweaks auf
- Empty-State: Wenn alle Tweaks OK sind und Filter "Offen" gewählt → grüner Hinweis "+ Alle Tweaks angewendet"

### Improved
- Status-Berechnung pro Tab-Update einmalig in $tweakStatuses Cache (vermeidet n+1-Aufrufe der StatusFn)

## [0.9.3-beta] - 2026-05-12
### Fixed
- Header-Version war seit Anfang hardcoded auf "v1.0.0-PoC" im XAML statt aus $Global:Suite.Version gelesen
- WindowTitle bekommt jetzt auch Version-Suffix
- Visible bug der bei jeder Version-Bump-Aktion seit 0.9.0 unsichtbar war

## [0.9.2-beta] - 2026-05-12
### Fixed
- Capture-Tab: Timer-Tick-Fehler bei JSON-Date-Deserialisierung (CaptureTime kam teils als DateTime statt String zurueck → .Substring crashte)
- Capture-Tab: defensive Null-Checks in Update-CapHistory; Row-Render-Fehler greppen jetzt nur die einzelne Zeile, nicht die ganze Trend-Tabelle
- Format-CapTimeShort Helper: konvertiert robust egal welche Form (String/DateTime/null)

### Added — Capture-Tab Polish
- Trend-Tabelle: Zeilen sind jetzt klickbar - öffnet die jeweilige CSV in Notepad
- Trend-Tabelle: Hover-Effekt (Background ändert sich)
- Neue Spalte "DELTA" - Avg-FPS-Differenz gegen die älteste angezeigte Messung (gruen/rot)
- Neuer Button "Compare to previous" - zeigt Side-by-Side-Vergleich der letzten zwei Messungen mit prozentualer Delta
- Neuer Button "Clear history" - leert captures.json (CSVs bleiben auf Disk)

## [0.9.1-beta] - 2026-05-12
### Added — Performance Capture Tab
- New "Capture" tab between Diagnose and Game Mode
- Intel PresentMon auto-install from GitHub Releases (passive ETW, no DLL hook)
- One-click 60-second capture with 10-second pre-countdown for Alt-Tab
- Live phase indicator: countdown -> capturing -> analyzing
- Big KPI cards: Avg FPS / 1% Low / 0.1% Low / StdDev / PresentMode / G-Sync / Stutter
- Color-coded PresentMode quality (Mode 1/3/4 = OK, Mode 5/6 = BAD)
- Captures saved to `%LOCALAPPDATA%\PUBGSuite\captures\capture_<timestamp>.csv`
- Persistent history in `captures.json` (last 50)
- Trend table: last 8 captures with Date/Avg/1%/0.1%/StdDev/Mode side-by-side
- "Open last CSV" / "Open Captures Folder" actions

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
