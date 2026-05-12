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

## [0.10.1-beta] - 2026-05-12
### Fixed — Capture Tab Display-Bugs nach 0.9.7-Erweiterung
- Neue Metriken (Bottleneck, CPU Busy, GPU Busy, Render Latency, Until Displayed, Click-to-Photon) zeigten beim Suite-Start "NA" obwohl die CSV-Daten existierten - Ursache: beim Start wurde der letzte History-Eintrag direkt gerendert, alte Eintraege (aus 0.9.6 und davor) hatten diese Felder schlicht nicht im JSON. Fix: wenn die CSV noch existiert wird sie beim Suite-Start neu mit `Analyze-CaptureCSV` analysiert und das frische Ergebnis angezeigt (statt der gespeicherten History-Zeile)
- Trend-Tabelle MODE-Spalte: zeigte `Mode Hardware: Legacy Flip` weil der hardcoded "Mode "-Praefix vor dem PresentMon-v2-String stand. Praefix entfernt, Mode-Spalte von 80px auf 200px verbreitert damit der volle Name nicht in die DELTA-Spalte ueberlaeuft
- Trend-Tabelle DELTA-Spalte: war neben dem Mode-Text geklebt weil Mode-Spalte zu schmal - jetzt klar getrennt
- Hauptanzeige "PRESENT MODE": defensiv `^Mode\s+` Praefix-Strip falls alte History-Daten geladen werden

### Changed — Present Mode Quality-Hierarchie verfeinert + visuell aufgewertet
Auf User-Wunsch ("Legacy Flip ist optimal - das soll auch gruen sein"):
- Neue Stufe **BEST** in der `PresentModeQuality`-Bewertung:
  - `BEST` (knallgruen `#22c55e` + `✓ OPTIMAL`-Badge): `Hardware: Independent Flip`, `Hardware: Legacy Flip` - kein DWM-Compose im Pfad
  - `OK` (normales Gruen `#4ade80`): `Hardware Composed: Flip`, `Hardware: Legacy Copy` - geringer DWM-Overhead
  - `WARN` (gelb): `Composition Atlas`
  - `BAD` (rot): `Composed Copy with GPU GDI` - ~3-5ms Latency
- Erklaerungstext unter dem Mode-Namen bekommt jetzt Severity-Farbe (gruene Toene fuer OK/BEST, gelb fuer WARN, rot fuer BAD) statt nur grau
- Trend-Tabelle MODE-Spalte: Mode-Text in der jeweiligen Severity-Farbe
- Mode-Card-Header umformuliert: "PRESENT MODE (Independent / Legacy Flip = OPTIMAL  -  Composed Copy = BAD, ~3-5ms DWM-Overhead)"
- Metriken-Expander: PRESENT MODE-Abschnitt zeigt jetzt die Hierarchie in farbig formatierten Unterzeilen statt einem Wall-of-Text-Absatz

## [0.10.0-beta] - 2026-05-12
### Changed — Dashboard- und UX-Overhaul

**Tab-Reihenfolge an User-Journey angepasst:**
- Alt: Dashboard -> Diagnose -> Capture -> Game Mode -> Tweaks -> Settings
- Neu: **Dashboard -> Tweaks -> Game Mode -> Capture -> Diagnose -> Settings**
- Reasoning: Status sehen -> direkt fixen -> Spielen vorbereiten -> Performance messen -> Tiefe-Analyse nur bei Bedarf -> Settings ganz hinten weil selten gebraucht
- Implementation: Reorder per `$ctrls.mainTabs.Items.RemoveAt/Insert` nach Window-Load statt 700-Zeilen-XAML-Block-Move

**Dashboard: 4x3 Grid komplett ausgefuellt (12 Cards statt 9)**
- 3 neue Info-Cards (Status='INFO', neutraler blauer Border):
  - **GPU**: Name der dedizierten Karte (iGPU wird gefiltert), Marketing-Praefix entfernt (`RTX 5080` statt `NVIDIA GeForce RTX 5080`)
  - **CPU**: Name mit gekuerzten Marketing-Suffixen (`Ryzen 9 7950X3D` statt `AMD Ryzen 9 7950X3D 16-Core Processor`)
  - **Display**: Hoechste aktive Refresh-Rate als Headline (`240 Hz`)
- Reihen: HVCI/Energieplan/GameDVR/Monitore - RTSS/Engine.ini/NV Profil/Defender - PUBG/GPU/CPU/Display
- Keine leeren Zellen mehr

**Empfehlungen visualisiert:**
- Alt: Ein TextBlock mit "Bla, Bla, Bla" als Liste
- Neu: Pro Befund eine eigene Card mit:
  - Severity-Icon (`⚠` rot fuer BAD-Findings, `!` gelb fuer WARN)
  - Klarer Titel + Detail-Erklaerung warum es relevant ist
  - Rechts ein **"Fix ->" Button** der direkt in den passenden Tab springt (Tweaks oder Game Mode)
- "Alles gruen"-Empty-State als gruene Bestaetigungs-Card

**Header gestrafft:**
- Subtitle "v0.9.x-beta" unter dem Logo entfernt (war doppelt mit der Titelleiste)
- Version jetzt als kompakter Badge neben dem Suite-Namen
- "X/Y OK" hat jetzt das Label "Status:" davor und ist in einem dunklen Pill-Badge eingefasst
- Refresh-Button mit Refresh-Symbol vorangestellt
- Top-Status zaehlt nur die 8 Tweak-relevanten Checks (nicht die INFO-Cards GPU/CPU/Display/PUBG)

**Footer erweitert:**
- Zeigt jetzt: Letzte Aktualisierung + letzter erfolgreich applied'er Tweak mit Zeitstempel (z.B. `Status: 19:14:30   |   Letzter Apply: engineini (16:15)`)
- "Letzte Aktualisierung"-Subtitle auch oben im Dashboard rechts neben "Live Status"-Header

## [0.9.9-beta] - 2026-05-12
### Fixed — Diagnose-Tab "PUBG-Diagnose-v6.ps1 nicht gefunden"
- DiagScript-Pfad war hardcoded auf `$env:USERPROFILE\Desktop\PUBG-Diagnose-v6.ps1` - das ist die Pre-Bootstrap-Annahme aus den ersten Suite-Iterationen
- Bootstrap (`launch.ps1`) entpackt das Repo nach `%LOCALAPPDATA%\PUBGSuite\app\` mit Sub-Folder `diagnose\PUBG-Diagnose-v6.ps1` - die Suite hat dort nie reingeguckt, obwohl das Script Teil der Installation ist
- Fix: DiagScript zeigt jetzt fest auf `Join-Path $PSScriptRoot 'diagnose\PUBG-Diagnose-v6.ps1'`. Das funktioniert in beiden Layouts (Repo-Dev-Run + Bootstrap-Install) ohne Such-Logik
- Settings-Tab zeigt den Pfad + Status `[OK]` oder `[FEHLT - irm|iex neu ausfuehren]`
- Bei Klick auf "Run Full Diagnose" mit fehlendem Script: klare Fehlermeldung mit exaktem `irm | iex` Command zum Reparieren

### Fixed — history.json Verschachtelung (selber Bug wie damals captures.json)
- `history.json` wurde bei jedem `Add-HistoryEntry` eine Ebene tiefer verschachtelt: `[{value: [{value: [{value: [...], Count: N}, ...], Count: N}, ...]}]`
- Ursache: `$entries | ConvertTo-Json` (Pipeline) + `Get-Content | ConvertFrom-Json` Roundtrip - PS 5.1 unwrappt Arrays mit 1 Element zu PSCustomObject, beim naechsten Save wird das wieder gewrappt
- Konsequenz: `Get-LastSnapshot` haette irgendwann nicht mehr den passenden Snapshot fuer Revert gefunden, weil die echten Eintraege immer tiefer in `{value: ...}`-Wrappern lagen
- Fix: `ConvertTo-Json -InputObject` (kein Pipeline) + manual `[`/`]` Wrap bei size=1, analog zur captures.json-Fix in 0.9.5-beta
- Recovery: `_Flatten-HistoryEntries` Helper unwrappt rekursiv alle `{value, Count}` Wrapper beim Lesen - alte verschachtelte history.json wird automatisch repariert

## [0.9.8-beta] - 2026-05-12
### Fixed — Bug-Bash nach User-Feedback "tweaks fehlen jedes mal nach Apply"

**Critical (Engine.ini Tweaks "fehlen" trotz erfolgreichem Apply):**
- PUBG ueberschreibt Engine.ini beim naechsten Spielstart/Beendigung mit seinen eigenen Default-Werten - alle unsere Performance-Tweaks waren weg, StatusFn zeigte deshalb dauerhaft WARN
- Beweis im Repo: `Engine.ini.bak_2026-05-12_154507_902` enthielt unsere Tweaks vollstaendig, aber die Live-`Engine.ini` (LastWrite 16:01) war komplett ohne Tweaks zurueck im PUBG-Default
- Fix: Engine.ini nach erfolgreichem Apply wird auf `FileAttributes.ReadOnly` gesetzt - PUBG kann sie nicht mehr ueberschreiben. Update-IniValue erkennt ReadOnly aus vorigem Apply und macht die Datei kurz writable, schreibt, setzt das Flag wieder
- RevertFn entfernt ReadOnly bevor das Backup zurueck-kopiert wird
- Dashboard zeigt jetzt "Tweaks drin (geschuetzt)" wenn ReadOnly aktiv ist

**Critical (MMCSS Tweak zeigt dauerhaft WARN trotz Apply):**
- `NetworkThrottlingIndex` wird als `REG_DWORD = 0xFFFFFFFF` geschrieben, kommt aber je nach PS-Version mal als Int32 `-1` und mal als String/Int64 `4294967295` zurueck
- Der bisherige Vergleich `$n -eq -1 -or $n -eq 0xFFFFFFFF -or $n -eq [int32]::MaxValue` schlug bei `4294967295 -eq 0xFFFFFFFF` fehl (PS 5.1 Typ-Quirk)
- Fix: String-Cast `"$n"` und Vergleich gegen '`-1`' / '`4294967295`' deckt beide Repraesentationen ab

### Impact-Doku ergaenzt
- Engine.ini-Tweak: Impact von 'KEIN' auf 'GERING' angehoben + ImpactDetail erklaert dass ReadOnly bedeutet "PUBG-Menue-'Reset to default' fuer Render-Settings funktioniert bis zum Revert nicht"

## [0.9.7-beta] - 2026-05-12
### Added — Capture Tab: Mehr Metriken + Erklaerungen
- **Bottleneck-Analyse**: CPU-Bound / GPU-Bound / Balanced aus `MsCPUBusy` vs `MsGPUBusy`
- **CPU Busy / GPU Busy** (ms pro Frame) - zeigt direkt wer das FPS-Budget verbraucht
- **Render Latency** (`MsRenderPresentLatency`) - Render-Start bis Present, farbcodiert (gruen &lt; 8ms / gelb &lt; 16ms / rot)
- **Until Displayed** (`MsUntilDisplayed`) - Frame-to-Photon Zeit bis Pixel wirklich am Monitor
- **Click-to-Photon** (`MsClickToPhotonLatency`) - End-to-End-Latency (nur mit Reflex-Support, meist NA in PUBG)
- **Stability Score** als Sub-Label unter StdDev: "Stability X% (sehr ruhig/ok/sichtbare Schwankung/unrund)"
- **Present Mode Sub-Erklaerung**: Direkt unter dem Mode-Namen wird der Mode in Klartext erklaert (z.B. "Hardware: Legacy Flip - niedrige Latency, kein DWM")
- **Metriken-Expander**: Aufklappbarer Abschnitt mit Klartext-Erklaerung jeder Metrik - was ist STDDEV, was bedeutet 1% Low, warum ist Mode 5 schlecht etc.

### Fixed
- Mode-Label-Anzeige: PresentMon v2 schreibt String-Namen ("Hardware: Legacy Flip") statt numerischer Codes ("1"/"5"). Wildcard-Matching im Analyse-Code erkennt jetzt alle Mode-Varianten korrekt (Independent Flip, Legacy Flip, Composed Flip, Legacy Copy, Composed Copy, Composition Atlas)
- StdDev-Karte zeigt jetzt klar dass es um Frame-Pacing geht (Sub-Title "Frame Pacing" + Stability-%-Score) - statt nackter ms-Zahl ohne Kontext

## [0.9.6-beta] - 2026-05-12
### Fixed — Self-Review Bug-Cycle

**Critical (Data-Loss + Crashes):**
- `Update-IniValue`: hatte keinen `-ErrorAction Stop` auf Get-Content. Bei Read-Fehler (Permission, File-Lock) wuerde `$null` an Set-Content uebergeben und Engine.ini/GameUserSettings.ini mit leerem Content ueberschreiben. Jetzt: try/catch, Null-Check, Size-Sanity-Check vor Write
- `Update-IniValue`: Backup-Filename nutzte script-scope `$timestamp` (frozen at load). Same-day re-runs ueberschrieben sich gegenseitig. Jetzt: per-call Sub-Sekunden-Timestamp
- NPI-Tweak rief `Get-NPIPath`/`Install-NPIFromGitHub`/`Invoke-NPIPubgProfile` auf, die nur in v6-Diagnose definiert waren - in der Suite undefined. NPI-Apply war stillschweigend kaputt seit 0.9.4. Funktionen jetzt direkt in Suite portiert
- Capture-State `Start-Process -PassThru` koennte $null zurueckgeben (UAC/Permission-Fall). State Machine bleibt dann ewig in 'capturing' haengen weil HasExited-Check auf $null wirft. Jetzt: explizite Null-Pruefung mit Exception-Throw

**Likely Bugs:**
- `$args` als Variablen-Name in DispatcherTimer-Scriptblock (PowerShell-Automatic-Variable). Umbenannt zu `$pmArgs`
- `Start-GameMode` RTSS/Background-Kill: `$rtss.Count` und `$p.Count` auf einzelnem Get-Process-Resultat - Process-Objekt hat keine .Count-Property, gibt $null. Jetzt: `@()` Wrapping konsistent
- `Install-MMT`: kein try/catch um Invoke-WebRequest/Expand-Archive. Bei 404/Corruption gibt Funktion einen Pfad zurueck der nicht existiert; Caller vertraut blind. Jetzt: vollstaendiger try/catch + Pfad-Verify am Ende
- `Install-PresentMonFromGitHub`: kein Partial-Download-Cleanup, keine Size-Validation. Truncated EXE wuerde Get-PresentMonPath finden und verbinden. Jetzt: Download in TEMP, Size-Vergleich gegen GitHub-API-Asset-Metadata, dann Move zu Target. Bei Fail: TEMP-Cleanup

**Resource Leaks:**
- DispatcherTimer wurde bei Window-Close nicht gestoppt. PresentMon-Process koennte als Orphan weiterlaufen. Jetzt: `Add_Closing`-Handler ruft Cleanup-CapState

## [0.9.5-beta] - 2026-05-12
### Fixed — Critical Capture-History Corruption
- captures.json wurde mit jeder neuen Messung tiefer verschachtelt ({value: {value: ...}}) statt flacher Array-Liste
- Ursache: PS 5.1 ConvertTo-Json unwrappt Pipeline-Arrays mit 1 Element zu Object; nachfolgende Re-Reads wrappten erneut
- Fix: ConvertTo-Json -InputObject statt Pipeline; bei size=1 manuell '[' und ']' wrappen
- Fix: Get-CaptureHistory hat jetzt _Flatten-CaptureEntries Helper der alte verschachtelte Daten beim Lesen automatisch unwrappt -> verlorene Eintraege werden recovered

### Added
- "Rebuild from CSVs" Button im Capture-Tab: scannt captures\ Ordner, analysiert alle CSV-Dateien neu, rebuildet captures.json from scratch -> Recovery-Option falls History korrupt

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
