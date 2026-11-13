[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath,
    [Parameter(Mandatory)]
    [string]$DestinationPath
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourcePath).Path
$cargoOutput = Join-Path $source 'target/x86_64-pc-windows-msvc/release'
$runtime = Join-Path $source 'target/standalone-runtime'
$amdDlls = @(Get-ChildItem -Path "$runtime/AGS_SDK-*/ags_lib/lib/amd_ags_x64.dll" -File)
if ($amdDlls.Count -ne 1) {
    throw 'Expected exactly one upstream AMD GPU Services x64 runtime DLL'
}

# Take the real application from Cargo's target directory, NEVER target/Zed-x86_64.exe
# (the Inno Setup installer). Preserve the runtime layout used by upstream.
$files = @(
    @{ Source = "$cargoOutput/zed.exe"; Relative = 'zed.exe' }
    @{ Source = "$cargoOutput/cli.exe"; Relative = 'bin/zed.exe' }
    @{ Source = $amdDlls[0].FullName; Relative = 'amd_ags_x64.dll' }
    @{ Source = "$runtime/conpty/runtimes/win-x64/native/conpty.dll"; Relative = 'conpty.dll' }
    @{ Source = "$runtime/conpty/build/native/runtimes/x64/OpenConsole.exe"; Relative = 'x64/OpenConsole.exe' }
    @{ Source = "$runtime/conpty/build/native/runtimes/arm64/OpenConsole.exe"; Relative = 'arm64/OpenConsole.exe' }
    @{ Source = "$source/LICENSE-GPL"; Relative = 'LICENSE-GPL' }
    @{ Source = "$source/LICENSE-APACHE"; Relative = 'LICENSE-APACHE' }
    @{ Source = "$source/assets/licenses.md"; Relative = 'licenses.md' }
)
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file.Source -PathType Leaf)) {
        throw "Standalone package is incomplete: missing $($file.Source)"
    }
}
if (Test-Path -LiteralPath $DestinationPath) {
    throw "Refusing to overwrite an existing package directory: $DestinationPath"
}

New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
foreach ($file in $files) {
    $destination = Join-Path $DestinationPath $file.Relative
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    Copy-Item -LiteralPath $file.Source -Destination $destination
}
@'
Zed for Windows x64 - standalone application (no installer)

Extract the ENTIRE ZIP to a folder, then double-click zed.exe in that folder.
Do not run it inside the ZIP and do not separate it from its runtime DLLs.
The optional command-line launcher is bin/zed.exe.

soft_wrap none uses a 100,000-column fallback. Upstream automatic updates,
manual checks and pending-update finalization are disabled in the source.
Download a newer standalone ZIP from this repository to update manually.

This is an unofficial, unsigned build. Settings and user data still use Zed's
normal Windows profile directories; this is not an isolated portable profile.
'@ | Set-Content -LiteralPath (Join-Path $DestinationPath 'README.txt') -Encoding utf8
Write-Host "Standalone application ready: $DestinationPath/zed.exe (not an installer)"
