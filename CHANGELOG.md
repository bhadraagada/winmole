# Changelog

All notable changes to WinMole are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Press `m` in the status dashboard to switch the top five processes between
  CPU and memory usage, including memory-heavy processes outside the CPU top five.

### Fixed

- Disk health now uses the fullest drive, so an earlier low-space warning cannot
  hide a critically full secondary drive. Existing thresholds and penalties remain.
- First-time analyzer, status, and script builds now tolerate Go download progress
  on stderr in Windows PowerShell 5.1. Build failures still show diagnostics, and
  analyzer and status commands exit with failure when compilation fails.

## [0.1.1] - 2026-07-31

### Fixed

- Interactive menus no longer stack a duplicate copy of themselves below the
  previous one on every keypress. All menu loops (`Show-Menu`,
  `Show-SelectionList`, purge's project picker and uninstall's app picker)
  repainted with `Clear-Host`, which is a no-op in some terminal hosts (e.g.
  Warp) and flickers in the rest. Frames are now redrawn in place with ANSI
  cursor control via a new `Write-MenuFrame` helper, which also keeps the
  banner and system info visible while navigating. (#31)
- Progress bars in `purge` and `uninstall` now advance correctly. The shared
  helper no longer shadows PowerShell's built-in `Write-Progress` cmdlet. (#18)

## [0.1.0] - 2026-07-28

First tagged release.

### Changed

- **License is now GPL-3.0, previously stated as MIT.** WinMole is a derivative
  work of [Mole](https://github.com/tw93/Mole), which is GPL-3.0 licensed, so
  WinMole must carry the same license. See [LICENSE](LICENSE) and the Credits
  section of the README.

### Fixed

- `clean` no longer fails on most of its flags. Six calls in `bin/clean.ps1`
  named functions that do not exist or passed parameters that were never
  declared, which broke `-Browsers`, `-Apps`, `-Dev`, `-System`,
  `-WindowsUpdate` and `-All`. (#14, via #11 and #12)
- The Recycle Bin is actually emptied now. `Clear-RecycleBin` shadowed the
  built-in cmdlet of the same name and called itself instead, recursing
  thousands of levels deep and reporting success without deleting anything.
  The call is now module-qualified. (#17)
- `clean -System` and `clean -All` no longer abort partway through on machines
  where the `wuauserv` service is unavailable. A property was read from a
  possibly-null service object outside any `try`, which terminated the run
  under StrictMode after earlier deletions had already been committed. (#19)
- `Get-InstalledPrograms` no longer throws on registry entries that have no
  `DisplayName`. (#11)
- `analyze` reports true directory sizes. Size walks stopped at depth 3, the
  system-directory skip list was matched against the bare folder name at every
  level (silently excluding `AppData\Local\Microsoft\Windows`), dot-directories
  were skipped, and a 500 ms / 10,000-file budget per directory returned partial
  results as if they were totals. Directory listings also dropped `Windows` and
  `Program Files` entirely, which is why whole-drive usage read far below
  Explorer. Trees are now walked to full depth with junctions and symlinks
  skipped, so nothing is double-counted or loops. Scans that are still cut short
  are marked `+` with a `≥` total rather than reported as exact. (#13)

### Added

- `Clear-UserCaches`, so `clean -User` works. (#12)
- A Pester regression test for `Get-InstalledPrograms` under StrictMode. (#11)
- Go test coverage for the disk analyzer, one case per root cause above plus a
  test pinning that protected system paths still refuse deletion. (#15)

### Known issues

- Progress bars in `purge` and `uninstall` are stuck at 0%, because a helper in
  `lib/core/log.ps1` shadows the built-in `Write-Progress` with an incompatible
  signature. (#18)

[0.1.1]: https://github.com/bhadraagada/winmole/releases/tag/v0.1.1
[0.1.0]: https://github.com/bhadraagada/winmole/releases/tag/v0.1.0
