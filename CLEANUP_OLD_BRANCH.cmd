@echo off
setlocal EnableExtensions EnableDelayedExpansion
title ArmyMen - Remove Obsolete Git Branch

rem One-click final cleanup after the AI takeover merge to main.
rem Only the known obsolete feature branch is removed. Never deletes main.
set "ROOT=%~dp0"
set "OBSOLETE=feature/ai-autoplay-spectator-camera"

where git >nul 2>&1
if errorlevel 1 (
    echo ERROR: Install Git for Windows or add git.exe to PATH.
    goto :failed
)
git -C "%ROOT%" rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo ERROR: Run this script in a clone of the ArmyMen repository.
    goto :failed
)
for /f "delims=" %%B in ('git -C "%ROOT%" branch --show-current') do set "CURRENT_BRANCH=%%B"
if /i not "!CURRENT_BRANCH!"=="main" (
    echo ERROR: Check out main before removing other branches.
    echo Current branch: "!CURRENT_BRANCH!"
    goto :failed
)
git -C "%ROOT%" remote get-url origin | findstr /i "MattKoRn/ArmyMen" >nul
if errorlevel 1 (
    echo ERROR: origin is not the expected MattKoRn/ArmyMen repository.
    goto :failed
)

echo Removing remote branch, keeping main untouched...
git -C "%ROOT%" ls-remote --exit-code --heads origin "%OBSOLETE%" >nul 2>&1
if not errorlevel 1 (
    git -C "%ROOT%" push origin --delete "%OBSOLETE%"
    if errorlevel 1 (
        echo ERROR: Remote branch deletion failed. GitHub push permission may be required.
        goto :failed
    )
) else (
    echo Remote feature branch already absent.
)

git -C "%ROOT%" show-ref --verify --quiet "refs/heads/%OBSOLETE%"
if not errorlevel 1 (
    git -C "%ROOT%" branch -d "%OBSOLETE%"
    if errorlevel 1 (
        echo Remote cleanup succeeded, but local feature branch is not fully merged.
        echo Review local changes before deleting this branch manually.
    )
)

echo.
echo Finished. The main branch was preserved.
pause
exit /b 0

:failed
echo.
echo No further branches were deleted.
pause
exit /b 1
