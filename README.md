# WinMole

*Deep clean and optimize your Windows PC.*

[![Stars](https://img.shields.io/github/stars/bhadraagada/winmole?style=flat-square)](https://github.com/bhadraagada/winmole/stargazers)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg?style=flat-square)](LICENSE)
[![Tests](https://img.shields.io/github/actions/workflow/status/bhadraagada/winmole/test.yml?branch=master&label=tests&style=flat-square)](https://github.com/bhadraagada/winmole/actions)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue?style=flat-square&logo=powershell)](https://docs.microsoft.com/en-us/powershell/)
[![Go](https://img.shields.io/badge/Go-1.24+-00ADD8?style=flat-square&logo=go)](https://go.dev/)

```
╦ ╦ ╦ ╔╗╔ ╔╦╗ ╔═╗ ╦   ╔═╗
║║║ ║ ║║║ ║║║ ║ ║ ║   ║╣ 
╚╩╝ ╩ ╝╚╝ ╩ ╩ ╚═╝ ╩═╝ ╚═╝
Windows System Maintenance
```

A comprehensive Windows port of the macOS [Mole](https://github.com/tw93/Mole) project.

## Features

- **All-in-one toolkit**: CCleaner, Revo Uninstaller, WinDirStat, and Task Manager combined into a **single tool**
- **Deep cleaning**: Scans and removes caches, logs, temp files, and browser data to **reclaim gigabytes of space**
- **Smart uninstaller**: Removes apps along with leftover files and **hidden remnants**
- **Disk insights**: Visualizes usage, manages large files, and explores disk space
- **Live monitoring**: Real-time stats for CPU, memory, disk, and network to **diagnose performance issues**
- **Developer cleanup**: Purges `node_modules`, `target`, `build`, and other **build artifacts**

## Quick Start

**Clone and run:**

```powershell
git clone https://github.com/bhadraagada/winmole.git
cd winmole

# Run interactive menu
.\winmole.ps1

# Or run specific commands
.\winmole.ps1 clean              # Deep cleanup
.\winmole.ps1 analyze            # Disk explorer
.\winmole.ps1 status             # System monitor
.\winmole.ps1 purge              # Clean dev artifacts
```

**Install to PATH (optional):**

```powershell
.\install.ps1 -AddToPath
```

## Commands

```powershell
winmole                      # Interactive menu
winmole clean                # Deep system cleanup
winmole clean -DryRun        # Preview cleanup (safe mode)
winmole uninstall            # Remove apps + leftovers
winmole optimize             # System optimization
winmole analyze              # Visual disk explorer
winmole status               # Live system dashboard
winmole purge                # Clean build artifacts
winmole --help               # Show help
```

## Features in Detail

### Deep System Cleanup

```powershell
.\winmole.ps1 clean

Scanning cache directories...

  ✓ User temp files                                          2.3 GB
  ✓ Browser cache (Chrome, Edge, Firefox)                    1.8 GB
  ✓ Windows Update cache                                     4.2 GB
  ✓ Developer tools (npm, pip, cargo)                        3.1 GB
  ✓ System logs and crash dumps                              0.5 GB
  ✓ Recycle Bin                                              1.2 GB

====================================================================
Space freed: 13.1 GB | Free space now: 156.3 GB
====================================================================
```

### Disk Space Analyzer

```powershell
.\winmole.ps1 analyze

Analyze Disk  C:\Users  |  Total: 89.2 GB

 ▶  1. ███████████████████  48.2%  |  📁 AppData                     43.0 GB
    2. ██████████░░░░░░░░░  22.1%  |  📁 Downloads                   19.7 GB
    3. ████░░░░░░░░░░░░░░░  14.3%  |  📁 Documents                   12.8 GB
    4. ███░░░░░░░░░░░░░░░░  10.8%  |  📁 Desktop                      9.6 GB
    5. ██░░░░░░░░░░░░░░░░░   4.6%  |  📄 Videos                       4.1 GB

  ↑↓ Navigate  |  Enter Expand  |  Backspace Back  |  Q Quit
```

Press `Backspace`, `Left`, or `h` to return to the previous directory. At the
starting directory, the same keys scan its parent, so you can explore above the
path you launched with. While a scan runs, wait for it to finish or press `q` or
`Ctrl+C` to quit.

### Save a disk usage report

```powershell
# Read-only scan, with no interactive terminal or deletion commands
.\winmole.ps1 analyze 'C:\Projects' -Json | Set-Content -Encoding UTF8 usage.json
$report = Get-Content -Raw usage.json | ConvertFrom-Json
$report.entries | Select-Object name, size_bytes, partial

# Standalone binary: put flags before a positional path
.\bin\analyze.exe -json -path 'C:\Projects'
```

The report contains `path`, `total_bytes`, `partial`, and `entries`. Each entry
contains `name`, `path`, `size_bytes`, `is_directory`, and `partial`. Paths are
absolute. Entries describe immediate children, with recursively measured sizes
for directories, sorted by size descending and then name. Empty directories
produce an empty `entries` array.

When `partial` is true, the corresponding byte count is a lower bound because
a scan timed out, hit its file limit, or could not read an entry. The report's
`partial` flag is true if any entry is partial. Invalid or unreadable root
directories return a nonzero exit code and an error on stderr. Reports use the
same scan limits as the interactive analyzer.

### Live System Status

The network panel shows upload and download rates per interface in bytes per
second. Rates start at zero until two samples are available and reset safely
when an interface reconnects or its counters restart.

```powershell
.\winmole.ps1 status

WinMole Status  Health ● 87  Windows 11 · AMD Ryzen 7 · 32 GB

⚙ CPU                                    ▦ Memory
Total   ████████████░░░░░░░  45.2%       Used    ███████████░░░░░░░  58.4%
Load    8 cores @ 3.8 GHz                Total   18.7 / 32.0 GB
                                         Free    ████████░░░░░░░░░░  41.6%

▤ Disk                                   ⇅ Network
C:      █████████████░░░░░░  67.2%       Down    ▮▮▯▯▯  3.2 MB/s
Free    156.3 GB / 476.9 GB              Up      ▮▯▯▯▯  0.8 MB/s
```

Press `m` in the status dashboard to switch the top five processes between CPU
and memory usage. CPU is the default; the process heading shows the active sort.

Each drive shows its used and total capacity, usage percentage, and free space
beside the usage bar. Free space updates with each metrics refresh.

### Developer Artifact Purge

```powershell
.\winmole.ps1 purge

Select Categories to Clean - 18.5 GB (8 selected)

➤ ● my-react-app       3.2 GB | node_modules
  ● old-project        2.8 GB | node_modules
  ● rust-app           4.1 GB | target
  ● dotnet-api         2.3 GB | bin/obj
  ○ current-work       856 MB | node_modules  | Recent
```

## Tips

- **Safety**: Built with strict protections. Preview changes with `winmole clean -DryRun`
- **Whitelist**: Protect paths by adding them to `~\.config\winmole\whitelist`
- **Navigation**: Supports arrow keys and Vim bindings (`h/j/k/l`) in TUI tools
- **Debug**: View detailed logs with `$env:WINMOLE_DEBUG = 1`

## Requirements

- Windows 10/11
- PowerShell 5.1+ (included with Windows)
- Go 1.24+ (optional, for building TUI tools)

## Installation Options

```powershell
# Quick install with PATH
.\install.ps1 -AddToPath

# Custom location
.\install.ps1 -InstallDir "C:\Tools\WinMole" -AddToPath

# Create desktop shortcut
.\install.ps1 -AddToPath -CreateShortcut

# Uninstall
.\install.ps1 -Uninstall
```

## Configuration

Configuration files are stored in `~\.config\winmole\`:

- `whitelist` - Paths to never clean (one per line)
- `config.json` - General settings

### Whitelist Example

```
# ~/.config/winmole/whitelist
C:\Users\me\AppData\Local\ImportantApp
C:\Projects\MyProject\node_modules
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `WINMOLE_DRY_RUN=1` | Preview mode - no actual deletions |
| `WINMOLE_DEBUG=1` | Enable debug output |

## Building from Source

```powershell
# Build Go binaries
.\scripts\build.ps1

# Run tests
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester -Path .\tests\ -ExcludeTag Integration

# Validate scripts
.\scripts\build.ps1 validate
```

## Project Structure

```
winmole/
├── winmole.ps1           # Main CLI entry point
├── install.ps1           # Installer script
├── bin/                  # Command scripts + binaries
│   ├── clean.ps1         # Cleanup orchestrator
│   ├── analyze.exe       # Disk analyzer TUI
│   └── status.exe        # System monitor TUI
├── lib/                  # Shared libraries
│   ├── core/             # Core modules
│   └── clean/            # Cleanup modules
├── cmd/                  # Go source code
│   ├── analyze/          # Disk analyzer
│   └── status/           # System monitor
└── tests/                # Pester tests
```

## Safety Features

- **Protected Paths**: System directories like `C:\Windows` and `C:\Program Files` are always protected
- **Whitelist Support**: User-defined paths that should never be cleaned
- **Dry Run Mode**: Preview all changes before execution with `-DryRun`
- **Confirmation Prompts**: Destructive operations require confirmation
- **Admin Checks**: System-level operations require administrator privileges

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) and check the [Security Audit](SECURITY_AUDIT.md) before making changes.

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `Invoke-Pester -Path .\tests\`
5. Submit a pull request

## License

GNU General Public License v3.0 - See [LICENSE](LICENSE) for the full text.

WinMole is a derivative work of [Mole](https://github.com/tw93/Mole), which is
licensed under GPL-3.0, so WinMole is distributed under the same license.

## Credits

WinMole is derived from [Mole](https://github.com/tw93/Mole) by
[tw93](https://github.com/tw93) - specifically its
[`windows` branch](https://github.com/tw93/Mole/tree/windows) - and adapted for
Windows with PowerShell 5.1 support.

Changes from upstream include a flag-based `clean` dispatcher, restructured
cleanup modules, a rewritten disk-size scanner, and an added Pester and Go test
suite. Upstream Mole remains the original work; please star it too.

---

**If WinMole saved you disk space, consider starring the repo!** ⭐
