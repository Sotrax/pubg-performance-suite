# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Planned
- Granularer Grafik-Tab: Einzel-Dropdowns pro Setting (Anzeigemodus, AA, Schatten, Texturen ...) als Erweiterung des neuen Grafik-Tabs
- Cross-system validation (AMD GPU / Intel CPU / Win10)
- Backup-Manager UI (browse + restore historical backups)
- Auto-update check at startup
- English UI localization
- GitHub Actions release pipeline
- Capture: comparison view (delta vs previous)

## [0.14.0-beta] - 2026-05-15
### Changed — Single Source of Truth: geteiltes Profil + Tweak-Registry

Die Suite und das Diagnose-Skript widersprachen sich: die Suite setzte
PUBG-Grafikwerte, die Diagnose meldete genau diese Werte als Problem, weil sie
gegen hartgecodete *andere* Soll-Werte prüfte. Dieser Refactor zieht beide
Komponenten auf **eine** gemeinsame Konfiguration zusammen.

**Neue Dateien**

- `config/PUBGProfile.psd1` — verbindliches PUBG-Grafikprofil (sg.*-Werte,
  Anzeigemodus, V-Sync, Motion Blur ...). Beide Komponenten laden es per
  `Import-PowerShellDataFile` (parst nur Daten, führt keinen Code aus).
- `config/PUBGTweakRegistry.psm1` — zentrale Registry aller 15 System-/PUBG-
  Tweaks mit je `Check`/`Apply`/`Revert`. Selbstständiges Modul mit eigenen
  privaten Helfern (Registry-Snapshot, INI-Writer, Datei-Backup, NPI).

**`PUBG-Suite.ps1` (0.13.0-beta → 0.14.0-beta)**

- Grafik-Tab lädt die Soll-Werte aus `PUBGProfile.psd1` statt aus einem
  hartgecodeten `$Global:EsportGfxProfile`.
- Beim Apply des Grafik-Profils werden jetzt `FullscreenMode` **+**
  `LastConfirmedFullscreenMode` **+** `PreferredFullscreenMode` geschrieben und
  `LastUserConfirmedResolutionSizeX/Y` mit der aktuellen Auflösung
  synchronisiert — so akzeptiert PUBG die Werte beim Start als „zuletzt
  bestätigt" und setzt das Profil nicht zurück. Kein Read-only-Flag auf
  GameUserSettings.ini (In-Game-Änderungen bleiben möglich).
- Tweaks-Tab rendert aus `PUBGTweakRegistry.psm1` statt aus einem inline
  `$Global:Tweaks`-Array. Bestehende Tweak-Logik wurde 1:1 ins Modul migriert,
  Duplikate konsolidiert. `Invoke-TweakApply`/`Invoke-TweakRevert` arbeiten mit
  dem neuen `Check`/`Apply`/`Revert`-Modell; History-/Snapshot-Revert bleibt.
- **Tweak-IDs unverändert** (`mmcss`, `fso`, `energieplan` ...) — bestehende
  `history.json` und damit der 1-Klick-Revert bereits angewendeter Tweaks
  bleiben gültig. Keine Migration nötig.
- Game-Mode-Tab unverändert (Monitor-Abschaltung via MultiMonitorTool
  funktioniert — siehe Diagnose-Fix unten).

**`diagnose/PUBG-Diagnose-v6.ps1` → `diagnose/PUBG-Diagnose-v7.ps1`**

- Neue, mechanisch definierte Status-Kategorien:
  `SYSINFO` (reine Identifikation) · `OK` · `TWEAK` (via Suite verbesserbar) ·
  `ISSUE` (via Suite zu beheben, wichtig) · `MANUELL` (selbst zu beheben:
  BIOS/Treiber/Windows) · `SKIP`. Kein `INFO` mehr.
- Grafik-Checks vergleichen gegen `PUBGProfile.psd1` — der alte Konflikt
  (Diagnose erwartete AA=0/ViewDist=3/Effects=2, Suite setzte 2/2/0) ist damit
  aufgelöst. Kritische Keys (V-Sync, Dynamic Resolution, Motion Blur,
  FullscreenMode) → `ISSUE` bei Abweichung, restliche → `TWEAK`.
- System-Tweak-Checks laufen über eine Schleife über die Tweak-Registry: jeder
  `TWEAK`-Befund hat damit garantiert einen Apply-Button in der Suite.
- **Bugfix MMCSS**: Check kommt jetzt aus der Registry mit robustem
  String-Vergleich — `SystemResponsiveness=10` + `NetworkThrottlingIndex` als
  `4294967295`/`-1` werden korrekt als `OK` erkannt (vorher fälschlich WARN).
- **Multi-Monitor**: Zählung via `[Windows.Forms.Screen]::AllScreens` statt
  `WmiMonitorID` — abgeklemmte/per Suite-Game-Mode deaktivierte Monitore zählen
  nicht mehr mit, der Count fällt nach dem Game-Mode korrekt auf 1.
- **Entfernt**: Display-Skalierung (zu invasiver Fix für 4K-Desktops) und
  System Timer Resolution (auf Win11 22H2+ obsolet — Timer-Resolution ist seit
  Win10 2004 per-process, globale Hints wirken nicht mehr systemweit).
- **Entfernt**: interaktive Fix-Phase + Admin-Script-Generierung. Das Skript ist
  jetzt **report-only** — alle Fixes laufen über die Suite. Damit gibt es keine
  doppelt gepflegte Fix-Logik mehr.
- HTML-Report: neue Summary-Cards (System-Info-Card bewusst dezenter), SYSINFO-
  Zeilen ausgegraut, Footer mit Profil-Version + SHA256-Hash.

**Recherche-Hinweise (geprüft, nicht ungeprüft übernommen)**

- MMCSS-Werte sind 2026 auf Win11 25H2 weiterhin gültig (Effekt modest, aber
  harmlos) — als `TWEAK` behalten.
- Globale Timer-Resolution ist auf Win11 22H2+ bestätigt obsolet → Check
  entfernt.
- `LastConfirmed*`/`LastUserConfirmed*`-Keys existieren in PUBG und werden beim
  Start geprüft → Apply schreibt sie konsequent mit.
- Die Profil-Werte sind mit dem Pro-Konsens 2025/2026 konsistent (minimale,
  vertretbare Abweichungen bei Texturen=Hoch und Sichtweite=Mittel).

**MTU**: Der MTU-Check ist von WARN+Fix auf reines `SYSINFO` (nur Wertanzeige)
zurückgestuft — 1492 zu erzwingen schadet auf modernen Kabel-/Glasfaser-
Anschlüssen leicht, ein MTU-Tweak wurde bewusst nicht angelegt.

### Migrationshinweise
- Keine Aktion nötig. Die alte `history.json` bleibt kompatibel (Tweak-IDs
  unverändert). Backups, Logs und State in `%LOCALAPPDATA%\PUBGSuite\` bleiben
  unangetastet.
- Beim Update via `irm | iex` wird der `config/`-Ordner automatisch mit
  ausgeliefert. Bei manuellem Update sicherstellen, dass `config/` neben
  `PUBG-Suite.ps1` liegt.

## [0.13.0-beta] - 2026-05-15
### Changed — Eigener "Grafik"-Tab fuer das Esport-Grafik-Profil

Das in 0.12.0 eingefuehrte `esportgfx`-Profil wurde aus der allgemeinen
Tweak-Liste herausgeloest und bekommt einen eigenen Tab. Die In-Game-Grafik
ist zu wichtig, um sie pauschal mit "Apply All" zusammen mit den System-Tweaks
anzuwenden - sie wird jetzt bewusst getrennt verwaltet.

- Neuer Tab **"Grafik"** zwischen Tweaks und Settings:
  - Status-Anzeige (OK / WARN / SKIP) des aktuellen In-Game-Grafik-Profils
  - Lesbare Auflistung aller Profil-Werte (Anzeigemodus, AA, Texturen, Schatten,
    Sichtweite, Post-Processing, Effekte, Laub, V-Sync, Motion Blur ...)
  - Eigener Button **"Competitive-Profil anwenden"** mit Bestaetigungs-Dialog
    (Hinweis: PUBG muss geschlossen sein)
  - Eigener Button **"Zuruecksetzen (Backup)"** - stellt GameUserSettings.ini
    aus dem letzten Backup wieder her, nur aktiv wenn ein Backup existiert
  - "Status pruefen"-Button zum manuellen Neuladen
- `esportgfx` wird **nicht mehr** von "Apply All" / "Apply Selected" erfasst und
  erscheint nicht mehr im Tweaks-Tab. History-/Snapshot-/Backup-System bleibt
  unveraendert (gemeinsame `Invoke-TweakApply` / `Invoke-TweakRevert`).

## [0.12.0-beta] - 2026-05-15
### Added — PUBG Esport-Grafik-Tweak (die fehlende Kernfunktion)

Bisher konfigurierte die Suite Windows, Engine.ini und den NVIDIA-Treiber - aber
**nie das eigentliche In-Game-Grafikmenue**. Nach "Apply All" blieb PUBG im
Windowed-Modus mit Ultra-Settings. Diese Luecke schliesst der neue Tweak.

- Neuer PUBG-Tweak `esportgfx` ("PUBG Esport-Grafik (Competitive-Profil)") -
  schreibt das Competitive-Profil direkt in
  `%LOCALAPPDATA%\TslGame\Saved\Config\WindowsNoEditor\GameUserSettings.ini`:
  - `[ScalabilityGroups]`: ViewDistance/AntiAliasing = Mittel (2), Texturen = Hoch (3),
    Shadow/PostProcess/Effects/Foliage = Sehr Niedrig (0), ResolutionQuality = 100
  - `[/Script/TslGame.TslGameUserSettings]`: `FullscreenMode=0` (Exklusiv-Vollbild,
    inkl. `LastConfirmedFullscreenMode`/`PreferredFullscreenMode`), `ScreenScale=100`,
    `bUseVSync=False`, `bMotionBlur=False`, `bSharpen=False`, `bSavedGraphicOption=True`
- "Balanced Visibility"-Profil: niedrige Sicht-Blocker fuer Spotting, AA/Texturen
  mittel-hoch fuer klare Distanz - basiert auf prosettings.net (67 Pro-Player)
- BattlEye-safe by design: alle Werte sind im PUBG-Grafikmenue selbst waehlbar
  (`sg.*` 0-4), keine Out-of-range-Werte, keine versteckten CVars
- Voll reversibel: Datei-Backup vor Apply, 1-Klick-Revert
- Aufloesung (`ResolutionSizeX/Y`) wird bewusst NICHT angefasst - hardware-spezifisch
- ApplyFn blockt, wenn PUBG laeuft (PUBG wuerde die Datei beim Beenden ueberschreiben)
- `Update-StatusGrid`/Reco-Engine bleiben unveraendert; der Tweak erscheint im
  Tweaks-Tab und wird von "Apply All" automatisch mit erfasst
- Versionssprung 0.11.2 -> 0.12.0 (neues Feature)

## [0.11.2-beta] - 2026-05-12
### Fixed — About-Card Hardcoded Version + veralteter Text
- Settings-Tab > About zeigte hardcoded `v1.0.0-PoC (Local Build)` - selber Bug-Klasse wie damals der Header-Label-Bug
- Fix: neues `lblAboutVersion`-Element wird beim Start dynamisch aus `$Global:Suite.Version` befuellt
- Veralteter Text "Geplant: GitHub-Release fuer Multi-User-Distribution" - das haben wir laengst. Ersetzt durch:
  - GitHub-Repo-Link
  - Aktueller `irm | iex` Update-Command direkt in der Card
  - Erweiterte Sektion: "Reversibel: 14 von 15 Tweaks", "BattlEye-safe: kein Special K, ReShade, DXVK, ban-bait Engine.ini, kein Process-Lasso auf BEService"

### Changed — History-Stat Label klarer
- Vorher: "History: 9 Eintraege - 9 Apply, 0 Revert, 0 Fehler"  →  verwirrte User weil im Tweaks-Tab "13 von 15 angewendet" steht
- Klarstellung im Label: "(Hinweis: Tweaks die schon by-default OK waren brauchten kein Apply und tauchen nicht in der History auf.)"

### Changed — README komplett ueberarbeitet (Trust-Foundation fuer Distribution)
- Neue Section "Warum diesem Tool vertrauen?" ganz oben - 3 Punkte: Open Source, vollstaendig reversibel, BattlEye-safe by design
- Klare Telemetrie-Aussage: "Keine Telemetrie, keine Cloud-Calls. Internet-Traffic nur fuer einmalige Tool-Downloads + Diagnose-Pings"
- Screenshots-Section mit 5 Slots (Dashboard, Tweaks, Game Mode, Capture, Settings) - Screenshots in `docs/screenshots/` ablegen
- Tweak-Liste aktualisiert auf 15 (war 14, HAGS dazugekommen in 0.11.0)
- Status-Footer aktualisiert auf 0.11.1

## [0.11.1-beta] - 2026-05-12
### Fixed — VBS-StatusCheck zu streng (false BAD nach erfolgreichem Apply)

User-Bug: nach Apply des "VBS + HVCI Disable"-Tweaks und Reboot zeigte der
Tweak weiter WARN/BAD - obwohl der Tweak technisch erfolgreich war. 
Diagnose mit `Get-ComputerInfo` zeigte: `DeviceGuardSmartStatus = Off`,
`SecurityServicesRunning = {0}` (nichts laeuft), `SecurityServicesConfigured = {0}`
- alles korrekt aus.

Aber: `Win32_DeviceGuard.VirtualizationBasedSecurityStatus = 2` (Running).
Das ist NICHT "VBS aktiv" sondern nur "Hypervisor-Stack geladen". 24H2 startet
den Hyper-V-Hypervisor auch wenn HVCI/CredGuard aus sind - ist UEFI/SecureBoot-
abhaengig und nicht per Registry abschaltbar. Der reine Hypervisor-Stack kostet
~1-3% SLAT-Overhead, nicht die 5-10% von HVCI/CredGuard.

**StatusFn-Hierarchie korrigiert (sowohl Tweak als auch Dashboard-Card):**
- `SecurityServicesRunning -contains 2` (HVCI) -> **BAD** (volle Penalty)
- `SecurityServicesRunning -contains 1` (CredGuard) -> **BAD**
- Nur `VirtualizationBasedSecurityStatus = 2` ohne Services -> **WARN**
  (Hypervisor laeuft noch, kleiner Overhead, vollstaendig aus nur via UEFI)
- Alles aus -> **OK**

**Dashboard-Card** differenziert jetzt: "HVCI + CredGuard aktiv" / "HVCI aktiv" /
"CredGuard aktiv" / "Hypervisor an (Services aus)" / "AUS"

**Recommendation-Engine** macht jetzt 2 separate Empfehlungen:
- Bei BAD: Tweak applieren
- Bei WARN: erklaert dass der Tweak schon gewirkt hat, der Rest UEFI-Setting

## [0.11.0-beta] - 2026-05-12
### Added — 2025/2026-Research Sprint 1 (3 evidenz-basierte Tweaks)

Nach systematischem Skeptiker-Check der Recherche-Findings ("verify before
ship") sind 2 von 5 Kandidaten als Placebo rausgeflogen (Segment Heap IFEO,
MMCSS Per-Task) - die anderen 3 sind hier mit ihren Quellen:

**Upgrade: bestehender HVCI-Tweak -> "Virtualization Security (VBS + HVCI): AUS"**
- Bisher: nur `Scenarios\HypervisorEnforcedCodeIntegrity\Enabled=0` - das deckte
  nur Memory Integrity ab. Win11 24H2 reaktiviert VBS bei Feature-Updates,
  weil der Master-Toggle weiter on stand und der Hypervisor lief
- Jetzt: ALLE 3 VBS-Komponenten + bcdedit:
  - `DeviceGuard\EnableVirtualizationBasedSecurity = 0`
  - `DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity\Enabled = 0`
  - `DeviceGuard\Scenarios\CredentialGuard\Enabled = 0`
  - `bcdedit /set hypervisorlaunchtype off` (kritisch fuer 24H2)
- StatusFn nutzt jetzt `Win32_DeviceGuard.VirtualizationBasedSecurityStatus`
  zusaetzlich zu `SecurityServicesRunning`
- Dashboard-Card differenziert: "HVCI + VBS aktiv" (BAD) / "VBS aktiv (HVCI aus)"
  (WARN) / "AUS" (OK)
- Evidenz: Toms Hardware 5-10% Gaming-Verlust mit VBS on, Neowin 2024-Retest
  bestaetigt Penalty auf aktuellen Win11-Builds, Microsoft-eigene Zahlen
  raeumen ~5% in CPU-bound Workloads ein. PUBG (240Hz CPU-bound DX11 UE4)
  ist genau das Profil mit hoechstem Gewinn.

**Neuer Tweak: Hardware-accelerated GPU Scheduling (HAGS) AN (Optional)**
- `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\HwSchMode = 2`
- Reboot erforderlich
- Default: NICHT in "Apply All" - manuell zu aktivieren
- ImpactDetail klar: "PUBG-spezifisch unklar - kein publizierter A/B-Test.
  Hauptvorteil ist DLSS-Frame-Generation, die PUBG nicht hat. UE4 hatte in
  manchen Titeln Shader-Compile-Stutter mit HAGS=ON. Aber: schadet meist
  nicht."
- Evidenz: Blur Busters Latency-Tests, NVIDIA Reflex/FG Voraussetzung -
  aber keine publizierten PUBG-spezifischen Zahlen, daher als Optional
  markiert

**Erweiterung bestehender Engine.ini-Tweak: + `r.D3D11.UseAllowTearing=1`**
- Setzt `DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING` auf Swap-Chain + `DXGI_PRESENT_ALLOW_TEARING`
  beim Present-Call - erlaubt Hardware Independent Flip auf DX11 Borderless
  wenn VSync aus
- Mechanismus offiziell von Microsoft empfohlen ("DXGI Flip Model" Dev-Blog)
  fuer niedrigste DX11-Latency
- Caveat (im Tweak dokumentiert): wirkt nur wenn VSync = OFF + Borderless
  oder Fullscreen. Bei FSE ist Tearing eh erlaubt, dann no-op. Auf
  Win11 24H2 macht DWM Independent Flip ohnehin aggressiver - auch da
  evtl. redundant. Bestcase: ein Frame DWM-Compose weniger.
- BattlEye-safe: Engine.ini ist user-writable + PUBG schreibt selbst rein,
  kein Banwave-Thread zu CVar-Edits gefunden

### Bewusst NICHT aufgenommen (nach Skeptiker-Check)
- **Segment Heap fuer TslGame.exe** (IFEO `FrontEndHeapDebugOptions=0x08`):
  Mechanismus existiert (Sebastian Schoener 2024), aber UE4 nutzt eigenen
  `FMalloc`-Allocator (TBB/Mimalloc/Binned2) und umgeht den NT-Heap im
  Hot-Path. Null Benchmark zeigt FPS-Gain bei Spielen. Placebo.
- **MMCSS `\Tasks\Games` Per-Task Subkey**: Microsoft Learn explizit:
  `GPU Priority` = "is not yet used", `SFIO Priority` = "is not used".
  Plus: Registry-Werte greifen nur wenn der Prozess
  `AvSetMmThreadCharacteristics("Games", ...)` aufruft - UE4/PUBG macht
  das nicht. Pure Placebo, denis-g klassifiziert exakt diese Tweaks als
  Snake-Oil.

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
The diagnostic backend now lives in `diagnose/PUBG-Diagnose-v7.ps1` (report-only,
shared config). Earlier standalone iterations:

- v6: Engine.ini auto-tweaks, MMCSS, NIC offloads, Multi-Monitor/RTSS/HDR checks
- v5: Correct NPI hex IDs + verification
- v4: Auto-fix loop, HTML report polish, alltagsauswirkung field, NPI auto-install
- v3: First HTML report version, 6 diagnostic sections
- v2: Plain-text diagnostic, initial PUBG-specific checks
