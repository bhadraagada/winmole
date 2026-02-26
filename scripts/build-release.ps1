# WinMole - Release Build Script
# Builds release artifacts for distribution via package managers
# Outputs: ZIP, EXE, and generates SHA256 hashes

#Requires -Version 5.1
param(
    [Parameter(Mandatory=$false)]
    [string]$Version,
    
    [switch]$SkipTests,
    [switch]$ShowHelp
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ============================================================================
# Configuration
# ============================================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$releaseDir = Join-Path $projectRoot "release"
$binDir = Join-Path $projectRoot "bin"
$cmdDir = Join-Path $projectRoot "cmd"

# Read version from winmole.ps1 if not provided
if (-not $Version) {
    $winmoleScript = Join-Path $projectRoot "winmole.ps1"
    $content = Get-Content $winmoleScript -Raw
    if ($content -match '\$script:WINMOLE_VER\s*=\s*"([^"]+)"') {
        $Version = $Matches[1]
    } else {
        Write-Host "Error: Could not detect version from winmole.ps1" -ForegroundColor Red
        exit 1
    }
}

$buildDate = Get-Date -Format "yyyy-MM-dd"
$archiveName = "winmole-$Version-x64"

# ============================================================================
# Help
# ============================================================================

function Show-BuildHelp {
    Write-Host ""
    Write-Host "WinMole Release Build Script" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\build-release.ps1 [-Version <version>] [-SkipTests]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Version <ver>  Specify version (default: auto-detect from winmole.ps1)"
    Write-Host "  -SkipTests      Skip running tests before building"
    Write-Host "  -ShowHelp       Show this help message"
    Write-Host ""
    Write-Host "Output:"
    Write-Host "  release/winmole-<version>-x64.zip        Portable archive"
    Write-Host "  release/winmole-<version>-x64.exe        Standalone executable"
    Write-Host "  release/SHA256SUMS.txt                  Hash file for verification"
    Write-Host ""
}

if ($ShowHelp) {
    Show-BuildHelp
    exit 0
}

# ============================================================================
# Banner
# ============================================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  WinMole - Release Build" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Version: $Version" -ForegroundColor Yellow
Write-Host "Build Date: $buildDate" -ForegroundColor Yellow
Write-Host "Output: $releaseDir" -ForegroundColor Yellow
Write-Host ""

# ============================================================================
# Pre-flight Checks
# ============================================================================

Write-Host "[1/7] Running pre-flight checks..." -ForegroundColor Cyan

# Check Go installation
$goVersion = & go version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Error: Go is not installed" -ForegroundColor Red
    Write-Host "  Install from: https://golang.org/dl/" -ForegroundColor Gray
    exit 1
}
Write-Host "  Go: $goVersion" -ForegroundColor Green

# Check PowerShell version
$psVersion = $PSVersionTable.PSVersion
Write-Host "  PowerShell: $psVersion" -ForegroundColor Green

# Check required directories exist
$requiredDirs = @($binDir, $cmdDir, "$projectRoot\lib")
foreach ($dir in $requiredDirs) {
    if (-not (Test-Path $dir)) {
        Write-Host "  Error: Required directory not found: $dir" -ForegroundColor Red
        exit 1
    }
}
Write-Host "  Project structure: OK" -ForegroundColor Green
Write-Host ""

# ============================================================================
# Run Tests
# ============================================================================

if (-not $SkipTests) {
    Write-Host "[2/7] Running tests..." -ForegroundColor Cyan
    
    $testScript = Join-Path $projectRoot "scripts\test.ps1"
    if (Test-Path $testScript) {
        try {
            & $testScript
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  Tests failed! Aborting release build." -ForegroundColor Red
                exit 1
            }
            Write-Host "  All tests passed" -ForegroundColor Green
        } catch {
            Write-Host "  Test execution failed: $_" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "  Warning: Test script not found, skipping..." -ForegroundColor Yellow
    }
    Write-Host ""
} else {
    Write-Host "[2/7] Skipping tests (--SkipTests flag)" -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================================
# Clean Release Directory
# ============================================================================

Write-Host "[3/7] Preparing release directory..." -ForegroundColor Cyan

if (Test-Path $releaseDir) {
    Write-Host "  Cleaning existing release directory..." -ForegroundColor Gray
    Remove-Item $releaseDir -Recurse -Force
}

New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
Write-Host "  Release directory ready: $releaseDir" -ForegroundColor Green
Write-Host ""

# ============================================================================
# Build Go Binaries
# ============================================================================

Write-Host "[4/7] Building Go binaries..." -ForegroundColor Cyan

Push-Location $projectRoot
try {
    # Build flags for release (strip debug info, optimize)
    $env:CGO_ENABLED = "0"
    $env:GOOS = "windows"
    $env:GOARCH = "amd64"
    $ldflags = "-s -w -X main.version=$Version -X main.buildDate=$buildDate"
    
    # Ensure bin directory exists
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }
    
    # Build analyze.exe
    Write-Host "  Building analyze.exe..." -ForegroundColor Gray
    & go build -ldflags $ldflags -o "$binDir\analyze.exe" "./cmd/analyze/"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to build analyze.exe" -ForegroundColor Red
        exit 1
    }
    $analyzeSize = (Get-Item "$binDir\analyze.exe").Length / 1KB
    Write-Host "  Built: analyze.exe ($([math]::Round($analyzeSize, 0)) KB)" -ForegroundColor Green
    
    # Build status.exe
    Write-Host "  Building status.exe..." -ForegroundColor Gray
    & go build -ldflags $ldflags -o "$binDir\status.exe" "./cmd/status/"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to build status.exe" -ForegroundColor Red
        exit 1
    }
    $statusSize = (Get-Item "$binDir\status.exe").Length / 1KB
    Write-Host "  Built: status.exe ($([math]::Round($statusSize, 0)) KB)" -ForegroundColor Green
}
finally {
    Pop-Location
}
Write-Host ""

# ============================================================================
# Create Portable ZIP Archive
# ============================================================================

Write-Host "[5/7] Creating portable ZIP archive..." -ForegroundColor Cyan

$tempBuildDir = Join-Path $releaseDir "temp-build"
New-Item -ItemType Directory -Path $tempBuildDir -Force | Out-Null

# Copy all necessary files
$filesToInclude = @(
    @{Source = "$projectRoot\winmole.ps1"; Dest = "$tempBuildDir\winmole.ps1"},
    @{Source = "$projectRoot\install.ps1"; Dest = "$tempBuildDir\install.ps1"},
    @{Source = "$projectRoot\LICENSE"; Dest = "$tempBuildDir\LICENSE"},
    @{Source = "$projectRoot\README.md"; Dest = "$tempBuildDir\README.md"}
)

foreach ($file in $filesToInclude) {
    if (Test-Path $file.Source) {
        Copy-Item $file.Source $file.Dest -Force
        Write-Host "  Added: $(Split-Path $file.Source -Leaf)" -ForegroundColor Gray
    }
}

# Copy directories
$dirsToInclude = @("bin", "lib", "cmd")
foreach ($dir in $dirsToInclude) {
    $sourcePath = Join-Path $projectRoot $dir
    $destPath = Join-Path $tempBuildDir $dir
    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath $destPath -Recurse -Force
        $fileCount = (Get-ChildItem $destPath -Recurse -File).Count
        Write-Host "  Added: $dir\ ($fileCount files)" -ForegroundColor Gray
    }
}

# Create ZIP archive
$zipPath = Join-Path $releaseDir "$archiveName.zip"
Write-Host "  Compressing to ZIP..." -ForegroundColor Gray

if ($PSVersionTable.PSVersion.Major -ge 5) {
    Compress-Archive -Path "$tempBuildDir\*" -DestinationPath $zipPath -CompressionLevel Optimal -Force
} else {
    # Fallback for older PowerShell
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempBuildDir, $zipPath)
}

$zipSize = (Get-Item $zipPath).Length / 1MB
Write-Host "  Created: $archiveName.zip ($([math]::Round($zipSize, 2)) MB)" -ForegroundColor Green

# Cleanup temp directory
Remove-Item $tempBuildDir -Recurse -Force
Write-Host ""

# ============================================================================
# Create Standalone EXE (Wrapper Script)
# ============================================================================

Write-Host "[6/7] Creating standalone executable..." -ForegroundColor Cyan
Write-Host "  Note: Creating PowerShell wrapper (requires PowerShell on target system)" -ForegroundColor Yellow

# Create a simple batch wrapper that calls PowerShell
$exePath = Join-Path $releaseDir "$archiveName.exe"
$wrapperScript = @"
@echo off
REM WinMole Windows Launcher
REM Version: $Version

REM Check PowerShell availability
where pwsh >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0winmole.ps1" %*
) else (
    where powershell >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0winmole.ps1" %*
    ) else (
        echo Error: PowerShell is not installed
        echo Please install PowerShell from: https://aka.ms/powershell
        exit /b 1
    )
)
"@

# For now, we'll create a batch file launcher
# TODO: Use PS2EXE or similar for true standalone executable
$batPath = Join-Path $releaseDir "winmole.bat"
Set-Content -Path $batPath -Value $wrapperScript -Encoding ASCII

Write-Host "  Created: winmole.bat (PowerShell wrapper)" -ForegroundColor Green
Write-Host "  TODO: True standalone EXE requires PS2EXE or compilation" -ForegroundColor Yellow
Write-Host ""

# ============================================================================
# Generate SHA256 Checksums
# ============================================================================

Write-Host "[7/7] Generating SHA256 checksums..." -ForegroundColor Cyan

$hashFile = Join-Path $releaseDir "SHA256SUMS.txt"
$hashContent = @()

# Calculate hash for ZIP
$zipHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
$hashContent += "$zipHash  $archiveName.zip"
Write-Host "  $archiveName.zip" -ForegroundColor Gray
Write-Host "    SHA256: $zipHash" -ForegroundColor Gray

# Calculate hash for BAT (if exists)
if (Test-Path $batPath) {
    $batHash = (Get-FileHash $batPath -Algorithm SHA256).Hash.ToLower()
    $hashContent += "$batHash  winmole.bat"
    Write-Host "  winmole.bat" -ForegroundColor Gray
    Write-Host "    SHA256: $batHash" -ForegroundColor Gray
}

# Save hash file
Set-Content -Path $hashFile -Value ($hashContent -join "`n") -Encoding UTF8
Write-Host ""
Write-Host "  Checksums saved to: SHA256SUMS.txt" -ForegroundColor Green
Write-Host ""

# ============================================================================
# Summary
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Build Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Release artifacts in: $releaseDir" -ForegroundColor Yellow
Write-Host ""
Write-Host "Files created:" -ForegroundColor Cyan
Get-ChildItem $releaseDir | ForEach-Object {
    $size = if ($_.PSIsContainer) { "-" } else { "$([math]::Round($_.Length / 1KB, 0)) KB" }
    Write-Host "  - $($_.Name) ($size)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Test the ZIP archive: Expand-Archive release\$archiveName.zip -DestinationPath test" -ForegroundColor Gray
Write-Host "  2. Create GitHub release and upload artifacts" -ForegroundColor Gray
Write-Host "  3. Submit to package managers (WinGet, Chocolatey, Scoop)" -ForegroundColor Gray
Write-Host ""
Write-Host "To verify integrity:" -ForegroundColor Cyan
Write-Host "  sha256sum -c release\SHA256SUMS.txt" -ForegroundColor Gray
Write-Host ""
