# Troubleshooting

## Suite launches but "Admin: NEIN" badge stays red

The `.bat` self-elevation didn't work. Causes:

1. **UAC set to "Never notify"** — Windows silently fails the elevation request. Either raise UAC level (Settings → Search "uac") or right-click `PUBG-Suite.bat` → "Run as administrator".
2. **You ran `PUBG-Suite.ps1` directly** instead of via the `.bat`. The `.ps1` doesn't self-elevate. Always launch via `.bat` or via the Desktop shortcut.
3. **Group policy restriction** — corporate machines may block UAC elevation. Use a personal machine.

## "Tweaks fehlen" stays WARN after Apply

1. Check the daily log in `%LOCALAPPDATA%\PUBGSuite\logs\<date>.log` for the actual error
2. For Engine.ini / GameUserSettings.ini: PUBG might be running and locking the file. Close PUBG completely, retry.
3. For HKLM tweaks (HVCI, MMCSS, NIC Offloads, Services): Suite needs Admin. Check the badge.

## Game Mode disables wrong monitor

The MonitorPattern regex doesn't match your secondary monitors' names.

**Fix**: Settings tab → "Detect & Fill" button auto-generates a pattern from your current Primary/Secondary setup. If you don't have a Primary set:
1. Windows Settings → System → Display → click your main gaming monitor → check "Make this my main display"
2. Suite → Settings → "Detect & Fill" again
3. Pattern should now correctly identify your secondaries

## MultiMonitorTool / NPI download fails

- **Firewall block** — Defender SmartScreen sometimes flags NirSoft tools as heuristic risk (false positive)
- **Manual download**:
  - MMT: https://www.nirsoft.net/utils/multi_monitor_tool.html → extract `MultiMonitorTool.exe` to `C:\Tools\MultiMonitorTool\`
  - NPI: https://github.com/Orbmu2k/nvidiaProfileInspector/releases → extract `nvidiaProfileInspector.exe` to `C:\Tools\nvidiaProfileInspector\`

## NPI applies but values don't appear in NVIDIA Control Panel / NVIDIA App

The new NVIDIA App and old Control Panel sometimes display the same setting differently. The values ARE in the driver profile DB. Verify by opening NPI directly:
1. Run `C:\Tools\nvidiaProfileInspector\nvidiaProfileInspector.exe`
2. Profiles dropdown → "PLAYERUNKNOWN'S BATTLEGROUNDS"
3. Check the 6 settings the suite writes (Power Mgmt, Low Latency, etc.)

## PUBG still in PresentMode 5 (Composed Copy) after all tweaks

Three independent factors force Mode 5:
1. **RTSS overlay** — Use Game Mode tab (kills RTSS) or quit RivaTuner Statistics Server entirely
2. **Multi-Monitor** — Game Mode tab disables secondaries via MMT
3. **PUBG's UE4 build** — may not support Hardware Independent Flip at all in current version

If all of (1) and (2) are addressed and you still see Mode 5: it's PUBG-structural and not fixable via user settings. Mode 1 (Hardware Legacy Flip) is the realistic best case in that scenario.

To verify which mode you're in, run `PUBG-Capture.bat` (in `helpers/`) — it uses Intel's PresentMon to capture without injecting overlays.

## Revert button doesn't appear after Apply

- The tweak doesn't have a `RevertFn` implemented (currently: NPI profile)
- The Apply failed silently before history was written — check logs
- History was manually cleared via Settings tab

Manual revert is always possible via the `.bak_<timestamp>` files in `%LOCALAPPDATA%\PUBGSuite\backups\`.

## Suite crashes on startup

1. Check PowerShell version: `$PSVersionTable.PSVersion` — must be 5.1 or higher
2. Re-encode the .ps1 to UTF-8 with BOM if you edited it manually:
   ```powershell
   $p = 'C:\path\to\PUBG-Suite.ps1'
   $c = [System.IO.File]::ReadAllText($p, [System.Text.UTF8Encoding]::new($false))
   [System.IO.File]::WriteAllText($p, $c, [System.Text.UTF8Encoding]::new($true))
   ```
   Without BOM, PowerShell 5.1 misreads non-ASCII characters (umlauts in error messages) and breaks parsing.

## "Run Full Diagnose" button does nothing

The Diagnose button looks for `PUBG-Diagnose-v6.ps1` on the Desktop. After install via `launch.ps1`, the file is in `%LOCALAPPDATA%\PUBGSuite\app\diagnose\PUBG-Diagnose-v6.ps1`.

**Future fix**: the suite will resolve this path automatically. For now: copy `diagnose\PUBG-Diagnose-v6.ps1` to your Desktop, or edit `$Global:Suite.DiagScript` in PUBG-Suite.ps1 to point at the right location.

## Reporting bugs

When opening an issue please include:
- Output of: `Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsArchitecture`
- Suite version (top of Dashboard)
- Admin: JA/NEIN status
- Relevant section of `%LOCALAPPDATA%\PUBGSuite\logs\<today>.log`
- Screenshot of the issue if UI-related
