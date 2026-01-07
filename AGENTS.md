# AGENTS.md - Development Guide for WinMole

This guide provides AI coding assistants with essential commands, patterns, and conventions for working in the WinMole codebase.

**Quick reference**: Build/test commands, Safety rules, Architecture map, Code style

---

## Safety Checklist

Before any operation:

- Use `Remove-SafeItem` helpers (never raw `Remove-Item -Recurse -Force`)
- Check protection: `Test-ProtectedPath`, `Test-WhitelistedPath`
- Test first: `-WhatIf` parameter or `$env:WINMOLE_DRY_RUN = 1`
- Validate syntax: PowerShell parser
- Run tests: `Invoke-Pester -Path .\tests\`

## NEVER Do These

- Run `Remove-Item -Recurse -Force` on user-provided paths
- Delete files without checking protection lists
- Modify system-critical paths (e.g., `C:\Windows`, `C:\Program Files`)
- Commit code changes unless explicitly requested
- Run destructive operations without `-WhatIf` validation
- Use `$args` as a variable name (reserved in PowerShell)

## ALWAYS Do These

- Use `Remove-SafeItem` helper functions for deletions
- Respect whitelist files (`~\.config\winmole\whitelist`)
- Check protection logic before cleanup operations
- Test with `-WhatIf` mode first
- Validate syntax before suggesting changes
- Use `gh` CLI for GitHub operations when available
- Never commit code unless explicitly requested by user

---

## Quick Reference

### Build Commands

```powershell
# Build Go binaries
.\scripts\build.ps1

# Build specific binary
go build -o bin/analyze.exe ./cmd/analyze
go build -o bin/status.exe ./cmd/status

# Validate PowerShell scripts
.\scripts\build.ps1 validate

# Clean build artifacts
.\scripts\build.ps1 clean
```

### Test Commands

```powershell
# Run full test suite
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester -Path .\tests\ -ExcludeTag Integration

# Run specific test
Invoke-Pester -Path .\tests\WinMole.Tests.ps1

# PowerShell syntax check (all scripts)
Get-ChildItem -Path . -Filter *.ps1 -Recurse | ForEach-Object {
    $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors)
    if ($errors) { Write-Host "Errors in $($_.Name): $errors" }
}
```

### Development Commands

```powershell
# Test cleanup in dry-run mode
$env:WINMOLE_DRY_RUN = 1
.\winmole.ps1 clean

# Enable debug logging
$env:WINMOLE_DEBUG = 1
.\winmole.ps1 clean

# Test Go tool directly
go run ./cmd/analyze
go run ./cmd/status
```

---

## Architecture Quick Map

```
winmole/
├── winmole.ps1           # Main CLI entrypoint (menu + routing)
├── install.ps1           # Installer with PATH management
├── bin/                  # Command entry points
│   ├── clean.ps1         # Deep cleanup orchestrator
│   ├── uninstall.ps1     # App removal with leftover detection
│   ├── optimize.ps1      # Service refresh + optimization
│   ├── purge.ps1         # Developer artifact cleanup
│   ├── analyze.ps1       # Disk usage explorer wrapper
│   ├── status.ps1        # System health dashboard wrapper
│   ├── analyze.exe       # Compiled Go TUI
│   └── status.exe        # Compiled Go TUI
├── lib/                  # Reusable PowerShell logic
│   ├── core/             # base.ps1, log.ps1, file_ops.ps1, ui.ps1, common.ps1
│   └── clean/            # Cleanup modules (user.ps1, dev.ps1, system.ps1)
├── cmd/                  # Go applications
│   ├── analyze/          # Disk analysis tool
│   └── status/           # Real-time monitoring
├── scripts/              # Build and test automation
│   └── build.ps1         # Main build script
└── tests/                # Pester tests
    └── WinMole.Tests.ps1
```

**Decision Tree**:

- User cleanup logic -> `lib/clean/<module>.ps1`
- Command entry -> `bin/<command>.ps1`
- Core utils -> `lib/core/<util>.ps1`
- Performance tool -> `cmd/<tool>/*.go`
- Tests -> `tests/*.Tests.ps1`

### Language Stack

- **PowerShell 5.1**: Core cleanup and system operations (`lib/`, `bin/`)
- **Go**: Performance-critical TUI tools (`cmd/analyze/`, `cmd/status/`)
- **Pester**: Unit and integration testing (`tests/`)

---

## Code Style Guidelines

### PowerShell Scripts

- **Indentation**: 4 spaces
- **Variables**: `$PascalCase` for script-level, `$camelCase` for local
- **Functions**: `Verb-Noun` format (e.g., `Remove-SafeItem`, `Get-CacheSize`)
- **Parameters**: Use `[Parameter()]` attributes with proper types
- **Quoting**: Use double quotes for strings with variables, single for literals
- **Comparison**: Use `-eq`, `-ne`, `-gt` etc., not `==`, `!=`

### Go Code

- **Formatting**: Follow standard Go conventions (`gofmt`, `go vet`)
- **Build tags**: Use `//go:build windows` for Windows-specific code
- **Error handling**: Never ignore errors, always handle them explicitly

### Comments

- **Language**: English only
- **Focus**: Explain "why" not "what" (code should be self-documenting)
- **Safety**: Document safety boundaries explicitly

---

## Key Helper Functions

### Safety Helpers (lib/core/file_ops.ps1)

- `Remove-SafeItem -Path <path>`: Safe deletion with validation
- `Remove-OldFiles -Path <path> -Days <n>`: Delete files older than N days
- `Remove-EmptyDirectories -Path <path>`: Clean empty folders
- `Test-ProtectedPath -Path <path>`: Check if path is system-protected

### Logging (lib/core/log.ps1)

- `Write-WinMoleInfo <msg>`: Informational messages
- `Write-WinMoleSuccess <msg>`: Success notifications
- `Write-WinMoleWarning <msg>`: Warnings
- `Write-WinMoleError <msg>`: Error messages

### Size Helpers (lib/core/base.ps1)

- `Format-ByteSize -Bytes <n>`: Format bytes as human-readable
- `Get-DirectorySize -Path <path>`: Calculate directory size

---

## Testing Strategy

### Test Types

1. **Syntax Validation**: PowerShell parser checks
2. **Unit Tests**: Pester tests for individual functions
3. **Integration Tests**: Full command execution (tagged with `Integration`)
4. **Dry-run Tests**: `-WhatIf` to validate without deletion

### Test Environment Variables

- `$env:WINMOLE_DRY_RUN = 1`: Preview changes without execution
- `$env:WINMOLE_DEBUG = 1`: Enable detailed debug logging

---

## Common Development Tasks

### Adding New Cleanup Module

1. Create `lib/clean/new_module.ps1`
2. Implement cleanup logic using `Remove-SafeItem`
3. Source it in `lib/core/common.ps1`
4. Add protection checks for critical paths
5. Write Pester test in `tests/`
6. Test with `-WhatIf` first

### Modifying Go Tools

1. Navigate to `cmd/<tool>/`
2. Make changes to Go files
3. Test with `go run .`
4. Build: `go build -o bin/<tool>.exe .`
5. Check integration: `.\winmole.ps1 <command>`

### Debugging Issues

1. Enable debug mode: `$env:WINMOLE_DEBUG = 1`
2. Check output for error messages
3. Verify admin privileges if needed
4. Test individual functions in isolation

---

## Error Handling Patterns

### PowerShell Scripts

```powershell
try {
    # Operation that may fail
    Remove-Item -Path $path -ErrorAction Stop
}
catch {
    Write-WinMoleError "Failed to remove: $_"
    return $false
}
```

### Go Code

```go
if err != nil {
    return fmt.Errorf("operation failed: %w", err)
}
```

---

## Security Best Practices

### Path Validation

- Always validate user-provided paths
- Check against protection lists before operations
- Use absolute paths to prevent traversal
- Implement proper sandboxing for destructive operations

### Permission Management

- Request admin only when necessary
- Use `#Requires -RunAsAdministrator` for admin-only scripts
- Check permissions before attempting privileged operations

---

## Common Pitfalls to Avoid

1. **Using `$args`**: Reserved variable in PowerShell, use different names
2. **Backtick-e escapes**: `` `e `` not valid in PS 5.1, use `[char]27`
3. **Null array counts**: Wrap in `@()` before `.Count`
4. **Write-Error in functions**: Can cause parse errors, use Write-Host or throw
5. **Missing `-ErrorAction`**: Always specify for critical operations

---

## Resources

- Main script: `winmole.ps1` (menu + routing logic)
- Protection lists: Check `Test-ProtectedPath` implementation
- User config: `~\.config\winmole\`
- Test directory: `tests/`
- Build scripts: `scripts/`
- Documentation: `README.md`, `CONTRIBUTING.md`, `SECURITY_AUDIT.md`

---

**Remember**: When in doubt, err on the side of safety. It's better to clean less than to risk user data.
