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
                $path = Join-Path (("$location").Trim()) 'Common7\Tools\VsDevCmd.bat'
                if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
            }
        }
    }

    $vsdir = [Environment]::GetEnvironmentVariable('VSINSTALLDIR')
    if ($vsdir) {
        $path = Join-Path $vsdir 'Common7\Tools\VsDevCmd.bat'
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    }

    # Fallback for older installations without vswhere. A Developer Command
    # Prompt alone does not prove the optional C++ tools were installed.
    $roots = @()
    if ($pf) {
        $roots += (Join-Path $pf 'Microsoft Visual Studio\2022')
        $roots += (Join-Path $pf 'Microsoft Visual Studio\2019')
    }
    if ($pf86) { $roots += (Join-Path $pf86 'Microsoft Visual Studio\2019') }
    foreach ($rootPath in $roots) {
        if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { continue }
        foreach ($edition in @('BuildTools','Community','Professional','Enterprise')) {
            $installPath = Join-Path $rootPath $edition
            $path = Join-Path $installPath 'Common7\Tools\VsDevCmd.bat'
            $toolsRoot = Join-Path $installPath 'VC\Tools\MSVC'
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
                -not (Test-Path -LiteralPath $toolsRoot -PathType Container)) { continue }
            $toolsets = @(Get-ChildItem -LiteralPath $toolsRoot -Directory -ErrorAction SilentlyContinue)
            foreach ($toolset in $toolsets) {
                $compiler = Join-Path $toolset.FullName 'bin\Hostx64\x86\cl.exe'
                if (Test-Path -LiteralPath $compiler -PathType Leaf) { return $path }
            }
        }
    }
    return $null
}

function Has-Command([string] $Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-VsRoot([string] $DevCmd) {
    if (-not $DevCmd) { return $null }
    $suffix = '\Common7\Tools\VsDevCmd.bat'
    if (-not $DevCmd.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    return $DevCmd.Substring(0, $DevCmd.Length - $suffix.Length)
}

function Find-MfcHeader([string] $VsRoot) {
    if (-not $VsRoot) { return $null }
    $tools = Join-Path $VsRoot 'VC\Tools\MSVC'
    if (-not (Test-Path -LiteralPath $tools -PathType Container)) {
        return $null
    }

    # VSDevCmd normally uses the default MSVC version, not just any older
    # toolset installed side-by-side. Only check that selected version.
    $versionFile = Join-Path $VsRoot 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt'
    $version = $null
    if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
        $version = (Get-Content -LiteralPath $versionFile -TotalCount 1).Trim()
    }
    if ($version) {
        $header = Join-Path (Join-Path $tools $version) 'atlmfc\include\afxwin.h'
        if (Test-Path -LiteralPath $header -PathType Leaf) { return $header }
        return $null
    }

    # Rare installations have no version file. Check newest usable toolset.
    $versions = @(Get-ChildItem -LiteralPath $tools -Directory |
                  Sort-Object -Property Name -Descending)
    foreach ($item in $versions) {
        $compiler = Join-Path $item.FullName 'bin\Hostx64\x86\cl.exe'
        if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { continue }
        $header = Join-Path $item.FullName 'atlmfc\include\afxwin.h'
        if (Test-Path -LiteralPath $header -PathType Leaf) { return $header }
        return $null
    }
    return $null
}

function Test-MfcFromIncludePath {
    $includePaths = [Environment]::GetEnvironmentVariable('INCLUDE')
    if (-not $includePaths) { return $false }
    foreach ($dir in $includePaths.Split(';')) {
        if (-not $dir) { continue }
        if (Test-Path -LiteralPath (Join-Path $dir 'afxwin.h') -PathType Leaf) {
            return $true
        }
    }
    return $false
}

function Save-VsSetupDiagnostics([int] $ExitCode, [datetime] $Started) {
    $out = Join-Path $Root 'AI_TAKEOVER_SETUP_DIAGNOSTICS.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Visual Studio Installer failure: exit code $ExitCode")
    $lines.Add("UTC recorded: $([datetime]::UtcNow.ToString('u'))")
    $lines.Add('Microsoft code 5007 = operation blocked; computer does not meet requirements.')
    $lines.Add('https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio')
    $lines.Add('')

    try {
        $os = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $lines.Add("Windows: $($os.ProductName); version $($os.DisplayVersion); build $($os.CurrentBuildNumber).$($os.UBR)")
        $lines.Add("64-bit Windows: $([Environment]::Is64BitOperatingSystem)")
    } catch { $lines.Add("Windows details unavailable: $($_.Exception.Message)") }

    try {
        $ram = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $gb = [math]::Round(([double] $ram.TotalPhysicalMemory / 1GB), 1)
        $lines.Add("Physical memory: $gb GB")
        if ($gb -lt 4) { $lines.Add('WARNING: Visual Studio 2022 requires at least 4GB RAM.') }
    } catch { $lines.Add("RAM detection unavailable: $($_.Exception.Message)") }

    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop
        $space = [math]::Round(([double] $disk.FreeSpace / 1GB), 1)
        $lines.Add("Free space on $($env:SystemDrive): $space GB")
        if ($space -lt 10) {
            $lines.Add('WARNING: Less than 10GB free. Visual Studio components may require significantly more free space.')
        }
    } catch { $lines.Add("Disk detection unavailable: $($_.Exception.Message)") }

    $lines.Add('')
    $lines.Add('Recent Microsoft setup log excerpts, if available:')
    $allLogs = @()
    $tempRoot = [IO.Path]::GetTempPath()
    foreach ($pattern in @('dd_setup_*.log', 'dd_client_*.log',
                           'dd_bootstrapper_*.log', 'dd_installer_*.log')) {
        $allLogs += @(Get-ChildItem -Path (Join-Path $tempRoot $pattern) -File -ErrorAction SilentlyContinue)
    }
    $recent = @($allLogs | Where-Object {
        $_.LastWriteTime -ge $Started.AddMinutes(-2)
    } | Sort-Object LastWriteTime -Descending | Select-Object -First 5)
    if ($recent.Count -eq 0) {
        $recent = @($allLogs | Sort-Object LastWriteTime -Descending |
                     Select-Object -First 3)
        $lines.Add('No current setup logs found; showing latest available logs.')
    }
    foreach ($log in $recent) {
        $lines.Add('')
        $lines.Add("== $($log.Name) ($($log.LastWriteTime)) ==")
        try {
            # Keep a small, relevant excerpt instead of copying potentially
            # sensitive complete Visual Studio setup logs.
            $matches = @(Select-String -LiteralPath $log.FullName -Pattern '5007|requirement|prerequisit|blocked|not supported|unsupported|error|fail|disk|space|memory|OS version' |
                Select-Object -Last 35)
            foreach ($match in $matches) {
                $snippet = $match.Line.Trim()
                if ($snippet.Length -gt 350) { $snippet = $snippet.Substring(0,350) + '...' }
                $lines.Add("line $($match.LineNumber): $snippet")
            }
            if ($matches.Count -eq 0) {
                $lines.Add('No matching lines; inspect the full log locally in TEMP.')
            }
        } catch { $lines.Add("Could not read log: $($_.Exception.Message)") }
    }
    $lines.Add('')
    $lines.Add('Warning: log excerpts may contain local file paths. Review before sharing.')
    [IO.File]::WriteAllLines($out, [string[]] $lines, [Text.Encoding]::UTF8)
    Info "Setup diagnostics saved: $out"
    return $out
}

function Install-MissingMfc([string] $VsRoot) {
    if (-not $VsRoot) {
        throw 'MFC (afxwin.h) is missing and no Visual Studio installation could be located.'
    }

    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $pf = [Environment]::GetFolderPath('ProgramFiles')
    $candidates = @()
    if ($pf86) {
        $candidates += (Join-Path $pf86 'Microsoft Visual Studio\Installer\setup.exe')
    }
    if ($pf) {
        $candidates += (Join-Path $pf 'Microsoft Visual Studio\Installer\setup.exe')
    }
    $installer = $candidates |
                 Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
                 Select-Object -First 1
    if (-not $installer) {
        throw 'MFC is missing. Open Visual Studio Installer > Modify and enable "C++ MFC for latest v143 build tools (x86 & x64)". Then rerun this script.'
    }

    Info 'MFC headers (afxwin.h) are missing from the active MSVC toolset.'
    Info "Adding official MFC x86/x64 component to Visual Studio: $VsRoot"
    Info 'Visual Studio Installer may request administrator permission.'
    # Prefer the version-matched MFC package for VS2022 v14.44 (17.14);
    # this exact component ID is listed in Microsoft's VS2022 catalog.
    $component = 'Microsoft.VisualStudio.Component.VC.ATLMFC'
    $versionFile = Join-Path $VsRoot 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt'
    if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
        $activeVersion = (Get-Content -LiteralPath $versionFile -TotalCount 1).Trim()
        if ($activeVersion -like '14.44.*') {
            $component = 'Microsoft.VisualStudio.Component.VC.14.44.17.14.MFC'
        }
    }
    Info "Installing MFC component: $component"
    Info 'Opening interactive Visual Studio Installer (not passive mode).'
    Info 'Approve the Windows administrator prompt and finish the installer if asked.'
    $arguments = @('modify', '--installPath', ('"' + $VsRoot + '"'),
                   '--add', $component)
    $started = Get-Date
    try {
        # Standard users cannot use Visual Studio's --passive or --quiet
        # modifiers programmatically. Interactive elevation lets the setup
        # interface show any unmet machine requirement instead of hiding it.
        $process = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru -Verb RunAs
    } catch {
        throw "Visual Studio setup could not start or elevation was cancelled: $($_.Exception.Message). Open the Visual Studio Installer application and select Modify > C++ MFC for v143 (x86/x64)."
    }
    if ($process.ExitCode -notin @(0, 3010)) {
        $diagnostics = Save-VsSetupDiagnostics $process.ExitCode $started
        if ($process.ExitCode -eq 5007) {
            throw "Visual Studio Installer blocked the MFC installation (5007: computer does not meet requirements). Check $diagnostics for Windows version, RAM, disk space and Microsoft setup log excerpts. The MFC header has NOT been installed; the original ArmyMen executable was preserved."
        }
        throw "Visual Studio Installer failed to add MFC (exit code $($process.ExitCode)). Check $diagnostics and the setup window for the actual cause."
    }
    if ($process.ExitCode -eq 3010) {
        Info 'MFC installation requested a reboot. Restart Windows before retrying if the header is still unavailable.'
    }
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
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
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
                    Info 'Git update was unavailable. Continuing with local main checkout; no local changes were discarded.'
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
        $vsRoot = Get-VsRoot $devCmd
        if (-not (Find-MfcHeader $vsRoot)) {
            if ($SkipToolInstall) {
                throw 'MFC header afxwin.h is missing. Install the C++ MFC component in Visual Studio Installer (or remove -SkipToolInstall).'
            }
            Install-MissingMfc $vsRoot
            if (-not (Find-MfcHeader $vsRoot)) {
                throw 'MFC installation completed but afxwin.h is still absent from the active MSVC toolset. Reboot if prompted, or use Visual Studio Installer > Modify > Individual components > C++ MFC for latest v143 build tools (x86 & x64).'
            }
        }
        Info "MFC headers available: $(Find-MfcHeader $vsRoot)"
    } else {
        Info 'Using NMAKE, cl.exe, link.exe and rc.exe already on PATH.'
        if (-not (Test-MfcFromIncludePath)) {
            throw 'MFC header afxwin.h was not found in INCLUDE. Install the C++ MFC component and launch from a Visual Studio Developer Command Prompt.'
        }
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
        ('nmake /f "Armymen.mak" CFG="ArmyMen - Win32 Release" ".\Release\Armymen.exe" > "' + $BuildLog + '" 2>&1'),
        'exit /b %ERRORLEVEL%'
    )
    [IO.File]::WriteAllLines($temporaryCmd, $lines, [Text.Encoding]::ASCII)
    try {
        if (Test-Path -LiteralPath $BuildLog) {
            Remove-Item -LiteralPath $BuildLog -Force
        }
        # Redirect from CMD, not from PowerShell: the latter turns compiler
        # stderr warnings into misleading NativeCommandError records.
        & $temporaryCmd
        $resultCode = $LASTEXITCODE
        if (Test-Path -LiteralPath $BuildLog) {
            Get-Content -LiteralPath $BuildLog | ForEach-Object { Write-Host $_ }
        }
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
