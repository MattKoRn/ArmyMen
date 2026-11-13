@echo off
setlocal EnableExtensions
title ArmyMen AI Takeover - One Click Build and Install

echo.
echo ========================================
echo   ArmyMen: Full AI Spectator Takeover
echo ========================================
echo.

set "SCRIPT=%~dp0scripts\Build-Install-ArmyMen.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: The build helper is missing:
    echo   "%SCRIPT%"
    echo Download the latest main branch of MattKoRn/ArmyMen.
    pause
    exit /b 2
)

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: Windows PowerShell is required to install the build tools automatically.
    pause
    exit /b 3
)

rem The helper locates existing VS tools or downloads official Microsoft
rem Build Tools, runs the legacy NMAKE build, backs up the original EXE,
rem installs the patched build, and launches the game on success.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
    echo.
    echo Build or install did not complete. See the error above and
    echo AI_TAKEOVER_BUILD.log for compiler diagnostics if a build started.
    pause
)
exit /b %EXITCODE%
