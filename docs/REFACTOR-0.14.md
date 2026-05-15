# Refactor 0.14.0-beta — Geteiltes Profil + Tweak-Registry

Zusammenfassung des Refactors, der Suite und Diagnose auf eine gemeinsame
Konfiguration zusammenführt. Vollständige Liste siehe `CHANGELOG.md`.

## 1. Was sich geändert hat — pro Datei

### Neu: `config/PUBGProfile.psd1`
Verbindliches PUBG-Grafikprofil. Section-bewusste Struktur (`Sections` →
INI-Sektion → Key/Wert). Geladen via `Import-PowerShellDataFile`. Werte
identisch zum bisherigen Suite-Master (unverändert), zusätzlich
`bUseDynamicResolution=False` aufgenommen.

### Neu: `config/PUBGTweakRegistry.psm1`
Selbstständiges Modul, exportiert nur `Get-PUBGTweakRegistry`. Enthält 15
Tweaks mit je `Check`/`Apply`/`Revert` und allen privaten Helfern (Registry-
Snapshot, INI-Writer, Datei-Backup, NPI). Die Check/Apply/Revert-Scriptblöcke
bleiben an den Modul-Scope gebunden und funktionieren daher sowohl in der Suite
als auch standalone in der Diagnose.

### Geändert: `PUBG-Suite.ps1` (0.13.0-beta → 0.14.0-beta)
- Lädt `PUBGProfile.psd1` + importiert `PUBGTweakRegistry.psm1`.
- `$Global:Tweaks` wird per Adapter (`ConvertTo-SuiteTweak`) aus der Registry
  gebaut — die UI-Felder (`Cat`/`Name`/`Desc` ...) bleiben, dazu kommen
  `Check`/`Apply`/`Revert`.
- Grafik-Tab: `esportgfx` schreibt das Profil + `LastConfirmed*`/
  `LastUserConfirmed*`-Keys. Kein Read-only-Flag auf GameUserSettings.ini.
- `Invoke-TweakApply`/`Invoke-TweakRevert` auf das neue Modell umgestellt.
- Diag-Skript-Referenz auf `PUBG-Diagnose-v7.ps1`.

### Geändert: `diagnose/PUBG-Diagnose-v6.ps1` → `diagnose/PUBG-Diagnose-v7.ps1`
- Neue Status-Kategorien `SYSINFO/OK/TWEAK/ISSUE/MANUELL/SKIP`.
- Grafik-Checks gegen `PUBGProfile.psd1`, System-Tweak-Checks per Schleife über
  die Registry.
- MMCSS-Bugfix, Multi-Monitor via `Screen.AllScreens`, MTU → SYSINFO.
- Display-Skalierung + Timer Resolution entfernt.
- Report-only: interaktive Fix-Phase + Admin-Script-Generierung entfernt.

### Geändert: `README.md`, `docs/TROUBLESHOOTING.md`, `CHANGELOG.md`
v6→v7-Referenzen, `config/`-Ordner dokumentiert.

## 2. Tweak-Registry — Migration

Alle 15 System-/PUBG-Tweaks wurden 1:1 aus dem inline `$Global:Tweaks`-Array
ins Modul migriert. **Tweak-IDs blieben unverändert** — damit bleibt die
bestehende `history.json` gültig und der 1-Klick-Revert funktioniert weiter.

| ID            | Kategorie | migriert | Bemerkung |
|---------------|-----------|----------|-----------|
| energieplan   | Windows   | ✓ | |
| gamemode      | Windows   | ✓ | |
| gamedvr       | Windows   | ✓ | |
| mouseaccel    | Windows   | ✓ | |
| mouseslider   | Windows   | ✓ | |
| fso           | PUBG      | ✓ | |
| engineini     | PUBG      | ✓ | Engine.ini bleibt nach Apply read-only |
| fpscap        | PUBG      | ✓ | |
| defender      | Windows   | ✓ | Admin |
| hvci          | Windows   | ✓ | Admin |
| hags          | GPU       | ✓ | Admin |
| mmcss         | Windows   | ✓ | Admin · Check-Bug behoben |
| services      | Windows   | ✓ | Admin |
| nicoffload    | Network   | ✓ | Admin |
| nvprofile     | GPU       | ✓ | Revert nicht möglich (kein definierter Vorzustand) |

- **Entfernt aus `$Global:Tweaks`**: `esportgfx` — ist kein System-Tweak, wird
  über `PUBGProfile.psd1` + den Grafik-Tab verwaltet.
- **Nicht neu angelegt**: ein MTU-Tweak. 1492 zu erzwingen schadet auf modernen
  Anschlüssen; der MTU-Check ist in der Diagnose nur noch `SYSINFO`.

## 3. Migrationshinweise für Nutzer

- **Keine Aktion nötig.** Beim Update via `irm | iex` wird `config/` automatisch
  mit ausgeliefert.
- `history.json`, Backups und Logs in `%LOCALAPPDATA%\PUBGSuite\` bleiben
  unangetastet — bereits angewendete Tweaks bleiben revert-bar.
- Bei manuellem Update sicherstellen, dass der `config/`-Ordner neben
  `PUBG-Suite.ps1` liegt (Suite und Diagnose brauchen ihn).

## 4. Test-Plan (5–10 Minuten)

Auf dem Windows-Gaming-PC, nach `git pull` bzw. `irm | iex`:

1. **Suite startet** — `PUBG-Suite.bat` als Admin. Suite öffnet ohne Fehler,
   Titel zeigt `0.14.0-beta`.
2. **Tweaks-Tab** — zeigt 15 Tweaks, gruppiert nach Kategorie (Windows / GPU /
   Network / PUBG). Status-Symbole und Apply-Buttons erscheinen.
3. **Grafik-Tab** — „Status prüfen". Werte-Liste zeigt das Profil. „Competitive-
   Profil anwenden" (PUBG geschlossen!) → danach Status `OK`.
4. **Diagnose** — Diagnose-Button bzw. `PUBG-Diagnose-v7.ps1` direkt starten.
   HTML-Report öffnet sich. Prüfen:
   - Summary-Cards: `OK / TWEAK / ISSUE / MANUELL / SKIP / System-Info`.
   - Kein einziger Eintrag hat Status `INFO`.
   - Abschnitt „PUBG Settings": alle `Grafik: …`-Zeilen stehen auf `OK`
     (Akzeptanzkriterium 1 — direkt nach dem Profil-Apply aus Schritt 3).
   - `MMCSS Gaming-Profil`: wenn die Registry-Werte gesetzt sind → `OK`
     (nicht mehr fälschlich TWEAK).
   - `Display Skalierung` und `System Timer Resolution` kommen **nicht** mehr
     vor.
   - Footer nennt `PUBGProfile.psd1 v1.0` + SHA256.
5. **Tweak-Kopplung** — einen `TWEAK`-Befund aus dem Report im Tweaks-Tab der
   Suite suchen, Apply drücken, Diagnose erneut laufen lassen → Status wechselt
   auf `OK`.
6. **Multi-Monitor** — Game-Mode-Tab → Game Mode starten. Diagnose erneut:
   „Aktive Monitore" zeigt `1`. Game Mode beenden → Monitore kehren zurück.

## 5. Offene Punkte / Empfehlungen für die nächste Iteration

- **`ISSUE` wird aktuell nur von den kritischen Grafik-Keys** (V-Sync, Dynamic
  Resolution, Motion Blur, FullscreenMode) erzeugt. System-Tweaks melden
  einheitlich `TWEAK`. Das ist bewusst — falls gewünscht, könnten einzelne
  System-Tweaks (z. B. HVCI an) als `ISSUE` höher gewichtet werden.
- **`Get-RegistrySnapshot`/`Restore-RegistrySnapshot` & Co.** existieren jetzt
  doppelt: einmal in `PUBG-Suite.ps1` (für `esportgfx`) und einmal privat im
  Registry-Modul. Bewusst belassen (geringeres Risiko), könnte später
  vollständig ins Modul wandern.
- **MMCSS** ist laut Recherche 2026 nur noch ein geringer (aber harmloser)
  Gewinn — als `TWEAK` mit Impact `GERING` belassen.
- **RSS / Interrupt Moderation** sind in der Diagnose `MANUELL` (kein Suite-
  Tweak). Falls gewünscht, könnten sie als NIC-Tweaks in die Registry
  aufgenommen werden (wäre eine Erweiterung über Abschnitt 4 des Auftrags
  hinaus).
- **Game-Mode**: die Monitor-Abschaltung der Suite (MultiMonitorTool) blieb
  unverändert — sie funktioniert. Es wurde nur die *Zählung* in der Diagnose
  korrigiert. Eine CCD-API-Lösung wäre auf einem Desktop ohne internes Panel
  nicht robuster.
