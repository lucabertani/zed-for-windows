# Standalone tests: no Pester, Rust toolchain or local Zed build needed.
$ErrorActionPreference = 'Stop'
$patch = Join-Path $PSScriptRoot '../Patch-Zed.ps1'
$root = Join-Path ([System.IO.Path]::GetTempPath()) "zed-windows-review/patch-tests-$([guid]::NewGuid())"
$editorPath = Join-Path $root 'crates/editor/src/editor.rs'
$elementPath = Join-Path $root 'crates/editor/src/element.rs'
$updaterPath = Join-Path $root 'crates/auto_update/src/auto_update.rs'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$original = "const MAX_LINE_LEN: usize = 1024;`nconst OTHER_LIMIT: usize = 42;`n"
$element = @'
match soft_wrap {
    SoftWrap::None => Some(wrap_width_for(MAX_LINE_LEN as u32 / 2)),
    SoftWrap::EditorWidth => Some(editor_width),
}
'@

$originalUpdater = @'
fn init() {
    #[cfg(target_os = "windows")]
    let quit_subscription = Some(cx.on_app_quit(|_, _| finalize_auto_update_on_quit()));
    if option_env!("ZED_UPDATE_EXPLANATION").is_none()
        && env::var("ZED_UPDATE_EXPLANATION").is_err()
        && poll_for_updates
    {
        let mut update_subscription = AutoUpdateSetting::get_global(cx)
            .0
            .then(|| updater.start_polling(cx));
    }
}
fn check() {
    if let Some(message) = option_env!("ZED_UPDATE_EXPLANATION")
        .map(ToOwned::to_owned)
        .or_else(|| env::var("ZED_UPDATE_EXPLANATION").ok())
    {
        drop(window.prompt(
            gpui::PromptLevel::Info,
            "Zed was installed via a package manager.",
            Some(&message),
            &["OK"],
            cx,
        ));
        return;
    }
    updater.poll(UpdateCheckType::Manual, cx);
}
'@
$disabledExplanation = 'Some("Updates are disabled in this patched build to preserve its patches.")'
$originalQuitHook = 'let quit_subscription = Some(cx.on_app_quit(|_, _| finalize_auto_update_on_quit()));'
$disabledQuitHook = 'let quit_subscription = None; // Patched build: never finalize pending upstream updates.'
$expectedUpdater = $originalUpdater.Replace('option_env!("ZED_UPDATE_EXPLANATION")', $disabledExplanation).
    Replace('"Zed was installed via a package manager."', '"Updates are disabled in this patched build."').
    Replace($originalQuitHook, $disabledQuitHook)

function Set-Fixture {
    param([string]$Editor, [string]$Element, [string]$Updater = $originalUpdater)
    [System.IO.File]::WriteAllText($editorPath, $Editor, $utf8)
    [System.IO.File]::WriteAllText($elementPath, $Element, $utf8)
    [System.IO.File]::WriteAllText($updaterPath, $Updater, $utf8)
}

function Assert-Rejected {
    param([string]$Name, [string]$Editor, [string]$Element, [string]$Updater = $originalUpdater)
    Set-Fixture -Editor $Editor -Element $Element -Updater $Updater
    $rejected = $false
    try {
        & $patch -SourcePath $root
    }
    catch {
        $rejected = $true
    }
    if (-not $rejected) {
        throw "FAIL: $Name should have been rejected"
    }
    if ([System.IO.File]::ReadAllText($editorPath) -cne $Editor -or
        [System.IO.File]::ReadAllText($updaterPath) -cne $Updater) {
        throw "FAIL: $Name changed source before rejecting it"
    }
    Write-Host "PASS: $Name"
}

New-Item -ItemType Directory -Path (Split-Path $editorPath), (Split-Path $updaterPath) -Force | Out-Null
try {
    Set-Fixture -Editor $original -Element $element
    & $patch -SourcePath $root
    $expected = $original.Replace('1024;', '200_000;')
    if ([System.IO.File]::ReadAllText($editorPath) -cne $expected) {
        throw 'FAIL: patch did not change exactly the rendering/wrap constant'
    }
    if ([System.IO.File]::ReadAllText($elementPath) -cne $element) {
        throw 'FAIL: other wrap modes were changed'
    }
    Write-Host 'PASS: original source patched to 100000-column fallback'
    if ([System.IO.File]::ReadAllText($updaterPath) -cne $expectedUpdater) {
        throw 'FAIL: automatic and manual checks must both use the permanent disabled explanation'
    }
    Write-Host 'PASS: automatic polling blocked, manual checks disabled and Windows quit hook removed'

    $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($editorPath))
    $updaterBefore = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($updaterPath))
    & $patch -SourcePath $root
    if ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($editorPath)) -cne $before -or
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($updaterPath)) -cne $updaterBefore) {
        throw 'FAIL: repeated patch was not byte-identical'
    }
    Write-Host 'PASS: patch is idempotent'

    $crlfOriginal = $original.Replace("`n", "`r`n")
    $crlfUpdater = $originalUpdater.Replace("`r`n", "`n").Replace("`n", "`r`n")
    $crlfExpectedUpdater = $expectedUpdater.Replace("`r`n", "`n").Replace("`n", "`r`n")
    Set-Fixture -Editor $crlfOriginal -Element $element -Updater $crlfUpdater
    & $patch -SourcePath $root
    if ([System.IO.File]::ReadAllText($editorPath) -cne $crlfOriginal.Replace('1024;', '200_000;') -or
        [System.IO.File]::ReadAllText($updaterPath) -cne $crlfExpectedUpdater) {
        throw 'FAIL: Windows CRLF line endings were not preserved'
    }
    Write-Host 'PASS: CRLF preserved'

    Assert-Rejected 'changed upstream constant' ($original.Replace('1024;', '2048;')) $element
    Assert-Rejected 'missing constant' '' $element
    Assert-Rejected 'duplicate constant' ($original + $original) $element
    Assert-Rejected 'changed none formula' $original ($element.Replace('/ 2', '/ 4'))
    Assert-Rejected 'missing none branch' $original 'SoftWrap::EditorWidth => Some(editor_width),'
    Assert-Rejected 'duplicate none branch' $original ($element + $element)
    Assert-Rejected 'incompatible already-patched source' $expected ($element.Replace('/ 2', '/ 4'))

    Assert-Rejected 'changed automatic-update guard' $original $element ($originalUpdater.Replace('.is_none()', '.is_some()'))
    Assert-Rejected 'changed manual-update guard' $original $element ($originalUpdater.Replace('if let Some(message)', 'if let Some(reason)'))
    Assert-Rejected 'changed Windows quit hook' $original $element ($originalUpdater.Replace('finalize_auto_update_on_quit()', 'finalize_updates()'))
    Assert-Rejected 'missing updater guards' $original $element ''
    Assert-Rejected 'duplicate updater guards' $original $element ($originalUpdater + $originalUpdater)
    Assert-Rejected 'partially patched updater' $original $element ($originalUpdater.Replace('if option_env!("ZED_UPDATE_EXPLANATION")', "if $disabledExplanation"))
    Assert-Rejected 'changed updater message' $original $element ($originalUpdater.Replace('Zed was installed via a package manager.', 'Other message'))
    Assert-Rejected 'incompatible already-patched updater' $expected $element ($expectedUpdater.Replace('.is_none()', '.is_some()'))

    # Reconcile a previously wrap-only patched tree as well as a pristine tree.
    Set-Fixture -Editor $expected -Element $element
    & $patch -SourcePath $root
    if ([System.IO.File]::ReadAllText($updaterPath) -cne $expectedUpdater) {
        throw 'FAIL: updater patch did not apply to an already wrap-patched tree'
    }
    Write-Host 'PASS: existing wrap-only source receives the update block'

    Remove-Item -LiteralPath $elementPath
    $rejected = $false
    try {
        & $patch -SourcePath $root
    }
    catch {
        $rejected = $true
    }
    if (-not $rejected) {
        throw 'FAIL: missing source file should have been rejected'
    }
    Write-Host 'PASS: missing file rejected'

    Set-Fixture -Editor $original -Element $element
    Remove-Item -LiteralPath $updaterPath
    $rejected = $false
    try {
        & $patch -SourcePath $root
    }
    catch {
        $rejected = $true
    }
    if (-not $rejected -or [System.IO.File]::ReadAllText($editorPath) -cne $original) {
        throw 'FAIL: missing updater source must reject before changing the wrap source'
    }
    Write-Host 'PASS: missing updater file rejected before any changes'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
Write-Host 'All patch tests passed. No compilation performed.'
