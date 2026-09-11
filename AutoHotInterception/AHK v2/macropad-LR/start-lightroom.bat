@echo off
REM ============================================================
REM Start MacroPad Lightroom Remapper (elevated)
REM
REM Interception requires admin rights, same as Diagnostic.ahk.
REM This re-launches itself elevated via UAC if not already
REM running as admin, then starts Lightroom.ahk using whatever
REM app is associated with .ahk files (AutoHotkey v2).
REM ============================================================

net session >nul 2>&1
if %errorLevel% == 0 goto :run

echo Requesting administrator privileges...
powershell -Command "Start-Process '%~f0' -Verb RunAs"
exit /b

:run
cd /d "%~dp0"

if not exist "Lightroom.ahk" (
    echo Lightroom.ahk not found in this folder: %~dp0
    echo Make sure this .bat sits next to Lightroom.ahk, config.json, and JSON.ahk.
    pause
    exit /b 1
)

start "" "Lightroom.ahk"
