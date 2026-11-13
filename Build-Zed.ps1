[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$source = (Resolve-Path -LiteralPath $SourcePath).Path

$channel = [System.IO.File]::ReadAllText((Join-Path $source 'crates/zed/RELEASE_CHANNEL')).Trim()
if ($channel -ne 'stable') {
    throw "Refusing to bundle a non-stable source tree: $channel"
}

# The official release script assumes VS Community on upstream's self-hosted
# runner. GitHub-hosted windows-2022 has Enterprise instead. Adapt only this
# host-tool path; leave every Cargo command, feature and optimization untouched.
$bundlerPath = Join-Path $source 'script/bundle-windows.ps1'
$bundler = [System.IO.File]::ReadAllText($bundlerPath)
$defaultLauncher = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\Launch-VsDevShell.ps1'
if (-not (Test-Path -LiteralPath $defaultLauncher)) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ([string]::IsNullOrWhiteSpace($installation)) {
        throw 'Visual Studio C++ build tools were not found'
    }
    $launcher = Join-Path $installation 'Common7/Tools/Launch-VsDevShell.ps1'
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        throw "Visual Studio developer shell not found: $launcher"
    }
    if ([regex]::Matches($bundler, [regex]::Escape($defaultLauncher)).Count -ne 1) {
        throw 'Upstream Visual Studio launcher changed; review the Windows bundler before building'
    }
    $bundler = $bundler.Replace($defaultLauncher, $launcher)
    [System.IO.File]::WriteAllText($bundlerPath, $bundler, [System.Text.UTF8Encoding]::new($false))
}

Push-Location -LiteralPath $source
try {
    # Use upstream's complete release pipeline, including bundle-config.toml,
    # licenses, runtime DLLs and installer. Do not reconstruct its Rust flags.
    & ./script/bundle-windows.ps1 -Architecture x86_64
    if ($LASTEXITCODE -ne 0) {
        throw "Upstream Windows bundler failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
