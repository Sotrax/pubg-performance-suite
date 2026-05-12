# GitHub Repo Setup — Step-by-Step

Persönliche Anleitung wie du dieses lokale Verzeichnis nach GitHub bekommst.

## Voraussetzung

- Git for Windows installiert: https://git-scm.com/download/win
- GitHub-Account: https://github.com/signup

Beim ersten Git-Setup einmalig:
```bash
git config --global user.name "Dein Name"
git config --global user.email "deine@email.de"
```

## Schritt 1: Repo auf GitHub erstellen

1. https://github.com/new öffnen
2. **Repository Name**: `pubg-performance-suite` (oder beliebig)
3. **Description**: "PowerShell-WPF tool to diagnose and tune PUBG for competitive play. BattlEye-safe."
4. **Public** (für `irm | iex` Bootstrap muss public sein)
5. **Initialize this repository with**: NICHTS anhaken (kein README, kein LICENSE, kein .gitignore — wir bringen unsere mit)
6. "Create repository" klicken

GitHub zeigt dir dann die Setup-Commands.

## Schritt 2: Lokales Verzeichnis als Git-Repo initialisieren

PowerShell oder Git Bash in `C:\Users\User\Desktop\pubg-performance-suite\` öffnen:

```bash
cd C:\Users\User\Desktop\pubg-performance-suite

# Repo initialisieren
git init -b main

# Alles staging
git add .

# Erster Commit
git commit -m "Initial commit - PUBG Performance Suite v0.9.0-beta"

# Remote hinzufuegen (REPLACE Sotrax mit deinem GitHub-Namen!)
git remote add origin https://github.com/<DEIN-USER>/pubg-performance-suite.git

# Push
git push -u origin main
```

GitHub fragt nach Authentifizierung. Empfehlung: **GitHub CLI** (`gh auth login`) oder **Personal Access Token** mit `repo`-Scope.

## Schritt 3: Repo-Slug anpassen (nur falls Fork)

Wenn du das Repo forkst oder unter eigenem Namen weiterführst, ersetze alle Vorkommen von `Sotrax/pubg-performance-suite` durch deinen eigenen GitHub-Pfad:

```bash
# Linux/Git-Bash:
grep -rln 'Sotrax/pubg-performance-suite' . --include='*.md' --include='*.ps1' | \
  xargs sed -i 's|Sotrax/pubg-performance-suite|DEIN-USER/dein-fork-name|g'
```

Betroffene Files: `README.md`, `launch.ps1`, `docs/INSTALL.md`.

Dann committen + pushen:
```bash
git add .
git commit -m "Update repo slug for fork"
git push
```

## Schritt 4: Bootstrap-URL testen

Nach dem Push sollte folgendes funktionieren (in Admin-PowerShell auf einem anderen Rechner oder nach Suite-Deinstallation):

```powershell
irm "https://raw.githubusercontent.com/Sotrax/pubg-performance-suite/main/launch.ps1" | iex
```

Erwartung:
1. UAC-Prompt (Self-Elevation)
2. Download des `main`-Branch-ZIP
3. Extract nach `%LOCALAPPDATA%\PUBGSuite\app\`
4. Desktop-Shortcut wird angelegt
5. Suite öffnet sich automatisch

Falls Fehler: in der Konsole erscheinen Hinweise. Häufige Issues:
- 404 → Repo-Slug falsch in launch.ps1
- "Repository must be public" → Repo in GitHub Settings auf Public stellen
- Defender SmartScreen blockt → "Trotzdem ausführen"

## Schritt 5: Erstes Release erstellen (optional, aber empfohlen)

GitHub Releases erlauben ZIP-Downloads als versionierte Snapshots — sicherer für Endnutzer als immer-`main`-Branch.

1. Auf GitHub: Repo → "Releases" (rechts) → "Create a new release"
2. **Tag**: `v0.9.0-beta` (passend zur Version im Code)
3. **Title**: `PUBG Performance Suite v0.9.0-beta`
4. **Description**: Inhalt aus `CHANGELOG.md` reinkopieren
5. **Set as pre-release** ankreuzen (weil 0.9 beta)
6. "Publish release" klicken

GitHub erzeugt automatisch ein `Source code (zip)` Asset. Das `launch.ps1` lädt aktuell `main`-Branch — wenn du auf Release-basiert umstellen willst, ändere in `launch.ps1`:

```powershell
$zipUrl = "https://github.com/$RepoSlug/archive/refs/heads/$Branch.zip"
```

zu:

```powershell
# Latest release statt main-branch
$apiUrl = "https://api.github.com/repos/$RepoSlug/releases/latest"
$release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -Headers @{ 'User-Agent' = 'PUBGSuite' }
$zipUrl = $release.zipball_url
```

## Schritt 6: README-Badges live machen

Die Badges im README sind aktuell statisch. Optional kannst du dynamische Badges einbauen:

```markdown
![GitHub release](https://img.shields.io/github/v/release/Sotrax/pubg-performance-suite?include_prereleases)
![GitHub last commit](https://img.shields.io/github/last-commit/Sotrax/pubg-performance-suite)
![GitHub issues](https://img.shields.io/github/issues/Sotrax/pubg-performance-suite)
![GitHub stars](https://img.shields.io/github/stars/Sotrax/pubg-performance-suite?style=social)
```

## Schritt 7: Issue-Templates (optional)

Für sauberen Bug-Report-Workflow:

```
.github/
├── ISSUE_TEMPLATE/
│   ├── bug_report.md
│   └── feature_request.md
└── PULL_REQUEST_TEMPLATE.md
```

Kann später ergänzt werden. Für eine 0.9-Beta nicht zwingend nötig.

## Schritt 8: Updates pushen

Workflow für künftige Änderungen:

```bash
# Edit irgendwas
git status            # sehen was sich geaendert hat
git diff              # konkrete Aenderungen anzeigen
git add .             # alles staging
git commit -m "Add Audio Tweaks (Issue #3)"
git push
```

Für Releases:
1. Version in `PUBG-Suite.ps1` bump'en (`$Global:Suite.Version = '0.9.1-beta'`)
2. CHANGELOG.md updaten
3. Commit + Push
4. GitHub → Releases → "Draft a new release" → Tag `v0.9.1-beta`

## Schritt 9: Friends-Beta

Sobald das alles steht, kannst du an Freunde schicken:

> Hi, hab nen PUBG-Performance-Tool gebaut. Run das in Admin-PowerShell:
> ```powershell
> irm "https://raw.githubusercontent.com/Sotrax/pubg-performance-suite/main/launch.ps1" | iex
> ```
> Bei Bugs: Log aus `%LOCALAPPDATA%\PUBGSuite\logs\` an mich schicken.

## Wenn du dafuer kein GitHub willst

Alternative: Repo bei **Codeberg** (https://codeberg.org), **GitLab** oder **Gitea-Instanz**. Der `launch.ps1`-Mechanismus funktioniert mit jeder Plattform die `archive/refs/heads/main.zip` ausliefert (das tun alle drei).

Für `irm | iex` muss das Repo nur **public** sein und einen direkten ZIP-Download per HTTPS bieten.
