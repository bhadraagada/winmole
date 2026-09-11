#!/usr/bin/env pwsh
# WinMole - System Status Monitor
# Wrapper for Go TUI application

#Requires -Version 5.1
param(
    [switch]$Help
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Get script directory
$script:WINMOLE_ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:WINMOLE_LIB = Join-Path $script:WINMOLE_ROOT "lib"
$script:WINMOLE_CMD = Join-Path $script:WINMOLE_ROOT "cmd"

# Import core
. "$script:WINMOLE_LIB\core\common.ps1"

# ============================================================================
# Help
# ============================================================================

function Show-StatusHelp {
    $cyan = $script:Colors.Cyan
    $gray = $script:Colors.Gray
    $green = $script:Colors.Green
    $nc = $script:Colors.NC
    
    Write-Host ""
    Write-Host "  ${green}STATUS${nc} - Real-time System Monitor"
    Write-Host ""
    Write-Host "  ${gray}Interactive TUI for monitoring system resources${nc}"
    Write-Host ""
    Write-Host "  ${green}USAGE:${nc}"
    Write-Host ""
    Write-Host "    winmole status"
    Write-Host ""
    Write-Host "  ${green}DISPLAYS:${nc}"
    Write-Host ""
    Write-Host "    ${cyan}CPU${nc}        Total usage with graph and core count"
    Write-Host "    ${cyan}Memory${nc}     RAM usage and availability"
    Write-Host "    ${cyan}Disk${nc}       Drive usage and free space"
    Write-Host "    ${cyan}Network${nc}    Bytes sent/received per interface"
    Write-Host "    ${cyan}Processes${nc}  Top five by CPU or memory usage"
    Write-Host ""
    Write-Host "  ${green}CONTROLS:${nc}"
    Write-Host ""
    Write-Host "    ${cyan}m${nc}          Toggle process sorting: CPU/memory"
    Write-Host "    ${cyan}c${nc}          Toggle WinMole animation"
    Write-Host "    ${cyan}r${nc}          Refresh now"
    Write-Host "    ${cyan}q/Ctrl+C${nc}   Quit"
    Write-Host ""
    Write-Host "  ${green}EXAMPLES:${nc}"
    Write-Host ""
    Write-Host "    ${gray}winmole status${nc}    ${gray}# Launch system monitor${nc}"
    Write-Host ""
}

# ============================================================================
# Build and Run
# ============================================================================

function Get-GoBinaryPath {
    $binaryName = "status.exe"
    $binPath = Join-Path $script:WINMOLE_ROOT "bin"
    return Join-Path $binPath $binaryName
}

function Build-StatusTool {
    $srcPath = Join-Path $script:WINMOLE_CMD "status"
    $binaryPath = Get-GoBinaryPath
    
    Write-Info "Building system monitor..."
    
    # Check if Go is installed
    $goCmd = Get-Command "go" -ErrorAction SilentlyContinue
    if (-not $goCmd) {
        Write-WinMoleError "Go is not installed or not in PATH"
        Write-Host ""
        Write-Host "  Install Go from: https://go.dev/dl/"
        Write-Host ""
        return $false
    }
    
    # Keep native stderr separate: PowerShell 5.1 treats merged progress messages as errors.
    try {
        Push-Location $srcPath
        
        # Download dependencies if needed
        if (-not (Test-Path (Join-Path $script:WINMOLE_ROOT "go.sum"))) {
            Write-Info "Downloading dependencies..."
            & go mod tidy | Out-Null
        }
        
        # Build
        $env:CGO_ENABLED = "0"
        $buildOutput = & go build -ldflags="-s -w" -o $binaryPath .
        
        if ($LASTEXITCODE -ne 0) {
            Write-WinMoleError "Build failed: $buildOutput"
            return $false
        }
        
        Write-Success "Build complete"
        return $true
    }
    catch {
        Write-WinMoleError "Build failed: $_"
        return $false
    }
    finally {
        Pop-Location
    }
}

function Invoke-StatusTool {
    $binaryPath = Get-GoBinaryPath
    
    # Build if binary doesn't exist or source is newer
    $srcPath = Join-Path $script:WINMOLE_CMD "status\main.go"
    $needsBuild = $false
    
    if (-not (Test-Path $binaryPath)) {
        $needsBuild = $true
    }
    elseif ((Get-Item $srcPath).LastWriteTime -gt (Get-Item $binaryPath).LastWriteTime) {
        $needsBuild = $true
    }
    
    if ($needsBuild) {
        if (-not (Build-StatusTool)) {
            throw 'Unable to build system monitor.'
        }
    }
    
    # Run the monitor
    & $binaryPath
}

# ============================================================================
# Main
# ============================================================================

function Main {
    # Initialize
    Initialize-WinMole
    
    if ($Help) {
        Show-StatusHelp
        return
    }
    
    # Run the status monitor
    Invoke-StatusTool
}

# Run
try {
    Main
}
catch {
    Write-Host ""
    Write-WinMoleError "An error occurred: $_"
    Write-Host ""
    exit 1
}
finally {
    Restore-WinMoleConsoleEncoding
}
