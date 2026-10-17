param([Parameter(Mandatory=$true)][string] $PackageDirectory)
$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('source-dock-installer-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Invoke-BatInstaller {
    param([string] $InstallerPath, [string] $ObsPath, [string] $PluginsPath)
    $command = '""{0}" -ObsDirectory "{1}"' -f $InstallerPath,$ObsPath
    if ($PluginsPath) { $command += ' -PluginRoot "{0}"' -f $PluginsPath }
    $command += ' -NoPause"'
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = '/d /s /c ' + $command
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    Write-Host $stdout.GetAwaiter().GetResult()
    $errors = $stderr.GetAwaiter().GetResult()
    if ($errors) { Write-Host $errors }
    return $process.ExitCode
}

try {
    $package = Join-Path $testRoot "package & 'quote! with spaces"
    New-Item -ItemType Directory -Path $package | Out-Null
    Get-ChildItem -LiteralPath $PackageDirectory -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $package -Recurse
    }
    $installer = Join-Path $package 'install.bat'
    if ((Test-Path -LiteralPath (Join-Path $package 'install.cmd')) -or
        (Test-Path -LiteralPath (Join-Path $package 'install.ps1'))) { throw 'Only install.bat may be shipped.' }
    $inputDll = Join-Path $package 'source-dock\bin\64bit\source-dock.dll'
    $obsPath = Join-Path $testRoot "OBS test & 'quote! with spaces"
    $pluginRoot = Join-Path $testRoot "plugins & 'quote! with spaces"
    if ((Invoke-BatInstaller $installer $obsPath $pluginRoot) -ne 0) { throw 'Fresh installation failed.' }
    $installedDll = Join-Path $pluginRoot 'source-dock\bin\64bit\source-dock.dll'
    if ((Get-FileHash -LiteralPath $installedDll).Hash -ne (Get-FileHash -LiteralPath $inputDll).Hash) { throw 'DLL hash mismatch.' }
    if (-not (Test-Path -LiteralPath (Join-Path $pluginRoot 'source-dock\data\locale\en-US.ini'))) { throw 'Locale files are missing.' }
    if ((Invoke-BatInstaller $installer $obsPath $pluginRoot) -ne 0) { throw 'Repeat installation failed.' }
    $legacyDll = Join-Path $obsPath 'obs-plugins\64bit\source-dock.dll'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $legacyDll) | Out-Null
    [IO.File]::WriteAllText($legacyDll, 'old plugin test fixture')
    if ((Invoke-BatInstaller $installer $obsPath '') -ne 0) { throw 'Legacy installation update failed.' }
    if ((Get-FileHash -LiteralPath $legacyDll).Hash -ne (Get-FileHash -LiteralPath $inputDll).Hash) { throw 'Legacy DLL was not replaced.' }
    if (-not (Test-Path -LiteralPath (Join-Path $obsPath 'data\obs-plugins\source-dock\locale\en-US.ini'))) { throw 'Legacy locale files are missing.' }
    $missingPackage = Join-Path $testRoot 'missing payload'
    New-Item -ItemType Directory -Path $missingPackage | Out-Null
    Copy-Item -LiteralPath $installer -Destination $missingPackage
    $missingTarget = Join-Path $testRoot 'must not be installed'
    if ((Invoke-BatInstaller (Join-Path $missingPackage 'install.bat') $obsPath $missingTarget) -eq 0) {
        throw 'Missing payload must return failure through the BAT launcher.'
    }
    if (Test-Path -LiteralPath $missingTarget) { throw 'A failed installation created the target directory.' }
    if (Get-ChildItem -LiteralPath $package -Filter '*.ps1' -Recurse) { throw 'Unexpected generated PowerShell script.' }
    Write-Host 'PASS: single BAT, fresh/repeat/legacy installs, payload hashes, missing-payload failure and special-character paths.'
} finally {
    $absoluteTestRoot = [IO.Path]::GetFullPath($testRoot)
    $absoluteTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($absoluteTestRoot.StartsWith($absoluteTempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $absoluteTestRoot).StartsWith('source-dock-installer-test-')) {
        Remove-Item -LiteralPath $absoluteTestRoot -Recurse -Force
    }
}
