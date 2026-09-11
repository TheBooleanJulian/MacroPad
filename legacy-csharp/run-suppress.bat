@echo off
REM ============================================================
REM MacroPad Suppression - build and run
REM
REM Blocks the macro pad's native input system-wide (no kernel
REM driver - see README for how). Uses -p:UseAppHost=false
REM because this project lives in a Google Drive-synced folder.
REM ============================================================

cd /d "%~dp0"

echo Building...
dotnet build -p:UseAppHost=false
if errorlevel 1 (
    echo.
    echo Build failed - see errors above.
    pause
    exit /b 1
)

echo.
echo Launching suppression mode...
echo.
dotnet bin\Debug\net8.0-windows\MacroPad.dll --suppress

pause
