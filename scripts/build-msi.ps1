# WinMole - MSI Installer Builder
# Creates Windows Installer (.msi) package using WiX Toolset
# Requires: WiX Toolset v3 or v4 (https://wixtoolset.org/)

#Requires -Version 5.1
param(
    [Parameter(Mandatory=$false)]
    [string]$Version,
    
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
$wixSource = Join-Path $scriptDir "winmole-installer.wxs"

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

$msiName = "winmole-$Version-x64.msi"
$msiPath = Join-Path $releaseDir $msiName
$wixObjPath = Join-Path $releaseDir "winmole-installer.wixobj"

# ============================================================================
# Help
# ============================================================================

function Show-BuildHelp {
    Write-Host ""
    Write-Host "WinMole MSI Builder" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\build-msi.ps1 [-Version <version>]"
    Write-Host ""
    Write-Host "Requirements:"
    Write-Host "  WiX Toolset v3 or v4: https://wixtoolset.org/releases/" -ForegroundColor Gray
    Write-Host "  Add WiX bin directory to PATH" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Version <ver>  Specify version (default: auto-detect)"
    Write-Host "  -ShowHelp       Show this help message"
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
Write-Host "  WinMole - MSI Installer Builder" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Version: $Version" -ForegroundColor Yellow
Write-Host ""

# ============================================================================
# Check Dependencies
# ============================================================================

Write-Host "[1/5] Checking dependencies..." -ForegroundColor Cyan

# Check if WiX is installed
$wixInstalled = $false
$candleCmd = $null
$lightCmd = $null

# Try to find WiX executables
$wixPaths = @(
    "${env:ProgramFiles(x86)}\WiX Toolset v3.11\bin",
    "${env:ProgramFiles}\WiX Toolset v3.11\bin",
    "${env:ProgramFiles(x86)}\WiX Toolset v4\bin",
    "${env:ProgramFiles}\WiX Toolset v4\bin"
)

foreach ($path in $wixPaths) {
    if (Test-Path "$path\candle.exe") {
        $candleCmd = "$path\candle.exe"
        $lightCmd = "$path\light.exe"
        $wixInstalled = $true
        break
    }
}

# Check PATH as fallback
if (-not $wixInstalled) {
    try {
        $null = & candle.exe -? 2>&1
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 104) {
            $candleCmd = "candle.exe"
            $lightCmd = "light.exe"
            $wixInstalled = $true
        }
    } catch {
        # Not in PATH
    }
}

if (-not $wixInstalled) {
    Write-Host "  Error: WiX Toolset not found" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Install WiX Toolset:" -ForegroundColor Yellow
    Write-Host "    https://wixtoolset.org/releases/" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Or use Chocolatey:" -ForegroundColor Yellow
    Write-Host "    choco install wixtoolset" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

Write-Host "  WiX Toolset: OK" -ForegroundColor Green
Write-Host "    candle: $candleCmd" -ForegroundColor Gray
Write-Host "    light: $lightCmd" -ForegroundColor Gray

# Check if source WXS file exists
if (-not (Test-Path $wixSource)) {
    Write-Host "  Error: WiX source file not found: $wixSource" -ForegroundColor Red
    exit 1
}
Write-Host "  WiX source: OK" -ForegroundColor Green

# Ensure release directory exists
if (-not (Test-Path $releaseDir)) {
    New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
}

Write-Host ""

# ============================================================================
# Update WXS Version
# ============================================================================

Write-Host "[2/5] Updating installer version..." -ForegroundColor Cyan

# Read source file as bytes to avoid any encoding issues
$sourceBytes = [System.IO.File]::ReadAllBytes($wixSource)
# Convert to string using UTF8 without BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$wixContent = $utf8NoBom.GetString($sourceBytes)

# Replace version
$wixContent = $wixContent -replace 'Version="[^"]+"', "Version=`"$Version`""

# Write back as bytes without BOM
$tempWxs = Join-Path $releaseDir "winmole-installer-temp.wxs"
$outputBytes = $utf8NoBom.GetBytes($wixContent)
[System.IO.File]::WriteAllBytes($tempWxs, $outputBytes)

Write-Host "  Version set to: $Version" -ForegroundColor Green
Write-Host ""

# ============================================================================
# Compile WXS to WIXOBJ
# ============================================================================

Write-Host "[3/5] Compiling WiX source..." -ForegroundColor Cyan

Push-Location $projectRoot
try {
    $candleArgs = @(
        $tempWxs,
        "-out", $wixObjPath,
        "-arch", "x64",
        "-ext", "WixUIExtension"
    )
    
    Write-Host "  Running candle.exe..." -ForegroundColor Gray
    & $candleCmd $candleArgs
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Compilation failed" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "  Compiled: winmole-installer.wixobj" -ForegroundColor Green
}
finally {
    Pop-Location
}
Write-Host ""

# ============================================================================
# Link WIXOBJ to MSI
# ============================================================================

Write-Host "[4/5] Linking installer package..." -ForegroundColor Cyan

Push-Location $projectRoot
try {
    $lightArgs = @(
        $wixObjPath,
        "-out", $msiPath,
        "-ext", "WixUIExtension",
        "-cultures:en-US",
        "-loc", "en-US"
    )
    
    Write-Host "  Running light.exe..." -ForegroundColor Gray
    & $lightCmd $lightArgs
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Linking failed" -ForegroundColor Red
        exit 1
    }
    
    if (Test-Path $msiPath) {
        $msiSize = (Get-Item $msiPath).Length / 1MB
        Write-Host "  Created: $msiName ($([math]::Round($msiSize, 2)) MB)" -ForegroundColor Green
    } else {
        Write-Host "  Error: MSI was not created" -ForegroundColor Red
        exit 1
    }
}
finally {
    Pop-Location
}
Write-Host ""

# ============================================================================
# Update Checksums
# ============================================================================

Write-Host "[5/5] Updating checksums..." -ForegroundColor Cyan

$hashFile = Join-Path $releaseDir "SHA256SUMS.txt"
$msiHash = (Get-FileHash $msiPath -Algorithm SHA256).Hash.ToLower()

# Append to existing hash file
$hashLine = "$msiHash  $msiName"
if (Test-Path $hashFile) {
    Add-Content -Path $hashFile -Value $hashLine -Encoding UTF8
} else {
    Set-Content -Path $hashFile -Value $hashLine -Encoding UTF8
}

Write-Host "  $msiName" -ForegroundColor Gray
Write-Host "    SHA256: $msiHash" -ForegroundColor Gray
Write-Host ""

# Cleanup temp files
if (Test-Path $tempWxs) { Remove-Item $tempWxs -Force }
if (Test-Path $wixObjPath) { Remove-Item $wixObjPath -Force }
if (Test-Path "$releaseDir\winmole-installer.wixpdb") { 
    Remove-Item "$releaseDir\winmole-installer.wixpdb" -Force 
}

# ============================================================================
# Summary
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Build Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "MSI installer created:" -ForegroundColor Yellow
Write-Host "  $msiPath" -ForegroundColor Gray
Write-Host ""
Write-Host "Test installation:" -ForegroundColor Cyan
Write-Host "  msiexec /i `"$msiPath`" /qn" -ForegroundColor Gray
Write-Host ""
Write-Host "Test with UI:" -ForegroundColor Cyan
Write-Host "  msiexec /i `"$msiPath`"" -ForegroundColor Gray
Write-Host ""
