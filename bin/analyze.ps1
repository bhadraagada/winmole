#!/usr/bin/env pwsh
# WinMole - Disk Space Analyzer
# Wrapper for Go TUI application

#Requires -Version 5.1
param(
    [Parameter(Position = 0)]
    [string]$Path,
    
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

function Show-AnalyzeHelp {
    $cyan = $script:Colors.Cyan
    $gray = $script:Colors.Gray
    $green = $script:Colors.Green
    $nc = $script:Colors.NC
    
    Write-Host ""
    Write-Host "  ${green}ANALYZE${nc} - Disk Space Analyzer"
    Write-Host ""
    Write-Host "  ${gray}Interactive TUI for exploring disk usage${nc}"
    Write-Host ""
    Write-Host "  ${green}USAGE:${nc}"
    Write-Host ""
    Write-Host "    winmole analyze [path]"
    Write-Host ""
    Write-Host "  ${green}ARGUMENTS:${nc}"
    Write-Host ""
    Write-Host "    ${cyan}path${nc}    Directory to analyze (default: current directory)"
    Write-Host ""
    Write-Host "  ${green}CONTROLS:${nc}"
    Write-Host ""
    Write-Host "    ${cyan}Up/k${nc}    Move up"
    Write-Host "    ${cyan}Down/j${nc}  Move down"
    Write-Host "    ${cyan}Enter${nc}   Expand/collapse directory"
    Write-Host "    ${cyan}Backspace${nc} Go to parent directory"
    Write-Host "    ${cyan}r${nc}       Refresh"
    Write-Host "    ${cyan}q/Esc${nc}   Quit"
    Write-Host ""
    Write-Host "  ${green}EXAMPLES:${nc}"
    Write-Host ""
    Write-Host "    ${gray}winmole analyze${nc}              ${gray}# Analyze current directory${nc}"
    Write-Host "    ${gray}winmole analyze C:\Users${nc}     ${gray}# Analyze specific path${nc}"
    Write-Host "    ${gray}winmole analyze D:\${nc}          ${gray}# Analyze entire drive${nc}"
    Write-Host ""
}

# ============================================================================
# Build and Run
# ============================================================================

function Get-GoBinaryPath {
    $binaryName = "analyze.exe"
    $binPath = Join-Path $script:WINMOLE_ROOT "bin"
    return Join-Path $binPath $binaryName
}

function Build-AnalyzeTool {
    $srcPath = Join-Path $script:WINMOLE_CMD "analyze"
    $binaryPath = Get-GoBinaryPath
    
    Write-Info "Building disk analyzer..."
    
    # Check if Go is installed
    $goCmd = Get-Command "go" -ErrorAction SilentlyContinue
    if (-not $goCmd) {
        Write-Host "  ERROR: Go is not installed or not in PATH" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Install Go from: https://go.dev/dl/"
        Write-Host ""
        return $false
    }
    
    # Build the binary
    try {
        Push-Location $srcPath
        
        # Download dependencies if needed
        if (-not (Test-Path (Join-Path $script:WINMOLE_ROOT "go.sum"))) {
            Write-Info "Downloading dependencies..."
            & go mod tidy 2>&1 | Out-Null
        }
        
        # Build
        $env:CGO_ENABLED = "0"
        $buildOutput = & go build -ldflags="-s -w" -o $binaryPath . 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: Build failed: $buildOutput" -ForegroundColor Red
            return $false
        }
        
        Write-Success "Build complete"
        return $true
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-Host "  ERROR: Build failed: $errMsg" -ForegroundColor Red
        return $false
    }
    finally {
        Pop-Location
    }
}

function Invoke-AnalyzeTool {
    param([string]$TargetPath)
    
    $binaryPath = Get-GoBinaryPath
    
    # Build if binary doesn't exist or source is newer
    $srcPath = Join-Path $script:WINMOLE_CMD "analyze\main.go"
    $needsBuild = $false
    
    if (-not (Test-Path $binaryPath)) {
        $needsBuild = $true
    }
    elseif ((Get-Item $srcPath).LastWriteTime -gt (Get-Item $binaryPath).LastWriteTime) {
        $needsBuild = $true
    }
    
    if ($needsBuild) {
        if (-not (Build-AnalyzeTool)) {
            return
        }
    }
    
    # Run the analyzer
    $analyzeArgs = @()
    if ($TargetPath) {
        $analyzeArgs += $TargetPath
    }
    
    & $binaryPath @analyzeArgs
}

# ============================================================================
# Main
# ============================================================================

function Main {
    # Initialize
    Initialize-WinMole
    
    if ($Help) {
        Show-AnalyzeHelp
        return
    }
    
    # Determine target path
    $targetPath = if ($Path) { 
        $Path 
    } else { 
        Get-Location 
    }
    
    # Validate path
    if (-not (Test-Path $targetPath)) {
        Write-Host "  ERROR: Path does not exist: $targetPath" -ForegroundColor Red
        return
    }
    
    # Run the analyzer
    Invoke-AnalyzeTool -TargetPath $targetPath
}

# Run
try {
    Main
}
catch {
    Write-Host ""
    $errMsg = $_.Exception.Message
    Write-Host "  ERROR: An error occurred: $errMsg" -ForegroundColor Red
    Write-Host ""
    exit 1
}
