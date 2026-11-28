# WinMole Desktop: command parity contract

**Goal:** a Windows user can complete every supported WinMole terminal workflow without opening a terminal. The desktop app should present the same operation, scope and outcome with mouse and keyboard, not send keystrokes to the TUI or create a second implementation of Windows maintenance. WinMole remains usable from the CLI.

The current command and flags below were checked against WinMole master at `9fd2cb5`. “Not yet” is a gap, not a hidden CLI fallback. This first implementation is a **read-only developer preview**, not a release or a replacement for the terminal.

| CLI surface | Desktop acceptance | Preview status |
| --- | --- | --- |
| Main menu, help and version | Named navigation for every command, contextual help, About/build version, and a settings screen for supported config. A shell is not required to make a setting, path, scope or error understandable. Keep CLI help and aliases intact. | Overview and Storage navigation; no common About/settings yet. |
| `status`, `status -Json` | Overview shows system identity/uptime, CPU and per-core readings, RAM/swap, disks/network and process data; sort/process detail, refresh, pause/resume, presentation settings, export the visible snapshot. Match unavailable and partial states and distinguish elapsed sampling from display pause. | One structured snapshot and explicit refresh/cancel; CPU, memory, swap, health and disks. Process/network/per-core/uptime, live sampling, settings, export are not wired. |
| `analyze [path]`, `analyze [path] -Json` | Folder/drive selection, drill-down, back, rescan, size/name sort, search, path access and export; show item counts and partial reasons, never imply the reported bytes are a complete total if incomplete. Cover analyzer selection and all single/batch delete semantics with an explicit fresh review and engine protections. | Read-only scan, browse/direct path, drill/down/up, refresh/cancel, item path, byte sizes, a selected item’s share of observed bytes and partial reasons. No search/sort controls, exports or deletion. |
| `clean`, `clean -DryRun`, `-All`, `-User`, `-Browsers`, `-Apps`, `-Caches`, `-GPUShaders`, `-Dev`, `-System`, `-RecycleBin`, `-WindowsUpdate`, `-GameMedia`, `-Orphaned` | Every engine-supported category discoverable with data type, privilege, side effects and protected/whitelisted/skipped entries. Scan is read-only; separately review exact work and request scoped elevation only when required. Distinguish permanent removal, Recycle Bin emptying and data that is not a cache. Display actual successes, skips and failures with reclaimed size, not only estimates. | Not yet. |
| `uninstall`, `-Rescan`, `-DebugMode` | Search/filter/rescan the same app inventory, including registry and Windows app entries, clear app identity and uninstall method, mark one or multiple, then review uninstall and leftover work separately. Keep protected apps inert. Preserve user-visible vendor UI where applicable. Show exit/reboot/failure separately from leftover outcomes; do not silently run another app's uninstaller. | Not yet. |
| `purge`, `-Paths`, `-DebugMode` | Display current project roots and edit the same configuration with explicit save; fail closed on unreadable configuration. Scan scoped roots, show detectable project/artifact/source and bytes, distinguish selected/unknown/skipped, review before removal and show actual per-item outcome. | Not yet. |
| `optimize`, `-DryRun`, `-DebugMode` | Surface health/repair checks, what each proposed action changes, admin/restart needs and system disruption. Keep preview separate from applying; don't silently flip services/network state. Report partial success and restart status. | Not yet. |
| Installation, update and WinMole self-removal (`install.ps1`) | Installation and app removal via standard Windows package UI where possible. A GUI setting should not bypass the user's installation provenance, script policy, PATH preferences or update choice. Never confuse removal of WinMole with app cleanup. | Outside this patch. |

Cross-cutting requirements:

- Provide keyboard navigation, visible focus, readable high-contrast layouts and meaningful screen-reader names. Use explicit labels and verbs instead of color alone. Visualize planned bytes, skipped entries and unavailable readings honestly, with an accessible non-visual equivalent.
- Continue using the existing policy, whitelist, protected-path and deletion backends. No `ExecutionPolicy Bypass`, prompt automation, arbitrary command strings, trip through an interactive terminal, or “always run as administrator.”
- Give mutating tools a structured **scan → review immutable plan → apply after fresh identity/protection check → outcome** interface. The planner exposes opaque candidate identity, origin, scope, time, privilege, estimates and skip/error reasons. Apply accepts explicit identifiers and expected identities, not arbitrary raw paths nor a parsed text preview. Changed scope, stale/missing scan, protected target or elevation refusal must block unsafe execution. Preserve audit distinctions for canceled, blocked, partial and failed operations. Under restricted PowerShell policy, explain unavailable functionality instead of weakening policy.
- Do not advertise full parity until every supported row has a Windows fixture through both entry points, including navigation/search, consent/elevation, partial results, and token/identity checks. Test deletion only against disposable sentinels; test UI consent independently from engine conditions.

## First desktop preview

This isolated Win32 shell uses the two existing, adjacent native read-only report helpers; no web server, network, third-party GUI dependency or PowerShell launcher is required for the two preview views. A GUI build is separate from the CLI/WinGet release work. Build with the repo's Go toolchain on Windows (matching architecture instructions for both helpers):

```powershell
go build -o bin/analyze.exe ./cmd/analyze
go build -o bin/status.exe ./cmd/status
go build -ldflags='-H=windowsgui' -o WinMoleDesktop.exe ./cmd/winmole-ui
.\WinMoleDesktop.exe
```

On a disposable Windows test machine/runner, run the read-only contract against the real staged native helpers:

```powershell
$env:WINMOLE_UI_HELPER_FIXTURE = (Get-Location).Path
go test -count=1 -v ./cmd/winmole-ui
```

The fixture checks Analyze/Status through the UI's adapter and only scans a throwaway directory. A separate visible smoke should verify that the window renders, Tab/Shift+Tab and access keys work, the folder picker works, and no terminal opens. No UI or filesystem guarantee follows from cross-building alone.

Storage initially asks for an explicit folder and does not scan the whole machine. Missing bundled helpers, cancellation, partial reasons and no results are visible. This does not test any mutating command, and is not evidence of a Windows runtime or an installer test.

Next integration increment: put one engine-backed **structured** Clean candidate category in the UI. Begin with user-cache scan, selected-item review and no-apply sentinels; only enable scoped apply after the shared backend and a native Windows fixture prove the protections above. Continue to Purge, Uninstall and Optimize while filling Status/Analyze gaps. Do not harden a one-off preview into a second maintenance engine.

## What to borrow from upstream Mole

Upstream [Mole](https://github.com/tw93/Mole) now documents a [separate native Windows app](https://mole.fit/windows) as well as Mac. Use the open CLI and public docs as behavioral references only: do not copy closed UI source/visual assets, and preserve licensing and upstream attribution for any code actually ported. These are operating-system translations, not drop-ins.

1. **Structured history**: upstream `mo history --json` distinguishes actions, sessions and ambiguous attribution. WinMole has logging and command summaries but not that reviewed desktop workflow. Build a local timeline with operation, outcome, actual reclaimed bytes (nullable), optional path details, retention and clear/export controls. Never present historical estimates as reclaimed space.
2. **Stale installers**: upstream `mo installer` separates installer files from already installed apps. On Windows, start with a review-only user-selected folder, age/size and conservative installer classifications. Leave MSI/EXE/MSIX and unknown ZIP files unselected by default; don't touch protected system installer caches or infer that every downloaded executable is safe to remove.
3. **Review UX and visual allocation**: upstream's public Windows page illustrates a treemap and explicit review. Design WinMole's own accessible visual map plus list, using the same scan results. Add **What grew since last scan?** as WinMole's complementary differentiator: store opt-in comparable local folder snapshots, disclose when scope or completeness prevents comparison, never convert a growth item into a deletion recommendation automatically.
4. **Not direct ports**: platform-specific items such as Touch ID, Apple-specific paths, launch frameworks and fan controls have no direct fit. Don't prioritize flashy new functionality ahead of existing CLI parity.
