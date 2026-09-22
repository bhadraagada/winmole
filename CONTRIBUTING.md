# Contributing to WinMole

Thank you for your interest in contributing to WinMole! This document provides guidelines and instructions for contributing.

## Setup

```powershell
# Clone the repository
git clone https://github.com/bhadraagada/winmole.git
cd winmole

# Install Pester for testing
Install-Module Pester -Force -SkipPublisherCheck

# Install Go (for TUI components)
# Download from https://go.dev/dl/
```

## Development

### Running Tests

```powershell
# Run all tests
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester -Path .\tests\ -ExcludeTag Integration

# Run specific test file
Invoke-Pester -Path .\tests\Commands.Tests.ps1
```

### Building Go Binaries

```powershell
# Build all binaries
.\scripts\build.ps1

# Build specific binary
go build -o bin/analyze.exe ./cmd/analyze
go build -o bin/status.exe ./cmd/status
```

### Validating Scripts

```powershell
# Check PowerShell syntax
.\scripts\build.ps1 validate
```

## Code Style

### PowerShell Scripts

- **Indentation**: 4 spaces
- **Variables**: `$PascalCase` for script-level, `$camelCase` for local
- **Functions**: `Verb-Noun` format (e.g., `Remove-SafeItem`, `Get-CacheSize`)
- **Parameters**: Use `[Parameter()]` attributes with proper types
- **Error handling**: Use `try/catch` for operations that may fail
- **Comments**: Explain "why" not "what"

Reuse the functions in `lib/core/file_ops.ps1` for deletion. Do not redefine
`Remove-SafeItem`; its protection, whitelist, and dry-run checks belong in one place.

### Go Code

- Follow standard Go conventions (`gofmt`, `go vet`)
- Use `//go:build windows` for Windows-specific code
- Handle errors explicitly, never ignore them
- Add package-level documentation for exported functions

## File Operations

**Always use safe wrappers, never raw `Remove-Item` on user paths:**

```powershell
. .\lib\core\file_ops.ps1
Set-DryRunMode -Enabled $true

# Preview a file or directory, including its contents
Remove-SafeItem -Path "C:\path\to\file"
Remove-SafeItem -Path "C:\path\to\dir" -Recurse
```

`Remove-SafeItem` does not support `-WhatIf`. Use `Set-DryRunMode` after loading
the helpers, or set `$env:WINMOLE_DRY_RUN = '1'` before loading them in a fresh
PowerShell session. For the cleanup command, use `winmole clean -DryRun`.
Keep preview mode enabled while developing; disabling it allows real deletion.

See `lib/core/file_ops.ps1` for all safe functions.

## Safety Rules

### NEVER Do These

- Use raw `Remove-Item -Recurse -Force` on user-provided paths
- Delete files without checking protection lists
- Modify system-critical paths (e.g., `C:\Windows`, `C:\Program Files`)
- Commit code changes unless explicitly requested
- Run destructive operations without dry-run validation

### ALWAYS Do These

- Use `Remove-SafeItem` or other safe helpers for deletions
- Check `Test-ProtectedPath` before cleanup operations
- Test with the helper's dry-run mode first
- Validate syntax before suggesting changes
- Write tests for new functionality

## Testing Strategy

### Test Types

1. **Syntax Validation**: PowerShell parser checks
2. **Unit Tests**: Pester tests for individual functions
3. **Integration Tests**: Full command execution (tagged with `Integration`)
4. **Dry-run Tests**: `Set-DryRunMode -Enabled $true` to validate without deletion

### Writing Tests

```powershell
Describe "Remove-SafeItem" {
    BeforeAll {
        . "$PSScriptRoot\..\lib\core\file_ops.ps1"
        $script:previousDryRun = $script:DryRun
        Set-DryRunMode -Enabled $true
    }

    AfterAll {
        Set-DryRunMode -Enabled $script:previousDryRun
    }
    
    It "Should return false for protected paths" {
        $result = Remove-SafeItem -Path "C:\Windows"
        $result | Should -Be $false
    }
    
    It "Should preserve files during a preview" {
        $testFile = Join-Path $TestDrive "test.txt"
        "test" | Set-Content $testFile
        
        Remove-SafeItem -Path $testFile | Should -Be $true
        
        Test-Path $testFile | Should -Be $true
    }
}
```

## Pull Requests

> **Important:** Please submit PRs to the `master` branch (the repository default).

1. Fork and create branch from `master`
2. Make your changes
3. Run tests: `Invoke-Pester -Path .\tests\`
4. Commit with descriptive message
5. Open PR targeting `master`

### Commit Messages

Use descriptive commit messages:

```
feat: add Windows Defender scan integration
fix: handle null arrays in Remove-EmptyDirectories
docs: update installation instructions
refactor: extract cache cleanup into separate module
test: add tests for Format-ByteSize function
```

## Project Structure

```
winmole/
├── winmole.ps1           # Main CLI entry point
├── install.ps1           # Installer script
├── bin/                  # Command scripts + compiled binaries
│   ├── clean.ps1         # Cleanup orchestrator
│   ├── uninstall.ps1     # App uninstaller
│   ├── optimize.ps1      # System optimizer
│   ├── purge.ps1         # Artifact cleaner
│   ├── analyze.ps1       # Disk analyzer wrapper
│   ├── status.ps1        # System monitor wrapper
│   ├── analyze.exe       # Compiled Go TUI
│   └── status.exe        # Compiled Go TUI
├── lib/                  # Shared libraries
│   ├── core/             # Core modules
│   └── clean/            # Cleanup modules
├── cmd/                  # Go applications
│   ├── analyze/          # Disk analyzer TUI
│   └── status/           # System monitor TUI
├── scripts/              # Build scripts
└── tests/                # Pester tests
```

## Requirements

- Windows 10/11
- PowerShell 5.1+ (included with Windows)
- Go 1.24+ (for building TUI tools)
- Pester 5.0+ (for running tests)

## Getting Help

- Open an issue for bugs or feature requests
- Check existing issues before creating new ones
- Provide clear reproduction steps for bugs

## License

By contributing, you agree that your contributions will be licensed under the GPL-3.0 License.
