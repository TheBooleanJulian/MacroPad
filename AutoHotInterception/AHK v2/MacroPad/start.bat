@echo off
REM MacroPad Remapper - self-elevating launcher
net session >nul 2>&1
if %errorLevel% == 0 goto :run
echo Requesting administrator privileges...
powershell -Command "Start-Process '%~f0' -Verb RunAs"
exit /b

:run
cd /d "%~dp0"
if not exist "MacroPad.ahk" (
    echo MacroPad.ahk not found in: %~dp0
    pause & exit /b 1
)
start "" "MacroPad.ahk"
