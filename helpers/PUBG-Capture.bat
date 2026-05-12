@echo off
setlocal

REM ===================================================================
REM PUBG-Capture.bat
REM Doppelklick-Wrapper fuer PresentMon
REM - Self-Elevate auf Admin (fuer ETW-Subscription)
REM - Findet PresentMon-*-x64.exe in C:\Tools\PresentMon
REM - 120 Sekunden Capture des TslGame.exe Prozesses
REM - CSV landet auf Desktop: pubg-presentmon.csv
REM ===================================================================

REM Self-Elevate falls nicht Admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Hole Admin-Rechte fuer ETW-Subscription...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

REM PresentMon finden
set "PM_DIR=C:\Tools\PresentMon"
if not exist "%PM_DIR%" (
    echo.
    echo FEHLER: Ordner %PM_DIR% existiert nicht.
    echo Lade PresentMon von https://github.com/GameTechDev/PresentMon/releases
    echo und leg PresentMon-*-x64.exe nach %PM_DIR%
    echo.
    pause
    exit /b 1
)

REM Erst x64 probieren, dann x86 als Fallback
set "PM_EXE="
for %%f in ("%PM_DIR%\PresentMon-*-x64.exe") do set "PM_EXE=%%f"
if not defined PM_EXE (
    for %%f in ("%PM_DIR%\PresentMon-*-x86.exe") do set "PM_EXE=%%f"
)
if not defined PM_EXE (
    for %%f in ("%PM_DIR%\PresentMon-*.exe") do set "PM_EXE=%%f"
)

if not defined PM_EXE (
    echo.
    echo FEHLER: Keine PresentMon-*.exe in %PM_DIR%
    echo Lade von https://github.com/GameTechDev/PresentMon/releases
    echo.
    pause
    exit /b 1
)

REM Warnung wenn x86 (x64 ist robuster, aber x86 funktioniert auch)
echo %PM_EXE% | findstr /i "x86" >nul && echo  HINWEIS: x86-Version erkannt - funktioniert, x64 waere optimaler.

set "OUTPUT=%USERPROFILE%\Desktop\pubg-presentmon.csv"

cls
echo.
echo  =====================================
echo    PUBG PRESENTMON CAPTURE
echo  =====================================
echo  Tool:    %PM_EXE%
echo  Ziel:    %OUTPUT%
echo  Dauer:   120 Sekunden
echo.
echo  WICHTIG:
echo   - PUBG muss schon LAUFEN und du IM MATCH sein
echo   - RTSS sollte NICHT laufen
echo   - Nur OLED-Monitor aktiv
echo.
echo  Capture startet in 10 Sekunden.
echo  WAEHREND DER WARTEZEIT zurueck zu PUBG wechseln (Alt+Tab)
echo.
timeout /t 10

echo.
echo  Capture laeuft (120s)...
echo.

"%PM_EXE%" -process_name TslGame.exe -timed 120 -terminate_after_timed -output_file "%OUTPUT%"

echo.
if exist "%OUTPUT%" (
    for %%A in ("%OUTPUT%") do set FILESIZE=%%~zA
    echo  =====================================
    echo    CAPTURE FERTIG
    echo  =====================================
    echo  CSV: %OUTPUT%
    echo  Datei-Groesse: %FILESIZE% Bytes
    echo.
    if "%FILESIZE%" == "0" (
        echo  WARNUNG: Datei ist leer - PUBG lief evtl. nicht?
    )
) else (
    echo  FEHLER: Capture-Datei wurde nicht erstellt
    echo  Moegliche Ursache: TslGame.exe lief nicht waehrend der 120s
)
echo.
pause
