# Patched Zed stable for Windows

This repository builds an **unofficial, patched Windows x64 release** of
[Zed](https://github.com/zed-industries/zed). Zed already officially supports
Windows; this build exists for the disabled-soft-wrap patch and permanently
blocks upstream updates that would replace it.

## The patch

Even with `"soft_wrap": "none"`, upstream Zed wraps long display lines at
`MAX_LINE_LEN / 2` columns. The supported upstream implementation defines
`MAX_LINE_LEN` as `1024`, giving a fallback of only **512 columns**.

[`Patch-Zed.ps1`](Patch-Zed.ps1) changes that constant to `200_000`, making the
fallback **100,000 columns**. It also increases the connected rendering limit to
200,000 bytes, rather than increasing the wrap width while still truncating
rendered lines at the old limit. This is display wrapping, not insertion of
newlines into files. It is not a limit on the number of lines in a file, nor is
it infinite wrapping; unusually long or multibyte-heavy lines still have limits.
Other soft-wrap mode calculations are unchanged.

### Updates disabled in source

The same script patches `crates/auto_update/src/auto_update.rs`. Upstream already
blocks updates when an update explanation is present. The patch replaces the
two compile-time environment lookups with a hardcoded `Some("...")` explanation:

- The periodic update poller and its settings observer are never started.
- The manual **Check for Updates** action displays a message explaining that
  updates are disabled and returns without checking or downloading anything.
- The Windows quit hook that finalizes a previously staged update is removed,
  preventing leftovers from an official installation from replacing this build.
- Neither `"auto_update": true` nor environment variables can re-enable updates.

This is a source-code change compiled into the application, not a settings
change or a runtime environment requirement.

Both patches are **mandatory after every source checkout**, idempotent, and
validate the original wrap constant/formula, both updater guards and the
Windows pending-update quit hook before writing either file. If a future stable changes the expected implementation,
the workflow fails instead of silently publishing an unpatched build. Review
the patches against that upstream version before rerunning it.

## One workflow

[`.github/workflows/daily-release.yml`](.github/workflows/daily-release.yml) is
the only workflow:

1. Every day at **03:00 UTC**, query the official repository's latest published
   stable release (not `main`, nightly or preview), then resolve its tag to an
   immutable source commit.
2. Skip scheduled builds if that version already has a published patched ZIP.
3. Check out the source and always apply and verify both patches before compiling.
4. Build **Windows x64 only**, on `windows-2022`, using the Rust toolchain from
   that stable's `rust-toolchain.toml` and its official
   `script/bundle-windows.ps1 -Architecture x86_64`.
5. ZIP the resulting **Windows installer** and publish a GitHub release named
   `<upstream-tag>-wrap-100000-no-updates`, with asset
   `zed-windows-x86_64-<upstream-tag>-wrap-100000-no-updates.zip`. The ZIP is also
   retained as a workflow artifact for seven days. A new release stays a draft
   until its asset has uploaded successfully. The `-no-updates` suffix ensures
   an older wrap-only release cannot cause this patched version to be skipped.

For a manual build, open **Actions → Patched Zed stable for Windows → Run
workflow**. Manual runs also rebuild an already-published version and replace
its ZIP. There is no need to push a synthetic tag. The workflow requires the
repository's `GITHUB_TOKEN` to have release write access; it needs no custom
secrets.

### Match official Windows release settings

[`Build-Zed.ps1`](Build-Zed.ps1) invokes the stable source's complete bundling
script. Cargo commands, features, `.cargo/config.toml`,
`.cargo/bundle-config.toml`, release profile, licenses and runtime dependencies
are taken from upstream, not reconstructed here. `CARGO_INCREMENTAL=0` matches
the official Windows release job. The only host adaptation is locating Visual
Studio Enterprise on GitHub's runner instead of the hardcoded Community path
on upstream's self-hosted runner. The GitHub-hosted Windows 2022 image includes
Visual Studio C++ tools, Windows SDK 26100 and Inno Setup required by the bundler.

The old `Parse-Rustflags.ps1` has been removed: it depended on PSToml and edited
**this repository's** `.cargo/config.toml`, not Zed's checked-out configuration.
The old local Cargo configuration has also been removed; its forced full LTO
and disabled debug information did not match the official bundle profile.
There is no nightly override, OpenGL matrix or custom `RUSTFLAGS`.

This does **not** reproduce Zed Industries' code-signing certificate, private
service secrets or self-hosted hardware. The resulting installer is unsigned;
Windows may display a SmartScreen warning. Its release build settings match
upstream, but the patched binary is naturally not byte-identical to an official
release.

### Build cache

`Swatinem/rust-cache` caches Cargo downloads, installed Cargo tools and compiled
crates in `zed/target`, including workspace crates. Keys include the compiler,
manifest/lockfile configuration, bundle configuration and patch/build scripts.
The shared Windows x64 cache can restore compatible dependencies across stable
updates; a compiler/configuration change causes the appropriate cache miss.
Failed builds can also save partial work. Reuse reduces compilation work but
does not eliminate relinking; cache availability is subject to GitHub's quota
and eviction policy.

## Install and keep the patch

Download the ZIP from this repository's **Releases**, extract it, and run
`Zed-x86_64.exe`. This is an installer, not a standalone portable executable;
the official bundler includes the application's runtime dependencies. Since
the installer is already compressed, ZIP packaging may only marginally reduce
its size.

In Zed settings, use:

```json
{
  "soft_wrap": "none"
}
```

There is no need to set `auto_update`: updates are permanently disabled in the
compiled source, regardless of the setting's value. To update, download a newer
patched stable build from this repository and install it manually.

## Tests without compiling Zed

```powershell
pwsh -NoProfile -File ./tests/Test-Patch-Zed.ps1
```

These standalone tests verify both source patches, idempotence, CRLF
preservation and rejection of unsupported or partially patched upstream layouts
without modifying either source file. They do not install Rust or compile Zed.
Only GitHub Actions runs the build.
