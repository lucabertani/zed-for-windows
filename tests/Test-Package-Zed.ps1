# Standalone packaging tests use marker files, never real binaries or a build.
$ErrorActionPreference = 'Stop'
$packageScript = Join-Path $PSScriptRoot '../Package-Zed.ps1'
$root = Join-Path ([System.IO.Path]::GetTempPath()) "zed-windows-review/packaging tests-$([guid]::NewGuid())"
$source = Join-Path $root 'source'
$output = Join-Path $root 'package'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$fixture = @{
    'target/x86_64-pc-windows-msvc/release/zed.exe' = 'REAL-CARGO-APPLICATION'
    'target/x86_64-pc-windows-msvc/release/cli.exe' = 'CLI-LAUNCHER'
    'target/x86_64-pc-windows-msvc/release/zed.pdb' = 'DO-NOT-SHIP-SYMBOLS'
    'target/Zed-x86_64.exe' = 'DO-NOT-SHIP-INSTALLER'
    'target/standalone-runtime/AGS_SDK-6.3.0/ags_lib/lib/amd_ags_x64.dll' = 'AMD-RUNTIME'
    'target/standalone-runtime/conpty/runtimes/win-x64/native/conpty.dll' = 'CONPTY-RUNTIME'
    'target/standalone-runtime/conpty/build/native/runtimes/x64/OpenConsole.exe' = 'CONSOLE-X64'
    'target/standalone-runtime/conpty/build/native/runtimes/arm64/OpenConsole.exe' = 'CONSOLE-ARM64'
    'LICENSE-GPL' = 'GPL-LICENSE'
    'LICENSE-APACHE' = 'APACHE-LICENSE'
    'assets/licenses.md' = 'THIRD-PARTY-LICENSES'
}

function Assert-Rejected {
    param([string]$Name, [string]$Destination)
    $rejected = $false
    try {
        & $packageScript -SourcePath $source -DestinationPath $Destination
    }
    catch {
        $rejected = $true
    }
    if (-not $rejected) {
        throw "FAIL: $Name should have been rejected"
    }
    Write-Host "PASS: $Name"
}

New-Item -ItemType Directory -Path $source -Force | Out-Null
try {
    foreach ($file in $fixture.GetEnumerator()) {
        $path = Join-Path $source $file.Key
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        [System.IO.File]::WriteAllText($path, $file.Value, $utf8)
    }
    & $packageScript -SourcePath $source -DestinationPath $output
    if ([System.IO.File]::ReadAllText((Join-Path $output 'zed.exe')) -cne 'REAL-CARGO-APPLICATION') {
        throw 'FAIL: root zed.exe is not the actual Cargo application'
    }
    if ([System.IO.File]::ReadAllText((Join-Path $output 'bin/zed.exe')) -cne 'CLI-LAUNCHER') {
        throw 'FAIL: CLI launcher was not placed in bin'
    }
    $expected = @('zed.exe', 'bin/zed.exe', 'amd_ags_x64.dll', 'conpty.dll',
        'x64/OpenConsole.exe', 'arm64/OpenConsole.exe', 'LICENSE-GPL',
        'LICENSE-APACHE', 'licenses.md', 'README.txt') | Sort-Object
    $actual = @(Get-ChildItem -LiteralPath $output -Recurse -File | ForEach-Object {
        [System.IO.Path]::GetRelativePath($output, $_.FullName).Replace('\', '/')
    } | Sort-Object)
    if (@(Compare-Object $expected $actual).Count -ne 0) {
        throw "FAIL: unexpected package contents: $($actual -join ', ')"
    }
    Write-Host 'PASS: direct application, CLI, runtime DLLs, console files and licenses; no installer or PDBs'

    $zipPath = Join-Path $root 'standalone.zip'
    Compress-Archive -Path "$output/*" -DestinationPath $zipPath -CompressionLevel Optimal
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entry = $zip.GetEntry('zed.exe')
        if ($null -eq $entry) {
            throw 'FAIL: ZIP does not contain zed.exe at its root'
        }
        $reader = [System.IO.StreamReader]::new($entry.Open())
        try {
            if ($reader.ReadToEnd() -cne 'REAL-CARGO-APPLICATION') {
                throw 'FAIL: ZIP contains an installer instead of the actual application'
            }
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $zip.Dispose()
    }
    Write-Host 'PASS: ZIP root zed.exe is the application, not the setup executable'

    Assert-Rejected 'existing package is never overwritten' $output
    if ([System.IO.File]::ReadAllText((Join-Path $output 'zed.exe')) -cne 'REAL-CARGO-APPLICATION') {
        throw 'FAIL: rejection modified the existing application'
    }

    $missingOutput = Join-Path $root 'missing-runtime-package'
    $conpty = Join-Path $source 'target/standalone-runtime/conpty/runtimes/win-x64/native/conpty.dll'
    Remove-Item -LiteralPath $conpty
    Assert-Rejected 'missing runtime rejects before creating package' $missingOutput
    if (Test-Path -LiteralPath $missingOutput) {
        throw 'FAIL: incomplete package directory was created'
    }
    [System.IO.File]::WriteAllText($conpty, 'CONPTY-RUNTIME', $utf8)

    $extraAmd = Join-Path $source 'target/standalone-runtime/AGS_SDK-other/ags_lib/lib/amd_ags_x64.dll'
    New-Item -ItemType Directory -Path (Split-Path $extraAmd) -Force | Out-Null
    [System.IO.File]::WriteAllText($extraAmd, 'AMBIGUOUS-AMD-RUNTIME', $utf8)
    Assert-Rejected 'ambiguous runtime version rejects package' (Join-Path $root 'ambiguous-package')
    Remove-Item -LiteralPath $extraAmd

    Remove-Item -LiteralPath (Join-Path $source 'target/x86_64-pc-windows-msvc/release/zed.exe')
    Assert-Rejected 'installer cannot substitute for missing Cargo application' (Join-Path $root 'installer-only-package')
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
Write-Host 'All standalone packaging tests passed. No compilation performed.'
