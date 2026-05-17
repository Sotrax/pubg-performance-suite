# =============================================================================
#  PUBGNvidiaProfile.psd1  -  Single Source of Truth fuer das NVIDIA-Treiberprofil
# =============================================================================
#
#  Diese Datei definiert die verbindlichen NVIDIA-Treiber-Soll-Werte, die die
#  Suite via nvidiaProfileInspector (.nip-Import) in die Treiber-Datenbank
#  schreibt. Frueher standen diese Werte hartkodiert in PUBGTweakRegistry.psm1.
#
#  Geladen wird IMMER via  Import-PowerShellDataFile  (parst nur Daten, fuehrt
#  keinen Code aus -> sicher). Niemals dot-sourcen oder Import-Module.
#
#  WICHTIG - die SettingIDs hier sind die im Repo VERIFIZIERTEN IDs (Stand
#  0.29.0-beta, gegen NvApiDriverSettings.cs + CustomSettingNames.xml aus
#  Orbmu2k/nvidiaProfileInspector geprueft). Bis 0.28.0-beta waren 4 von 7 IDs
#  falsch verdrahtet (eine sogar frei erfunden) - diese Datei darf NICHT mit
#  unverifizierten IDs aus Drittquellen ueberschrieben werden. Bei jeder
#  ID-Aenderung gegen die NPI-Referenz pruefen und ProfileVersion erhoehen.
#
#  Werte:
#    - PubgSettings      : preset-unabhaengiger Basis-Block des PUBG-App-Profils
#    - GSyncBaseSettings : G-Sync-Master-Schalter, geht ins globale 'Base Profile'
#    - GSyncAppSettings  : G-Sync-Settings des PUBG-App-Profils
#    - VSyncId           : Setting-ID fuer Vertical Sync (Wert kommt je Preset)
#    - Presets           : geordnete Liste der waehlbaren Competitive-Setups
#
#  Quellen (Stand Mai 2026):
#    - Blur Busters G-Sync 101: https://blurbusters.com/gsync/gsync101-input-lag-tests-and-settings/
#    - NvApiDriverSettings.cs / CustomSettingNames.xml (Orbmu2k/nvidiaProfileInspector)
# =============================================================================

@{
    ProfileVersion  = '1.0'
    Description     = 'PUBG Competitive NVIDIA-Treiberprofil - tearing-frei + low latency'

    # Ziel-Profile in der .nip
    ProfileName     = "PLAYERUNKNOWN'S BATTLEGROUNDS"   # PUBG-App-Profil
    Executable      = 'TslGame.exe'                     # Executable des App-Profils
    BaseProfileName = 'Base Profile'                    # globales Treiberprofil

    # Setting-ID fuer Vertical Sync. Der Wert ist preset-abhaengig (siehe Presets).
    #   0x47814940 = Force on    0x08416747 = Force off
    VSyncId = '0x00A879CF'

    # --- Preset-unabhaengiger Basis-Block des PUBG-App-Profils -----------------
    PubgSettings = @(
        @{ Id = '0x1057EB71'; Val = '0x00000001'; Desc = 'Power Management Mode = Prefer maximum performance' }
        @{ Id = '0x00CE2691'; Val = '0x00000014'; Desc = 'Texture Filtering - Quality = High performance' }
        @{ Id = '0x0019BB68'; Val = '0x00000001'; Desc = 'Texture Filtering - Negative LOD Bias = Clamp' }
        @{ Id = '0x20C1221E'; Val = '0x00000001'; Desc = 'Threaded Optimization = On' }
        @{ Id = '0x10835000'; Val = '0x00000000'; Desc = 'Ultra Low Latency = Off (manueller fpscap-Cap ist wirksamer als der ULL-Ultra-Auto-Cap)' }
        @{ Id = '0x00AC8497'; Val = '0x00002800'; Desc = 'Shader Cache Size = 10 GB (gegen Shader-Compile-Stutter / Frametime-Spikes)' }
        @{ Id = '0x0064B541'; Val = '0x00000001'; Desc = 'Preferred Refresh Rate = Highest available' }
    )

    # --- G-Sync-Master-Schalter (globales 'Base Profile') ----------------------
    GSyncBaseSettings = @(
        @{ Id = '0x1094F157'; Val = '0x00000001'; Desc = 'G-SYNC Global Feature = On' }
        @{ Id = '0x1094F1F7'; Val = '0x00000001'; Desc = 'G-SYNC Global Mode = Fullscreen only' }
    )

    # --- G-Sync-Settings des PUBG-App-Profils ----------------------------------
    GSyncAppSettings = @(
        @{ Id = '0x1194F158'; Val = '0x00000001'; Desc = 'G-SYNC Application Mode = Fullscreen only' }
        @{ Id = '0x10A879CF'; Val = '0x00000000'; Desc = 'G-SYNC Application State = Allow' }
    )

    # --- Waehlbare Presets (Reihenfolge = Anzeige-Reihenfolge) -----------------
    # Jedes Preset = PubgSettings-Basisblock + Vertical Sync (VSync) + G-Sync an/aus.
    Presets = @(
        @{
            Key     = 'blurbusters'
            Label   = 'Blur Busters - G-Sync + V-Sync (tearing-frei)'
            Summary = 'G-Sync an, Vertical Sync (NVCP) = Force On als Tearing-Backstop. Tearing-frei bei minimaler Latenz INNERHALB des VRR-Fensters. WICHTIG: zusaetzlich den Tweak "fpscap" anwenden (Refresh-3) - der ist hier Pflicht, sonst greift V-Sync real.'
            VSync   = '0x47814940'   # Force on
            GSync   = $true
        }
        @{
            Key     = 'competitive'
            Label   = 'Real Competitive - G-Sync aus (max. latenzfrei)'
            Summary = 'G-Sync und V-Sync komplett aus. Absolut niedrigste Input-Latenz, dafuer sichtbares Tearing. Passend, wenn die FPS dauerhaft deutlich ueber der Monitor-Hz liegen. FPS-Cap: uncapped oder ~80 % der stabilen FPS.'
            VSync   = '0x08416747'   # Force off
            GSync   = $false
        }
    )
}
