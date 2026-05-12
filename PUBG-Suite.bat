@echo off
REM PUBG Performance Suite - Doppelklick-Starter
REM Self-elevate falls Admin noetig (z.B. fuer Defender-Check)

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0PUBG-Suite.ps1"
