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
    throw "Refusing to build a non-stable source tree: $channel"
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ([string]::IsNullOrWhiteSpace($installation)) {
    throw 'Visual Studio C++ build tools were not found'
}
$launcher = Join-Path $installation 'Common7/Tools/Launch-VsDevShell.ps1'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw "Visual Studio developer shell not found: $launcher"
}

Push-Location
try {
    & $launcher -Arch amd64 -HostArch amd64
}
finally {
    Pop-Location
}

# Import only upstream's runtime-download functions, never its top-level
# bundling pipeline, BuildInstaller, MakeAppx, signing or update-helper build.
$parseErrors = $null
$tokens = $null
$bundler = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $source 'script/bundle-windows.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Cannot parse upstream runtime-download functions: $($parseErrors -join '; ')"
}
foreach ($name in @('DownloadAMDGpuServices', 'DownloadConpty')) {
    $definitions = @($bundler.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $false))
    if ($definitions.Count -ne 1) {
        throw "Upstream runtime download function changed: $name"
    }
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

Push-Location -LiteralPath $source
try {
    $env:ZED_RELEASE_CHANNEL = $channel
    $env:RELEASE_CHANNEL = $channel
    # Generate the same embedded license asset as the official release build.
    & ./script/generate-licenses.ps1

    # Same target, configuration, release profile and default features as the
    # official Windows bundle. Only build the application and CLI, not installers,
    # Explorer integration, the update helper or the separately shipped server.
    cargo --config .cargo/bundle-config.toml build --release --package zed --package cli --target x86_64-pc-windows-msvc

    $runtime = Join-Path $source 'target/standalone-runtime'
    if (Test-Path -LiteralPath $runtime) {
        Remove-Item -LiteralPath $runtime -Recurse -Force
    }
    New-Item -ItemType Directory -Path $runtime | Out-Null
    Push-Location -LiteralPath $runtime
    try {
        # Versions and URLs come from this stable's official bundling script.
        DownloadAMDGpuServices
        DownloadConpty
    }
    finally {
        Pop-Location
    }
}
finally {
    Pop-Location
}
