@echo off
REM ============================================================
REM MacroPad Diagnostic - build and run
REM
REM Uses -p:UseAppHost=false because this project lives in a
REM Google Drive-synced folder, which locks files during the
REM normal apphost-generation step and breaks a plain "dotnet
REM build". This workaround skips that step and runs the DLL
REM directly instead of a generated .exe.
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
echo Launching diagnostic...
echo.
dotnet bin\Debug\net8.0-windows\MacroPad.dll --diagnostic

pause
