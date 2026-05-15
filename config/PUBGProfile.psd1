# =============================================================================
#  PUBGProfile.psd1  -  Single Source of Truth fuer das PUBG-Grafikprofil
# =============================================================================
#
#  Diese Datei definiert die verbindlichen PUBG-Grafik-Soll-Werte.
#  BEIDE Komponenten lesen ausschliesslich von hier:
#    - PUBG-Suite.ps1            (Grafik-Tab: schreibt diese Werte in die INI)
#    - PUBG-Diagnose-v7.ps1      (prueft die INI gegen diese Werte)
#
#  Geladen wird IMMER via  Import-PowerShellDataFile  (parst nur Daten, fuehrt
#  keinen Code aus -> sicher). Niemals dot-sourcen oder Import-Module.
#
#  Werte-Skala der sg.*-Settings (Scalability Groups):
#    0 = Sehr Niedrig | 1 = Niedrig | 2 = Mittel | 3 = Hoch | 4 = Ultra
#
#  NICHT im Profil (bewusst): ResolutionSizeX/Y und FrameRateLimit. Beide sind
#  monitor-/hardwarespezifisch und werden separat behandelt (die Diagnose listet
#  sie nur als INVENTAR, ohne Bewertung).
#
#  Aenderungen an Werten sind User-Master-Entscheidungen - nicht automatisch
#  anpassen. Bei jeder Wertaenderung die ProfileVersion erhoehen.
# =============================================================================

@{
    # Profil-Version. Erscheint im Footer des Diagnose-Reports, damit
    # nachvollziehbar ist, gegen welches Profil geprueft wurde.
    ProfileVersion = '1.0'

    Description = 'PUBG Competitive "Balanced Visibility" - menuekonform, BattlEye-safe'

    # Sections bildet 1:1 die GameUserSettings.ini ab:
    #   Schluessel = INI-Sektionsname (ohne eckige Klammern)
    #   Wert       = Hashtable aus INI-Key = Soll-Wert
    # Die Suite schreibt jeden Eintrag via Update-IniValue in die passende
    # Sektion; die Diagnose liest dieselben Keys und vergleicht.
    Sections = @{

        'ScalabilityGroups' = @{
            'sg.ResolutionQuality'   = '100.000000'  # 100 % - volle Render-Skalierung
            'sg.ViewDistanceQuality' = '2'           # Mittel  - sauberes Terrain auf Distanz
            'sg.AntiAliasingQuality' = '2'           # Mittel  - klare Kanten beim Spotting
            'sg.ShadowQuality'       = '0'           # Sehr Niedrig - Gegner-Schatten bleiben
            'sg.PostProcessQuality'  = '0'           # Sehr Niedrig - kein Bloom/Haze
            'sg.TextureQuality'      = '3'           # Hoch    - Spotting-Klarheit, kostet kaum FPS
            'sg.EffectsQuality'      = '0'           # Sehr Niedrig - weniger Screen-Clutter
            'sg.FoliageQuality'      = '0'           # Sehr Niedrig - liegende Gegner sichtbar
        }

        '/Script/TslGame.TslGameUserSettings' = @{
            'ScreenScale'                 = '100.000000'  # kein Upscaling-Blur
            'bUseVSync'                   = 'False'       # V-Sync aus - kein Input-Lag
            'bUseDynamicResolution'       = 'False'       # dynamische Aufloesung aus - stabiles Bild
            'bMotionBlur'                 = 'False'       # Bewegungsunschaerfe aus
            'bSharpen'                    = 'False'       # In-Game-Sharpen aus (Engine.ini schaerft bereits)
            'bSavedGraphicOption'         = 'True'        # Werte als user-gewaehlt behandeln -> kein Auto-Reset
            'FullscreenMode'              = '0'           # 0 = Exklusiv-Vollbild (niedrigste Latenz)
            'LastConfirmedFullscreenMode' = '0'           # mit FullscreenMode konsistent halten
            'PreferredFullscreenMode'     = '0'           # dito - sonst Confirm-Dialog/Reset beim Start
        }
    }
}
