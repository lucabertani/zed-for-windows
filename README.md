# Patched Zed stable for Windows

This repository builds an **unofficial, patched Windows x64 release** of
[Zed](https://github.com/zed-industries/zed), distributed as a **standalone
application ZIP, not an installer**. Extract the entire ZIP and double-click
`zed.exe` to launch Zed directly. Zed already officially supports Windows; this
build exists for the disabled-soft-wrap patch and permanently blocks upstream
updates that would replace it.

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

## One active workflow

[`.github/workflows/windows-standalone.yml`](.github/workflows/windows-standalone.yml)
is the only active workflow. The old installer workflow and its build wrapper
are preserved under [`archive/windows-installer/`](archive/windows-installer/README.md),
outside `.github/workflows`, so GitHub does not run them.

1. Every day at **03:00 UTC**, query the official repository's latest published
   stable release (not `main`, nightly or preview), then resolve its tag to an
   immutable source commit.
2. Skip both scheduled and manual builds if that version already has a published
   patched ZIP, unless a manual run explicitly enables `force`.
3. Check out the source and always apply and verify both patches before compiling.
4. Build **Windows x64 only**, on `windows-2022`, using the Rust toolchain from
   that stable's `rust-toolchain.toml` and its official Windows release Cargo
   configuration. Build the application and CLI directly, without invoking the
   installer bundler, Inno Setup, Explorer integration or the update helper.
5. Collect the **real Cargo-built `zed.exe`**, CLI, required runtime files and
   licenses, then publish their ZIP in a GitHub release named
   `<upstream-tag>-wrap-100000-no-updates-standalone`, with asset
   `zed-windows-x86_64-<upstream-tag>-wrap-100000-no-updates-standalone.zip`.
   The ZIP is also retained as a workflow artifact for seven days. A new release
   stays a draft until its asset has uploaded successfully. The `-standalone`
   suffix prevents an older installer release from skipping the new app build.

For a manual build, open **Actions → Patched Zed stable for Windows (standalone)
→ Run workflow**. The boolean **force** input is unchecked by default:

- **force off (default):** skip compilation if the patched release for the latest
  stable already exists and its ZIP is uploaded. A missing release, draft release
  or missing/incomplete ZIP still triggers a build.
- **force on:** rebuild the latest stable even if already published, then replace
  its ZIP in the same release.

Scheduled runs never force a rebuild. There is no need to push a synthetic tag.
The workflow requires the repository's `GITHUB_TOKEN` to have release write
access; it needs no custom secrets.

### Match official Windows release settings

[`Build-Zed.ps1`](Build-Zed.ps1) builds `zed` and `cli` with the same
`cargo --config .cargo/bundle-config.toml build --release --target x86_64-pc-windows-msvc`
settings used for the application in the official Windows bundler. The stable's
`.cargo/config.toml`, bundle optimizations, release profile and default features
remain unchanged. `CARGO_INCREMENTAL=0` matches the official release job. The
wrapper locates Visual Studio on the runner and runs upstream's license
asset generator before compiling.

Only the `DownloadAMDGpuServices` and `DownloadConpty` function definitions are
imported from the stable's bundling script to download its exact runtime
versions. The bundler itself and its top-level commands are **never executed**.
There is no installer, update-helper, Explorer extension, AppX or remote-server
build. The GitHub-hosted Windows 2022 image supplies the required Visual Studio
C++ tools and Windows SDK.

[`Package-Zed.ps1`](Package-Zed.ps1) takes the application from
`zed/target/x86_64-pc-windows-msvc/release/zed.exe`, **not** the installer at
`zed/target/Zed-x86_64.exe`. It includes AMD GPU Services, ConPTY and OpenConsole
in upstream's runtime layout. Release assets (fonts, themes and icons) are
embedded by upstream's release build. Packaging fails if any required file is
missing, rather than publishing an incomplete standalone ZIP.

The old `Parse-Rustflags.ps1` has been removed: it depended on PSToml and edited
**this repository's** `.cargo/config.toml`, not Zed's checked-out configuration.
The old local Cargo configuration has also been removed; its forced full LTO
and disabled debug information did not match the official bundle profile.
There is no nightly override, OpenGL matrix or custom `RUSTFLAGS`.

This does **not** reproduce Zed Industries' code-signing certificate, private
service secrets or self-hosted hardware. The resulting application is unsigned;
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

## Run directly and keep the patch

Download the **standalone** ZIP from this repository's Releases, extract the
**entire archive** to a folder, then double-click **`zed.exe`** at its root.
It launches the editor directly: no setup wizard, installation, administrative
permissions or registry setup is needed. Do not run it from inside the ZIP or
copy only the EXE: keep the runtime files and subfolders with it.

```text
zed.exe                 # The actual editor; double-click this
bin/zed.exe             # Optional CLI launcher
amd_ags_x64.dll
conpty.dll
x64/OpenConsole.exe
arm64/OpenConsole.exe
LICENSE-GPL
LICENSE-APACHE
licenses.md
README.txt
```

This is a standalone application folder, not a single-file EXE and not an
isolated portable profile. Settings, extensions and user data still use Zed's
normal Windows profile directories. The ZIP does not install Explorer
integration, register file associations or create shortcuts. Older release
assets without the `-standalone` suffix are installer ZIPs; do not use those
if you want the application directly.

In Zed settings, use:

```json
{
  "soft_wrap": "none"
}
```

There is no need to set `auto_update`: updates are permanently disabled in the
compiled source, regardless of the setting's value. To update, download a newer
patched standalone ZIP from this repository, close Zed and extract it into a
new folder.

## Tests without compiling Zed

```powershell
pwsh -NoProfile -File ./tests/Test-Patch-Zed.ps1
pwsh -NoProfile -File ./tests/Test-Package-Zed.ps1
```

The tests verify both source patches, idempotence, CRLF preservation and
rejection of unsupported upstream layouts. Packaging tests use marker files
to verify that the ZIP contains the actual application at its root, includes
runtime dependencies, excludes installers/debug symbols, and rejects incomplete
packages or overwrites. They do not install Rust, compile Zed or launch an
installer. Only GitHub Actions runs the build.
