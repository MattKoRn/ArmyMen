# ArmyMen one-click Windows build/install.
# Automatically finds an x86 MSVC environment, or installs official VS2022
# Build Tools if missing. Does not pretend that a 1998 codebase is guaranteed
# to compile with a new compiler.
[CmdletBinding()]
param(
    [switch] $SkipToolInstall,
    [switch] $NoLaunch,
    [switch] $NoPull
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Source = Join-Path $Root 'src'
$RunTime = Join-Path $Source 'RunTime'
$BuiltExe = Join-Path $Source 'Release\Armymen.exe'
$GameExe = Join-Path $RunTime 'Armymen.exe'
$BackupExe = Join-Path $RunTime 'Armymen.exe.before-ai-takeover'
$BuildLog = Join-Path $Root 'AI_TAKEOVER_BUILD.log'

function Info([string] $Message) { Write-Host "[ArmyMen] $Message" -ForegroundColor Cyan }

function Find-VsDevCmd {
    $candidates = @()
    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $pf = [Environment]::GetFolderPath('ProgramFiles')
    if ($pf86) { $candidates += (Join-Path $pf86 'Microsoft Visual Studio\Installer\vswhere.exe') }
    if ($pf) { $candidates += (Join-Path $pf 'Microsoft Visual Studio\Installer\vswhere.exe') }
    $vswhere = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

    if ($vswhere) {
        # Prefer VS2022: newest supported tooling may not understand old options.
        foreach ($version in @('[17.0,18.0)', '')) {
            $args = @('-latest', '-products', '*',
                      '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
                      '-property', 'installationPath')
            if ($version) { $args += @('-version', $version) }
            $locations = @(& $vswhere @args 2>$null)
            foreach ($location in $locations) {
                if (-not $location) { continue }
                $path = Join-Path "$location".Trim() 'Common7\Tools\VsDevCmd.bat'
                if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
            }
        }
    }

    $vsdir = [Environment]::GetEnvironmentVariable('VSINSTALLDIR')
    if ($vsdir) {
        $path = Join-Path $vsdir 'Common7\Tools\VsDevCmd.bat'
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    }

    # Fallback if vswhere isn't available but a standard VS install exists.
    foreach ($rootPath in @(
        (Join-Path $pf 'Microsoft Visual Studio\2022'),
        (Join-Path $pf 'Microsoft Visual Studio\2019'),
        (Join-Path $pf86 'Microsoft Visual Studio\2019')
    )) {
        if (-not $rootPath -or -not (Test-Path -LiteralPath $rootPath -PathType Container)) { continue }
        foreach ($edition in @('BuildTools','Community','Professional','Enterprise')) {
            $path = Join-Path $rootPath ($edition + '\Common7\Tools\VsDevCmd.bat')
            if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
        }
    }
    return $null
}

function Has-Command([string] $Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-MicrosoftBuildTools {
    # Official Microsoft bootstrapper. Installer may request administrator
    # elevation; significant download and disk space are required.
    $Uri = 'https://aka.ms/vs/17/release/vs_buildtools.exe'
    $installer = Join-Path $env:TEMP 'ArmyMen-VS2022-BuildTools.exe'
    Info 'No configured NMAKE/Visual C++ environment was found.'
    Info 'Downloading official Microsoft Visual Studio 2022 Build Tools.'
    Info 'The installer may request administrator permission and download several GB.'
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Uri -OutFile $installer -UseBasicParsing
        if ((Get-Item -LiteralPath $installer).Length -lt 100000) {
            throw 'The Microsoft installer download is unexpectedly small.'
        }
        Info 'Installing x86 C++ tools, MFC, and Windows SDK components...'
        $installArgs = @('--passive', '--wait', '--norestart',
                         '--add', 'Microsoft.VisualStudio.Workload.VCTools',
                         '--includeRecommended',
                         '--add', 'Microsoft.VisualStudio.Component.VC.ATLMFC')
        $proc = Start-Process -FilePath $installer -ArgumentList $installArgs -Wait -PassThru
        if ($proc.ExitCode -notin @(0, 3010)) {
            throw "Visual Studio installer returned exit code $($proc.ExitCode)."
        }
        if ($proc.ExitCode -eq 3010) {
            Info 'A reboot may be required before the new tools are usable.'
        }
    } finally {
        Remove-Item -LiteralPath $installer -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host '========================================'
Write-Host '  ArmyMen: Full AI Spectator Takeover'
Write-Host '========================================'
Write-Host ''

try {
    if (-not (Test-Path -LiteralPath (Join-Path $Source 'Armymen.mak'))) {
        throw 'src\Armymen.mak was not found. Run from a complete ArmyMen checkout.'
    }

    if (-not $NoPull -and (Has-Command 'git.exe')) {
        & git -C $Root rev-parse --is-inside-work-tree 1>$null 2>$null
        if ($LASTEXITCODE -eq 0) {
            $current = (& git -C $Root branch --show-current).Trim()
            if ($current -eq 'main') {
                Info 'Checking for a fast-forward update to main (local edits are preserved)...'
                & git -C $Root pull --ff-only origin main
                if ($LASTEXITCODE -ne 0) {
                    throw 'Git could not fast-forward main. Local changes are untouched. Use -NoPull to build offline.'
                }
            } else {
                Info "On branch '$current'; building the local checkout without switching branches."
            }
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $Source 'AutoAITakeover.inc'))) {
        throw 'AI Takeover source is missing; download the updated main branch first.'
    }

    $devCmd = Find-VsDevCmd
    $pathReady = (Has-Command 'nmake.exe') -and (Has-Command 'cl.exe') -and
                 (Has-Command 'link.exe') -and (Has-Command 'rc.exe')
    if (-not $devCmd -and -not $pathReady) {
        if ($SkipToolInstall) {
            throw 'MSVC/NMAKE not found and -SkipToolInstall was selected.'
        }
        Install-MicrosoftBuildTools
        $devCmd = Find-VsDevCmd
    }
    if (-not $devCmd -and -not $pathReady) {
        throw 'Build Tools installation finished, but NMAKE/Visual C++ are still unavailable. Check the Visual Studio Installer for Desktop development with C++ and retry (a reboot may be required).'
    }

    if ($devCmd) {
        Info "Using Visual Studio environment: $devCmd"
    } else {
        Info 'Using NMAKE, cl.exe, link.exe and rc.exe already on PATH.'
    }

    Info 'Building ArmyMen for Win32 (x86) ...'
    Info "Build log: $BuildLog"

    # A legacy .mak file requires the executable target, not the default ALL
    # target: modern Visual Studio no longer ships BSCMAKE for .bsc browsing.
    # Force the AI-related source files to rebuild, including the .inc file.
    foreach ($name in @('aix.obj','GameFlow.obj','Unit.obj','ui.obj','Armymen.exe')) {
        $obj = Join-Path $Source ('Release\' + $name)
        if (Test-Path -LiteralPath $obj) {
            Remove-Item -LiteralPath $obj -Force
        }
    }

    $temporaryCmd = Join-Path $env:TEMP ('ArmyMen-build-' + $PID + '.cmd')
    $lines = @('@echo off')
    if ($devCmd) {
        $lines += ('call "' + $devCmd + '" -arch=x86 -host_arch=x64')
        $lines += 'if errorlevel 1 exit /b 81'
    }
    $lines += @(
        'where nmake.exe >nul 2>nul || exit /b 82',
        'where cl.exe >nul 2>nul || exit /b 83',
        'where link.exe >nul 2>nul || exit /b 84',
        'where rc.exe >nul 2>nul || exit /b 85',
        ('cd /d "' + $Source + '"'),
        'nmake /f "Armymen.mak" CFG="ArmyMen - Win32 Release" ".\Release\Armymen.exe"',
        'exit /b %ERRORLEVEL%'
    )
    [IO.File]::WriteAllLines($temporaryCmd, $lines, [Text.Encoding]::ASCII)
    try {
        & $temporaryCmd 2>&1 | Tee-Object -FilePath $BuildLog
        $resultCode = $LASTEXITCODE
    } finally {
        Remove-Item -LiteralPath $temporaryCmd -ErrorAction SilentlyContinue
    }

    if ($resultCode -ne 0) {
        throw "NMAKE/build failed with exit code $resultCode. See AI_TAKEOVER_BUILD.log. The original game was not replaced. If errors reference old MFC/DirectX APIs or obsolete compiler switches, the 1998 source still needs a compatibility port."
    }
    if (-not (Test-Path -LiteralPath $BuiltExe -PathType Leaf)) {
        throw 'The build reported success but did not create Release\Armymen.exe. Nothing was installed.'
    }
    if ((Get-Item -LiteralPath $BuiltExe).Length -lt 65536) {
        throw 'The generated executable is unexpectedly small. Nothing was installed.'
    }

    if (-not (Test-Path -LiteralPath $RunTime -PathType Container)) {
        New-Item -Path $RunTime -ItemType Directory -Force | Out-Null
    }
    if ((Test-Path -LiteralPath $GameExe) -and
        -not (Test-Path -LiteralPath $BackupExe)) {
        Copy-Item -LiteralPath $GameExe -Destination $BackupExe -ErrorAction Stop
        Info "Original executable backed up to: $BackupExe"
    }
    Copy-Item -LiteralPath $BuiltExe -Destination $GameExe -Force -ErrorAction Stop
    Info "Patched game installed to: $GameExe"

    if (-not $NoLaunch) {
        Info 'Launching ArmyMen...'
        Start-Process -FilePath $GameExe -WorkingDirectory $RunTime
    }

    Info 'SUCCESS: The AI Takeover executable was built and installed.'
    exit 0
} catch {
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host "Diagnostic log (if a build started): $BuildLog" -ForegroundColor Yellow
    Write-Host 'The previous game executable was left in place unless a completed build was successfully installed.'
    exit 1
}
