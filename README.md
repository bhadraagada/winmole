# WinMole

**Windows System Maintenance Toolkit**

A comprehensive system maintenance toolkit for Windows, ported from the macOS [Mole](https://github.com/anomalyco/mole) project.

```
╦ ╦╦╔╗╔╔╦╗╔═╗╦  ╔═╗
║║║║║║║║║║║ ║║  ║╣ 
╚╩╝╩╝╚╝╩ ╩╚═╝╩═╝╚═╝
Windows System Maintenance
```

## Features

- **Deep System Cleanup** - Remove caches, temp files, logs, and browser data
- **Smart App Uninstaller** - Uninstall applications with leftover detection
- **Disk Space Analyzer** - Interactive TUI for exploring disk usage
- **Real-time System Monitor** - Monitor CPU, memory, disk, and network
- **System Optimization** - Defrag, TRIM, service optimization, startup management
- **Developer Artifact Purge** - Clean node_modules, target, build directories

## Requirements

- Windows 10/11
- PowerShell 5.1+ (included with Windows)
- Go 1.21+ (for building TUI tools - optional)

## Installation

### Quick Install

```powershell
# Clone or download the repository
git clone https://github.com/yourname/winmole.git
cd winmole

# Run the installer
.\install.ps1 -AddToPath
```

### Manual Install

```powershell
# Copy to your preferred location
Copy-Item -Path .\winmole -Destination "$env:LOCALAPPDATA\WinMole" -Recurse

# Add to PATH (optional)
$path = [Environment]::GetEnvironmentVariable("PATH", "User")
[Environment]::SetEnvironmentVariable("PATH", "$path;$env:LOCALAPPDATA\WinMole", "User")
```

### Install Options

```powershell
# Full installation with shortcut
.\install.ps1 -AddToPath -CreateShortcut

# Custom location
.\install.ps1 -InstallDir "C:\Tools\WinMole" -AddToPath

# Uninstall
.\install.ps1 -Uninstall
```

## Usage

### Interactive Mode

```powershell
winmole
```

This launches an interactive menu where you can select operations.

### Command Line

```powershell
# Deep system cleanup
winmole clean

# Preview cleanup (dry run)
winmole clean -DryRun

# Clean specific categories
winmole clean -User          # User caches only
winmole clean -System        # System caches (requires admin)
winmole clean -Dev           # Developer tools

# Uninstall applications
winmole uninstall

# Disk space analyzer
winmole analyze
winmole analyze C:\Users

# System monitor
winmole status

# System optimization
winmole optimize

# Clean developer artifacts
winmole purge
winmole purge -Path "C:\Projects"
```

## Commands

### `clean` - Deep System Cleanup

Removes temporary files, caches, logs, and other unnecessary data.

**Categories:**
- **User**: Browser caches, app caches, temp files, Recycle Bin
- **System**: Windows Update cache, system logs, memory dumps (requires admin)
- **Dev**: npm/pip/cargo caches, IDE caches

```powershell
winmole clean              # Interactive selection
winmole clean -All         # Clean everything
winmole clean -User        # User caches only
winmole clean -DryRun      # Preview without deleting
```

### `uninstall` - Smart App Uninstaller

Lists installed applications and helps remove them with leftover detection.

```powershell
winmole uninstall          # Interactive app selection
winmole uninstall -Search "Chrome"  # Search for specific app
```

### `analyze` - Disk Space Analyzer

Interactive TUI for exploring disk usage with visual size representation.

**Controls:**
- `↑/↓` or `j/k` - Navigate
- `Enter` - Expand/collapse directory
- `Backspace` - Go to parent
- `r` - Refresh
- `q` - Quit

```powershell
winmole analyze            # Analyze current directory
winmole analyze D:\        # Analyze specific path
```

### `status` - System Monitor

Real-time system resource monitoring with TUI.

**Displays:**
- CPU usage per core
- Memory usage
- Disk usage per drive
- Network throughput

```powershell
winmole status
```

### `optimize` - System Optimization

Performs system optimization tasks.

**Tasks:**
- Drive defragmentation/TRIM
- Service optimization
- Startup program management
- Network reset

```powershell
winmole optimize           # Interactive selection
winmole optimize -All      # Run all optimizations
```

### `purge` - Developer Artifact Cleanup

Finds and removes build artifacts from projects.

**Targets:**
- `node_modules` (Node.js)
- `target` (Rust/Java)
- `bin/obj` (.NET)
- `__pycache__` (Python)
- `.gradle`, `.maven` (Java)
- `build`, `dist` (Various)

```powershell
winmole purge              # Scan current directory
winmole purge -Path "C:\Projects"  # Scan specific path
winmole purge -DryRun      # Preview only
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

### Build Everything

```powershell
.\scripts\build.ps1
```

### Build Options

```powershell
.\scripts\build.ps1 go        # Build Go binaries only
.\scripts\build.ps1 validate  # Validate PowerShell scripts
.\scripts\build.ps1 test      # Run tests
.\scripts\build.ps1 clean     # Remove build artifacts
.\scripts\build.ps1 -Release  # Build optimized binaries
```

### Requirements for Building

- PowerShell 5.1+
- Go 1.21+ (for TUI tools)
- Pester module (for tests): `Install-Module Pester -Force`

## Testing

```powershell
# Run all tests
.\scripts\build.ps1 test

# Or directly with Pester
Invoke-Pester -Path .\tests\
```

## Project Structure

```
WinMole/
├── winmole.ps1           # Main CLI entry point
├── install.ps1           # Installer script
├── go.mod                # Go module file
├── bin/                  # Command scripts
│   ├── clean.ps1         # Cleanup orchestrator
│   ├── uninstall.ps1     # App uninstaller
│   ├── analyze.ps1       # Disk analyzer wrapper
│   ├── status.ps1        # System monitor wrapper
│   ├── optimize.ps1      # System optimizer
│   └── purge.ps1         # Artifact cleaner
├── lib/                  # Shared libraries
│   ├── core/             # Core modules
│   │   ├── common.ps1    # Module loader
│   │   ├── base.ps1      # Base functions
│   │   ├── log.ps1       # Logging
│   │   ├── file_ops.ps1  # Safe file operations
│   │   └── ui.ps1        # UI components
│   └── clean/            # Cleanup modules
│       ├── user.ps1      # User cleanup
│       ├── dev.ps1       # Developer cleanup
│       └── system.ps1    # System cleanup
├── cmd/                  # Go applications
│   ├── analyze/          # Disk analyzer TUI
│   └── status/           # System monitor TUI
├── scripts/              # Build scripts
│   └── build.ps1
└── tests/                # Pester tests
    └── WinMole.Tests.ps1
```

## Safety Features

- **Protected Paths**: System directories like `C:\Windows` and `C:\Program Files` are protected
- **Whitelist Support**: User-defined paths that should never be cleaned
- **Dry Run Mode**: Preview all changes before execution
- **Confirmation Prompts**: Destructive operations require confirmation
- **Admin Checks**: System-level operations require administrator privileges

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `.\scripts\build.ps1 test`
5. Submit a pull request

## License

MIT License - See LICENSE file for details.

## Credits

Ported from [Mole](https://github.com/anomalyco/mole) for macOS.
