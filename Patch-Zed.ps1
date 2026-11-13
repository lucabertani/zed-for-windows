[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath
)

$ErrorActionPreference = 'Stop'

$editorPath = Join-Path $SourcePath 'crates/editor/src/editor.rs'
$elementPath = Join-Path $SourcePath 'crates/editor/src/element.rs'
$updaterPath = Join-Path $SourcePath 'crates/auto_update/src/auto_update.rs'
$editor = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $editorPath))
$element = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $elementPath))
$updater = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $updaterPath))

# The same limit also caps rendered line bytes. Raising only the wrap width
# would leave long lines truncated at the old rendering limit.
$constantPattern = '(?m)^const MAX_LINE_LEN: usize = (?<limit>1024|200_000);\r?$'
$wrapPattern = 'SoftWrap::None\s*=>\s*Some\(wrap_width_for\(MAX_LINE_LEN as u32 / 2\)\)'
$constants = [regex]::Matches($editor, $constantPattern)
$wraps = [regex]::Matches($element, $wrapPattern)

# Fail closed if upstream changes either the constant or the no-wrap formula.
# Do not silently publish an unpatched or potentially broken stable build.
if ($constants.Count -ne 1 -or $wraps.Count -ne 1) {
    throw 'Unsupported upstream wrap implementation: expected one MAX_LINE_LEN constant and one SoftWrap::None => Some(wrap_width_for(MAX_LINE_LEN as u32 / 2)) branch.'
}

# Upstream already blocks periodic polling and manual checks whenever an update
# explanation is present. Bake that explanation into both code paths instead of
# changing a user preference or relying on an overridable environment variable.
$originalExplanation = 'option_env!("ZED_UPDATE_EXPLANATION")'
$disabledExplanation = 'Some("Updates are disabled in this patched build to preserve its patches.")'
$originalTitle = '"Zed was installed via a package manager."'
$disabledTitle = '"Updates are disabled in this patched build."'
$originalQuitHook = 'let quit_subscription = Some(cx.on_app_quit(|_, _| finalize_auto_update_on_quit()));'
$disabledQuitHook = 'let quit_subscription = None; // Patched build: never finalize pending upstream updates.'
$originalCount = [regex]::Matches($updater, [regex]::Escape($originalExplanation)).Count
$disabledCount = [regex]::Matches($updater, [regex]::Escape($disabledExplanation)).Count
$explanation = if ($originalCount -eq 2 -and $disabledCount -eq 0) {
    $originalExplanation
} elseif ($originalCount -eq 0 -and $disabledCount -eq 2) {
    $disabledExplanation
} else {
    throw 'Unsupported upstream update implementation: expected two original or two permanently disabled explanation guards.'
}
$title = if ($originalCount -eq 2) {
    $originalTitle
} else {
    $disabledTitle
}
$quitHook = if ($originalCount -eq 2) {
    $originalQuitHook
} else {
    $disabledQuitHook
}
if ([regex]::Matches($updater, [regex]::Escape($quitHook)).Count -ne 1) {
    throw 'Unsupported upstream update implementation: Windows pending-update quit hook changed.'
}
if ([regex]::Matches($updater, [regex]::Escape("if ${explanation}.is_none()")).Count -ne 1 -or
    [regex]::Matches($updater, [regex]::Escape("if let Some(message) = $explanation")).Count -ne 1 -or
    [regex]::Matches($updater, [regex]::Escape($title)).Count -ne 1) {
    throw 'Unsupported upstream update implementation: periodic polling or manual-check guard changed.'
}

# Validate both patches before writing either source file.
if ($constants[0].Groups['limit'].Value -eq '1024') {
    $updated = $editor.Replace('const MAX_LINE_LEN: usize = 1024;', 'const MAX_LINE_LEN: usize = 200_000;')
    [System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $editorPath), $updated, [System.Text.UTF8Encoding]::new($false))
}
if ($originalCount -eq 2) {
    $updated = $updater.Replace($originalExplanation, $disabledExplanation).
        Replace($originalTitle, $disabledTitle).Replace($originalQuitHook, $disabledQuitHook)
    [System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $updaterPath), $updated, [System.Text.UTF8Encoding]::new($false))
}

# MAX_LINE_LEN / 2 = 100,000 columns; existing upstream tests use that formula.
Write-Host 'Patched and verified: soft_wrap none wraps at 100,000 columns; rendering limit is 200,000 bytes.'
Write-Host 'Patched and verified: automatic updates, manual checks and Windows pending-update finalization are disabled in code.'
