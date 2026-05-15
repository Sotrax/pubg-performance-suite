# Tweak Reference

Complete list of all tweaks the suite applies, what they change, and the everyday-life impact.

Each tweak has a **Revert** function unless noted. Backups for file-based tweaks live in `%LOCALAPPDATA%\PUBGSuite\backups\`. Registry/service snapshots live in `history.json`.

## Windows Tweaks (5)

### 1. Energieplan: Hoechstleistung
- **What**: Switches active power plan to Windows' "High Performance" GUID
- **Where**: `powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`
- **Impact**: GERING — ~5W more idle power consumption on desktop. On Ryzen 7000+ CPUs the boost behavior is mostly identical to Balanced anyway.
- **Reversible**: ✓ (restores pre-Apply plan GUID)

### 2. Game Mode: AN
- **What**: Enables Windows Game Mode
- **Where**: `HKCU:\Software\Microsoft\GameBar\AutoGameModeEnabled = 1`
- **Impact**: KEIN
- **Reversible**: ✓

### 3. Xbox Game DVR: AUS
- **What**: Disables Xbox background recording
- **Where**: `HKCU:\System\GameConfigStore\GameDVR_Enabled = 0`
- **Impact**: KEIN — recording still possible via Win+Alt+R if needed
- **Reversible**: ✓

### 4. Mouse: Enhanced Pointer Precision AUS
- **What**: Disables Windows mouse acceleration
- **Where**: `HKCU:\Control Panel\Mouse\` — `MouseSpeed=0`, `MouseThreshold1=0`, `MouseThreshold2=0`
- **Impact**: KEIN
- **Reversible**: ✓ (restores Windows defaults: Speed=1, T1=6, T2=10)

### 5. Mouse: Slider Mitte (6/11)
- **What**: Sets pointer speed slider to exact middle for 1:1 DPI mapping
- **Where**: `HKCU:\Control Panel\Mouse\MouseSensitivity = 10`
- **Impact**: KEIN
- **Reversible**: ✓

## PUBG Tweaks (5)

### 6. Vollbildoptimierungen TslGame.exe: AUS
- **What**: Disables Windows Fullscreen Optimizations for PUBG executable
- **Where**: `HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers`
  - Value: `<full-path>\TslGame.exe` = `"~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE"`
  - PUBG path auto-detected via Steam `libraryfolders.vdf`
- **Impact**: KEIN — minor Alt-Tab speed difference, Auto-HDR off for PUBG (not desired anyway)
- **Reversible**: ✓

### 7. Engine.ini Tweaks (Sharpening + Streaming + Pacing)
- **What**: Adds BattlEye-safe UE4 cvars to PUBG's Engine.ini
- **Where**: `%LOCALAPPDATA%\TslGame\Saved\Config\WindowsNoEditor\Engine.ini`
- **Values applied**:
  - `[SystemSettings]`
    - `r.Tonemapper.Sharpen = 0.7` — Spotting clarity on distance
    - `r.OneFrameThreadLag = 0` — Frame pacing
    - `r.FinishCurrentFrame = 0` — Frame pacing
    - `r.GTSyncType = 1` — Smoother frametimes
  - `[/Script/Engine.RendererSettings]`
    - `r.Streaming.PoolSize = 4096` — More VRAM for texture streaming
    - `r.Streaming.HLODStrategy = 2` — Better LOD streaming
    - `r.Streaming.FramesForFullUpdate = 1` — Faster streaming updates
- **Impact**: KEIN
- **Reversible**: ✓ (full file backup before write)

### 8. PUBG FPS-Cap (Monitor-Hz minus 3)
- **What**: Sets in-game FPS cap dynamically based on primary monitor refresh rate
- **Where**: `%LOCALAPPDATA%\TslGame\Saved\Config\WindowsNoEditor\GameUserSettings.ini` — `FrameRateLimit`
- **Examples**: 240Hz → 237, 165Hz → 162, 144Hz → 141, 360Hz → 357
- **Impact**: KEIN — keeps frames inside G-Sync window for Reflex pipeline
- **Reversible**: ✓ (full file backup before write)

### 9. NVIDIA PUBG-Profil (via NPI)
- **What**: Sets 6 driver-level settings for PUBG via NVIDIA Profile Inspector
- **Tool**: Auto-installs NPI from `github.com/Orbmu2k/nvidiaProfileInspector` to `C:\Tools\nvidiaProfileInspector\`
- **Profile**: `PLAYERUNKNOWN'S BATTLEGROUNDS`
- **Settings applied**:
  - Power Management Mode = Prefer Maximum Performance
  - Vertical Sync = Force OFF
  - Texture Filtering Quality = High Performance
  - Threaded Optimization = ON
  - Low Latency Mode = Ultra (Reflex-equivalent driver-side)
  - Frame Rate Limiter v3 = 237 FPS
  - Antialiasing Mode = Application Controlled
- **Stamp**: `%LOCALAPPDATA%\PUBGDiag\npi-applied.stamp` — 60-day cache before re-apply prompt
- **Impact**: KEIN
- **Reversible**: ⚠ — currently no automated revert; manually via NPI GUI → "Restore profile defaults"

### 10. PUBG Esport-Grafik (Competitive-Profil)
- **What**: Writes PUBG's in-game graphics menu to the "Balanced Visibility" competitive profile
- **Where**: `%LOCALAPPDATA%\TslGame\Saved\Config\WindowsNoEditor\GameUserSettings.ini`
- **Values applied**:
  - `[ScalabilityGroups]`
    - `sg.ResolutionQuality = 100` — full render scale
    - `sg.ViewDistanceQuality = 2` (Medium) — clean distant terrain
    - `sg.AntiAliasingQuality = 2` (Medium) — clean edges for long-range spotting
    - `sg.ShadowQuality = 0` (Very Low) — enemy shadows still render
    - `sg.PostProcessQuality = 0` (Very Low) — no bloom/haze washing out enemies
    - `sg.TextureQuality = 3` (High) — spotting clarity, near-zero FPS cost
    - `sg.EffectsQuality = 0` (Very Low) — less screen clutter
    - `sg.FoliageQuality = 0` (Very Low) — prone enemies far easier to see
  - `[/Script/TslGame.TslGameUserSettings]`
    - `ScreenScale = 100` — no upscaling blur
    - `FullscreenMode = 0` / `LastConfirmedFullscreenMode = 0` / `PreferredFullscreenMode = 0` — exclusive fullscreen, lowest latency
    - `bUseVSync = False` — no V-Sync input lag
    - `bMotionBlur = False` — motion blur off
    - `bSharpen = False` — in-game sharpen off (the Engine.ini tweak already sharpens)
    - `bSavedGraphicOption = True` — PUBG treats values as user-chosen, no auto-detect reset
- **sg.* scale**: 0 = Very Low, 1 = Low, 2 = Medium, 3 = High, 4 = Ultra
- **Not changed**: resolution (`ResolutionSizeX/Y`) is left untouched — it is hardware/monitor specific
- **BattlEye**: safe — every value is selectable in PUBG's own graphics menu; no out-of-range values, no hidden console vars
- **Note**: PUBG must be closed when applying — it rewrites `GameUserSettings.ini` on exit and would overwrite the changes
- **Impact**: MITTEL — lowers in-game visual fidelity (intentional competitive trade-off)
- **Reversible**: ✓ (full file backup before write)

## System Tweaks (5, require Admin)

### 11. Defender Exclusion fuer PUBG-Ordner
- **What**: Adds PUBG install folder to Windows Defender real-time scan exclusions
- **Where**: `Add-MpPreference -ExclusionPath <PUBG-Pfad>`
- **Impact**: GERING — Defender stops scanning PUBG folder. Risk only if mods/cheats land there (irrelevant for vanilla Steam install).
- **Reversible**: ✓ (only removes exclusions that didn't exist pre-Apply)

### 12. Memory Integrity (HVCI): AUS
- **What**: Disables Hypervisor-Enforced Code Integrity
- **Where**: `HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity\Enabled = 0`
- **Impact**: MITTEL — Kernel-level malicious driver protection disabled. Acceptable for solo gaming desktop without cracked software. NOT recommended on corporate/enterprise machines.
- **Notes**: Requires reboot to take effect. VBS itself may still run if Hyper-V / WSL2 / Smart App Control are enabled (separate from HVCI).
- **Reversible**: ✓

### 13. MMCSS Gaming-Profil
- **What**: Tunes Multimedia Class Scheduler Service for gaming
- **Where**: `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile`
  - `SystemResponsiveness = 10` (default: 20) — Multimedia threads get more CPU
  - `NetworkThrottlingIndex = 0xFFFFFFFF` — Disables the 10ms network throttle on multimedia threads
- **Impact**: KEIN
- **Reversible**: ✓

### 14. Game-unfriendly Services disablen
- **What**: Disables four services that interfere with gaming
- **Services**:
  - `SysMain` (SuperFetch / Memory Prefetcher) — useless on SSD/NVMe
  - `WSearch` (Windows Search Indexer) — touches NVMe during matches
  - `DiagTrack` (Telemetry) — background traffic
  - `MapsBroker` — background traffic
- **Impact**: GERING — Windows Search slower (~few seconds), indexed files still usable
- **Reversible**: ✓ (restores pre-Apply StartType + restarts if was running)

### 15. NIC Offloads (LSO, RSC) deaktivieren
- **What**: Disables Large Send Offload v2 and Receive Segment Coalescing on the primary network adapter
- **Where**: `Disable-NetAdapterLso -IPv4 -IPv6`, `Disable-NetAdapterRsc -IPv4 -IPv6`
- **Adapter**: First Up + non-Virtual adapter
- **Impact**: KEIN — actually improves UDP gaming latency (PUBG uses UDP). LSO/RSC bundle packets, useless for game traffic.
- **Reversible**: ✓ (restores pre-Apply enabled state per protocol)

## What's intentionally NOT included (BattlEye-Risk)

The following are widely-cited "PUBG tweaks" online but are **excluded from this suite** because they could trigger BattlEye:

- ❌ **Special K** / `dxgi.dll` injection — DLL injection, BE flags as cheat-engine
- ❌ **ReShade** — Krafton has banned ReShade users since 2018
- ❌ **DXVK / Vulkan-Layer** — Replaces D3D11, BE flags as anti-cheat bypass
- ❌ **Engine.ini Ban-Bait**:
  - `r.Fog=0`, `r.FogDensity=0` — 2018 ban wave still referenced
  - `r.Atmosphere=0`
  - `r.Shadow.MaxResolution<256` (below UI minimum)
  - Negative `r.MipMapLODBias` (texture sharpness hack)
  - Anything under `[/Script/Engine.GameSession]`
  - `Foliage.DensityScale` overrides
- ❌ **Process Lasso affinity on `BEService.exe`** — BE detects external thread-affinity manipulation
- ❌ **Manual SMT-disable on X3D CPUs** — outdated advice, hurts more than helps on Ryzen 7000+ with Win11 22H2+

The suite restricts itself to changes that mirror official PUBG UI sliders, Windows-provided system settings, or driver-level configuration that BattlEye doesn't inspect.

## Snapshot/Backup Locations

After every Apply:
- **Registry snapshots** → entries in `%LOCALAPPDATA%\PUBGSuite\history.json` (JSON, human-readable)
- **File backups** → `%LOCALAPPDATA%\PUBGSuite\backups\<filename>.bak_<timestamp>`
- **Action log** → `%LOCALAPPDATA%\PUBGSuite\logs\<date>.log`

Manual revert (without using suite): copy the `.bak_*` file back to the original, or use Registry Editor with the values from `history.json`.
