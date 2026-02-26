# WinGet Manifests for WinMole

This directory contains WinGet manifests for WinMole.

## Files

- `winmole.yaml` - Version manifest
- `winmole.installer.yaml` - Installer manifest
- `winmole.locale.en-US.yaml` - Locale manifest

## Update Steps

1. Update `PackageVersion` in all three files.
2. Update `InstallerUrl` and `InstallerSha256` in `winmole.installer.yaml`.
3. Update `ReleaseNotesUrl` in `winmole.locale.en-US.yaml`.

## Validation

Use the WinGet manifest validation tool before submission.
