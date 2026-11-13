# Archived Windows installer workflow

These files preserve the previous installer-based build:

- `daily-release.yml`: workflow that produces a ZIP containing the Inno Setup installer.
- `Build-Zed.ps1`: wrapper that runs upstream's complete Windows bundler.

They intentionally live **outside `.github/workflows`** and are not an active
GitHub Actions workflow. The active pipeline is
[`../../.github/workflows/windows-standalone.yml`](../../.github/workflows/windows-standalone.yml),
which publishes the actual application instead.

The archived workflow retains the stable selection, mandatory patches, Cargo
cache, `force` input and GitHub release publishing. Its build step points to
`archive/windows-installer/Build-Zed.ps1`, so it will not accidentally invoke the
new root-level standalone builder.

If the installer is needed in the future, first move the standalone workflow
out of `.github/workflows`, then copy this `daily-release.yml` back into
`.github/workflows`. Review its upstream compatibility before running it. Do
not move the archived build wrapper to the root: the restored workflow uses
its archived path. The installer release tags deliberately omit `-standalone`,
so they do not overwrite standalone application releases.
