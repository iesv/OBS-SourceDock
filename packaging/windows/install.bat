@echo off
setlocal DisableDelayedExpansion
set "SOURCE_DOCK_INSTALLER=%~f0"
set "SOURCE_DOCK_OBS_DIRECTORY="
set "SOURCE_DOCK_PLUGIN_ROOT="
set "SOURCE_DOCK_NO_PAUSE="
set "SOURCE_DOCK_ELEVATED="
set "SOURCE_DOCK_ARGUMENT_ERROR="
:source_dock_arguments
if "%~1"=="" goto source_dock_run
if /i "%~1"=="-ObsDirectory" (
    set "SOURCE_DOCK_OPTION=SOURCE_DOCK_OBS_DIRECTORY"
    goto source_dock_value
)
if /i "%~1"=="-PluginRoot" (
    set "SOURCE_DOCK_OPTION=SOURCE_DOCK_PLUGIN_ROOT"
    goto source_dock_value
)
if /i "%~1"=="-NoPause" goto source_dock_no_pause
set "SOURCE_DOCK_ARGUMENT_ERROR=Unknown argument: %~1"
goto source_dock_run
:source_dock_value
if "%~2"=="" goto source_dock_missing_value
set "%SOURCE_DOCK_OPTION%=%~2"
shift
shift
goto source_dock_arguments
:source_dock_no_pause
set "SOURCE_DOCK_NO_PAUSE=1"
shift
goto source_dock_arguments
:source_dock_missing_value
set "SOURCE_DOCK_ARGUMENT_ERROR=Missing value for %~1."
:source_dock_run
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$text=[IO.File]::ReadAllText($env:SOURCE_DOCK_INSTALLER); $marker=':'+'SOURCE_DOCK_POWERSHELL'; & ([ScriptBlock]::Create($text.Substring($text.IndexOf($marker)+$marker.Length)))"
exit /b %errorlevel%
:SOURCE_DOCK_POWERSHELL
$ObsDirectory = $env:SOURCE_DOCK_OBS_DIRECTORY
$PluginRoot = $env:SOURCE_DOCK_PLUGIN_ROOT
$NoPause = $env:SOURCE_DOCK_NO_PAUSE -eq '1'
$Elevated = $env:SOURCE_DOCK_ELEVATED -eq '1'

$ErrorActionPreference = 'Stop'
# Use Windows PowerShell's own modules even when launched from PowerShell 7.
$env:PSModulePath = [IO.Path]::Combine($PSHOME, 'Modules')

function Wait-InstallerExit {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $lastSecond = -1
    while ($timer.Elapsed.TotalSeconds -lt 5) {
        $remaining = 5 - [int][Math]::Floor($timer.Elapsed.TotalSeconds)
        if ($remaining -ne $lastSecond) {
            Write-Host -NoNewline ("`rClosing in {0} seconds. Press any key to exit... " -f $remaining)
            $lastSecond = $remaining
        }
        try {
            if (-not [Console]::IsInputRedirected -and [Console]::KeyAvailable) {
                $null = [Console]::ReadKey($true)
                break
            }
        } catch { }
        Start-Sleep -Milliseconds 50
    }
    Write-Host
}

function Install-SourceDock {
    param([string] $ObsPath, [string] $PluginsPath)

    if (Get-Process -Name obs64,obs32 -ErrorAction SilentlyContinue) {
        throw 'Close OBS Studio before installing Source Dock.'
    }
    $payload = Join-Path (Split-Path -Parent $env:SOURCE_DOCK_INSTALLER) 'source-dock'
    $dll = Join-Path $payload 'bin\64bit\source-dock.dll'
    $data = Join-Path $payload 'data'
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $data 'locale\en-US.ini') -PathType Leaf)) {
        throw 'Plugin files are missing. Extract the complete ZIP before running install.bat.'
    }
    if (-not $ObsPath) {
        $ObsPath = Join-Path $env:ProgramFiles 'obs-studio'
    }
    $legacyDll = Join-Path $ObsPath 'obs-plugins\64bit\source-dock.dll'
    if (-not $PluginsPath -and (Test-Path -LiteralPath $legacyDll -PathType Leaf)) {
        $destinationDll = $legacyDll
        $destinationData = Join-Path $ObsPath 'data\obs-plugins\source-dock'
    } else {
        if (-not $PluginsPath) {
            $PluginsPath = Join-Path $env:ProgramData 'obs-studio\plugins'
        }
        $pluginDirectory = Join-Path $PluginsPath 'source-dock'
        $obsExecutable = Join-Path $ObsPath 'bin\64bit\obs64.exe'
        $majorVersion = if (Test-Path -LiteralPath $obsExecutable -PathType Leaf) {
            (Get-Item -LiteralPath $obsExecutable).VersionInfo.FileMajorPart
        } else { 32 }
        if ($majorVersion -ge 33) {
            $destinationDll = Join-Path $pluginDirectory 'source-dock.dll'
        } else {
            $destinationDll = Join-Path $pluginDirectory 'bin\64bit\source-dock.dll'
        }
        $destinationData = Join-Path $pluginDirectory 'data'
    }

    # Copy resources first; retain the existing DLL until its replacement is ready.
    $dllDirectory = Split-Path -Parent $destinationDll
    New-Item -ItemType Directory -Force -Path $dllDirectory,$destinationData | Out-Null
    $temporaryDll = Join-Path $dllDirectory ('source-dock.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Copy-Item -LiteralPath $dll -Destination $temporaryDll -Force
        $expectedHash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
        if ((Get-FileHash -LiteralPath $temporaryDll -Algorithm SHA256).Hash -ne $expectedHash) {
            throw 'The copied plugin failed its integrity check.'
        }
        Get-ChildItem -LiteralPath $data -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $destinationData -Recurse -Force
        }
        if (Test-Path -LiteralPath $destinationDll) {
            $backupDll = $temporaryDll + '.bak'
            [IO.File]::Replace($temporaryDll, $destinationDll, $backupDll)
            Remove-Item -LiteralPath $backupDll -Force
        } else {
            [IO.File]::Move($temporaryDll, $destinationDll)
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryDll) {
            Remove-Item -LiteralPath $temporaryDll -Force
        }
    }
    Write-Host "Source Dock 0.5.1-2 installed successfully.`nPlugin: $destinationDll`nYou can now open OBS Studio." -ForegroundColor Green
}

$exitCode = 0
$pauseHere = -not $NoPause
try {
    if ($env:SOURCE_DOCK_ARGUMENT_ERROR) { throw $env:SOURCE_DOCK_ARGUMENT_ERROR }
    Install-SourceDock -ObsPath $ObsDirectory -PluginsPath $PluginRoot
} catch {
    $accessDenied = $_.CategoryInfo.Category -eq 'PermissionDenied'
    $cause = $_.Exception
    while ($null -ne $cause) {
        if ($cause -is [UnauthorizedAccessException]) { $accessDenied = $true }
        $cause = $cause.InnerException
    }
    if ($accessDenied -and -not $Elevated) {
        Write-Host 'Administrator permission is required. Please accept the Windows prompt.'
        # Encode data before relaunching so paths never become PowerShell code.
        $state = @{}
        foreach ($name in 'INSTALLER','OBS_DIRECTORY','PLUGIN_ROOT','NO_PAUSE') {
            $state['SOURCE_DOCK_' + $name] = [Environment]::GetEnvironmentVariable('SOURCE_DOCK_' + $name)
        }
        $state64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($state | ConvertTo-Json -Compress)))
        $command = @"
`$state = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$state64')) | ConvertFrom-Json
`$state.PSObject.Properties | ForEach-Object { [Environment]::SetEnvironmentVariable(`$_.Name, [string]`$_.Value) }
`$env:SOURCE_DOCK_ELEVATED = '1'
`$env:SOURCE_DOCK_ARGUMENT_ERROR = ''
`$text = [IO.File]::ReadAllText(`$env:SOURCE_DOCK_INSTALLER)
`$marker = ':' + 'SOURCE_DOCK_POWERSHELL'
& ([ScriptBlock]::Create(`$text.Substring(`$text.IndexOf(`$marker) + `$marker.Length)))
"@
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        try {
            $child = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
                '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encodedCommand
            ) -Verb RunAs -Wait -PassThru
            $exitCode = $child.ExitCode
            $pauseHere = $false
        } catch {
            Write-Host ('Installation failed: ' + $_.Exception.Message) -ForegroundColor Red
            $exitCode = 1
        }
    } else {
        Write-Host ('Installation failed: ' + $_.Exception.Message) -ForegroundColor Red
        $exitCode = 1
    }
} finally {
    if ($pauseHere) { Wait-InstallerExit }
}
exit $exitCode
