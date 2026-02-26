# WinMole - Build Script
# Builds Go binaries and validates PowerShell scripts

#Requires -Version 5.1
param(
    [switch]$Clean,
    [switch]$Release,
    [switch]$Validate,
    [switch]$ShowHelp
)

$ErrorActionPreference = "Stop"

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$windowsDir = Split-Path -Parent $scriptDir
$binDir = Join-Path $windowsDir "bin"

function Show-BuildHelp {
    Write-Host ""
    Write-Host "WinMole Build Script" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\build.ps1 [options]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Clean      Clean build artifacts before building"
    Write-Host "  -Release    Build optimized release binaries"
    Write-Host "  -Validate   Validate PowerShell script syntax"
    Write-Host "  -ShowHelp   Show this help message"
    Write-Host ""
}

if ($ShowHelp) {
    Show-BuildHelp
    return
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  WinMole - Build" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Clean
# ============================================================================

if ($Clean) {
    Write-Host "[Clean] Removing build artifacts..." -ForegroundColor Yellow
    
    $artifacts = @(
        (Join-Path $binDir "analyze.exe"),
        (Join-Path $binDir "status.exe"),
        (Join-Path $windowsDir "coverage-go.out"),
        (Join-Path $windowsDir "coverage-pester.xml")
    )
    
    foreach ($artifact in $artifacts) {
        if (Test-Path $artifact) {
            Remove-Item $artifact -Force
            Write-Host "  Removed: $artifact" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
}

# ============================================================================
# Validate PowerShell Scripts
# ============================================================================

if ($Validate) {
    Write-Host "[Validate] Checking PowerShell script syntax..." -ForegroundColor Yellow
    
    $scripts = Get-ChildItem -Path $windowsDir -Filter "*.ps1" -Recurse
    $errors = @()
    
    foreach ($script in $scripts) {
        try {
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script.FullName,
                [ref]$null,
                [ref]$null
            )
            Write-Host "  OK: $($script.Name)" -ForegroundColor Green
        }
        catch {
            Write-Host "  ERROR: $($script.Name)" -ForegroundColor Red
            $errors += $script.FullName
        }
    }
    
    if ($errors.Count -gt 0) {
        Write-Host ""
        Write-Host "  $($errors.Count) script(s) have syntax errors!" -ForegroundColor Red
        exit 1
    }
    
    Write-Host ""
}

# ============================================================================
# Build Go Binaries
# ============================================================================

Write-Host "[Build] Building Go binaries..." -ForegroundColor Yellow

# Check if Go is installed
$goVersion = & go version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Error: Go is not installed" -ForegroundColor Red
    Write-Host "  Please install Go from https://golang.org/dl/" -ForegroundColor Gray
    exit 1
}

Write-Host "  $goVersion" -ForegroundColor Gray
Write-Host ""

# Create bin directory if needed
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}

Push-Location $windowsDir
try {
    # Build flags
    $ldflags = ""
    if ($Release) {
        $ldflags = "-s -w"  # Strip debug info for smaller binaries
    }
    
    # Build analyze
    Write-Host "  Building analyze.exe..." -ForegroundColor Gray
    if ($Release) {
        & go build -ldflags "$ldflags" -o "$binDir\analyze.exe" "./cmd/analyze/"
    }
    else {
        & go build -o "$binDir\analyze.exe" "./cmd/analyze/"
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to build analyze.exe" -ForegroundColor Red
        exit 1
    }
    
    $analyzeSize = (Get-Item "$binDir\analyze.exe").Length / 1MB
    Write-Host "  Built: analyze.exe ($([math]::Round($analyzeSize, 2)) MB)" -ForegroundColor Green
    
    # Build status
    Write-Host "  Building status.exe..." -ForegroundColor Gray
    if ($Release) {
        & go build -ldflags "$ldflags" -o "$binDir\status.exe" "./cmd/status/"
    }
    else {
        & go build -o "$binDir\status.exe" "./cmd/status/"
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to build status.exe" -ForegroundColor Red
        exit 1
    }
    
    $statusSize = (Get-Item "$binDir\status.exe").Length / 1MB
    Write-Host "  Built: status.exe ($([math]::Round($statusSize, 2)) MB)" -ForegroundColor Green
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Build complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
