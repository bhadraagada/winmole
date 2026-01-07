#!/usr/bin/env pwsh
# WinMole Build Script
# Builds Go binaries and validates PowerShell scripts

#Requires -Version 5.1
param(
    [Parameter(Position = 0)]
    [ValidateSet("all", "go", "validate", "clean", "test")]
    [string]$Target = "all",
    
    [switch]$Release,
    [switch]$ShowDetails,
    [switch]$ShowHelp
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ============================================================================
# Configuration
# ============================================================================

$script:ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:BIN_DIR = Join-Path $script:ROOT "bin"
$script:CMD_DIR = Join-Path $script:ROOT "cmd"
$script:LIB_DIR = Join-Path $script:ROOT "lib"
$script:TESTS_DIR = Join-Path $script:ROOT "tests"

$script:GO_TOOLS = @("analyze", "status")
$script:VERSION = "1.0.0"

# Colors
$script:Colors = @{
    Red     = "`e[31m"
    Green   = "`e[32m"
    Yellow  = "`e[33m"
    Blue    = "`e[34m"
    Cyan    = "`e[36m"
    Gray    = "`e[90m"
    NC      = "`e[0m"
}

# ============================================================================
# Helpers
# ============================================================================

function Write-Info {
    param([string]$Message)
    $c = $script:Colors
    Write-Host "$($c.Blue)==>$($c.NC) $Message"
}

function Write-Success {
    param([string]$Message)
    $c = $script:Colors
    Write-Host "$($c.Green)==>$($c.NC) $Message"
}

function Write-Warn {
    param([string]$Message)
    $c = $script:Colors
    Write-Host "$($c.Yellow)==>$($c.NC) $Message"
}

function Write-Fail {
    param([string]$Message)
    $c = $script:Colors
    Write-Host "$($c.Red)==>$($c.NC) $Message"
}

function Show-Help {
    $c = $script:Colors
    
    Write-Host ""
    Write-Host "  $($c.Cyan)WinMole Build Script$($c.NC)"
    Write-Host ""
    Write-Host "  $($c.Green)USAGE:$($c.NC)"
    Write-Host ""
    Write-Host "    .\build.ps1 [target] [options]"
    Write-Host ""
    Write-Host "  $($c.Green)TARGETS:$($c.NC)"
    Write-Host ""
    Write-Host "    $($c.Cyan)all$($c.NC)        Build everything (default)"
    Write-Host "    $($c.Cyan)go$($c.NC)         Build Go binaries only"
    Write-Host "    $($c.Cyan)validate$($c.NC)   Validate PowerShell scripts"
    Write-Host "    $($c.Cyan)test$($c.NC)       Run tests"
    Write-Host "    $($c.Cyan)clean$($c.NC)      Remove build artifacts"
    Write-Host ""
    Write-Host "  $($c.Green)OPTIONS:$($c.NC)"
    Write-Host ""
    Write-Host "    $($c.Cyan)-Release$($c.NC)      Build optimized release binaries"
    Write-Host "    $($c.Cyan)-ShowDetails$($c.NC)  Show detailed output"
    Write-Host "    $($c.Cyan)-ShowHelp$($c.NC)     Show this help"
    Write-Host ""
    Write-Host "  $($c.Green)EXAMPLES:$($c.NC)"
    Write-Host ""
    Write-Host "    $($c.Gray).\build.ps1$($c.NC)              # Build all"
    Write-Host "    $($c.Gray).\build.ps1 go -Release$($c.NC)  # Build release Go binaries"
    Write-Host "    $($c.Gray).\build.ps1 validate$($c.NC)     # Validate scripts"
    Write-Host "    $($c.Gray).\build.ps1 test$($c.NC)         # Run tests"
    Write-Host "    $($c.Gray).\build.ps1 clean$($c.NC)        # Clean artifacts"
    Write-Host ""
}

# ============================================================================
# Build Functions
# ============================================================================

function Get-GoPath {
    # Try standard location first
    $defaultPath = "C:\Program Files\Go\bin\go.exe"
    if (Test-Path $defaultPath) {
        return $defaultPath
    }
    
    # Try PATH
    $go = Get-Command "go" -ErrorAction SilentlyContinue
    if ($go) {
        return $go.Source
    }
    
    return $null
}

function Test-GoInstalled {
    $script:GoExe = Get-GoPath
    if (-not $script:GoExe) {
        Write-Fail "Go is not installed or not in PATH"
        Write-Host "  Install from: https://go.dev/dl/"
        return $false
    }
    
    if ($ShowDetails) {
        $version = & $script:GoExe version
        Write-Info "Go: $version"
    }
    
    return $true
}

function Build-GoTool {
    param(
        [string]$Name,
        [switch]$Release
    )
    
    $srcDir = Join-Path $script:CMD_DIR $Name
    $outPath = Join-Path $script:BIN_DIR "$Name.exe"
    
    if (-not (Test-Path $srcDir)) {
        Write-Warn "Source not found: $srcDir"
        return $false
    }
    
    Write-Info "Building $Name..."
    
    try {
        Push-Location $srcDir
        
        # Set build flags
        $ldflags = "-s -w"
        if ($Release) {
            $ldflags = "-s -w -X main.Version=$script:VERSION"
        }
        
        $env:CGO_ENABLED = "0"
        $env:GOOS = "windows"
        $env:GOARCH = "amd64"
        
        $buildArgs = @("build", "-ldflags=$ldflags", "-o", $outPath, ".")
        
        if ($ShowDetails) {
            Write-Host "    $script:GoExe $($buildArgs -join ' ')"
        }
        
        $output = & $script:GoExe @buildArgs 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Build failed for $Name"
            Write-Host $output
            return $false
        }
        
        $size = (Get-Item $outPath).Length / 1MB
        Write-Success "Built $Name ($([math]::Round($size, 2)) MB)"
        return $true
    }
    catch {
        Write-Fail "Build error: $_"
        return $false
    }
    finally {
        Pop-Location
    }
}

function Build-AllGo {
    Write-Host ""
    Write-Info "Building Go tools..."
    Write-Host ""
    
    if (-not (Test-GoInstalled)) {
        return $false
    }
    
    # Download dependencies
    Write-Info "Downloading dependencies..."
    Push-Location $script:ROOT
    try {
        # Always run mod tidy first to ensure go.sum exists
        $tidyOutput = & $script:GoExe mod tidy 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "go mod tidy warning: $tidyOutput"
        }
        
        $dlOutput = & $script:GoExe mod download 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "go mod download warning: $dlOutput"
        }
    }
    finally {
        Pop-Location
    }
    
    $allSuccess = $true
    foreach ($tool in $script:GO_TOOLS) {
        if (-not (Build-GoTool -Name $tool -Release:$Release)) {
            $allSuccess = $false
        }
    }
    
    Write-Host ""
    return $allSuccess
}

function Test-PowerShellScripts {
    Write-Host ""
    Write-Info "Validating PowerShell scripts..."
    Write-Host ""
    
    $scripts = Get-ChildItem -Path $script:ROOT -Include "*.ps1" -Recurse
    $errors = @()
    
    foreach ($script in $scripts) {
        $relativePath = $script.FullName.Replace($script:ROOT, "").TrimStart("\")
        
        try {
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script.FullName,
                [ref]$null,
                [ref]$parseErrors
            )
            
            if ($parseErrors.Count -gt 0) {
                $errors += @{
                    File = $relativePath
                    Errors = $parseErrors
                }
                Write-Fail "  $relativePath - $($parseErrors.Count) error(s)"
            }
            else {
                if ($ShowDetails) {
                    Write-Success "  $relativePath"
                }
            }
        }
        catch {
            $errors += @{
                File = $relativePath
                Errors = @($_)
            }
            Write-Fail "  $relativePath - Parse error"
        }
    }
    
    Write-Host ""
    
    if ($errors.Count -gt 0) {
        Write-Fail "Validation failed with $($errors.Count) file(s) having errors"
        
        foreach ($err in $errors) {
            Write-Host ""
            Write-Host "  $($err.File):"
            foreach ($e in $err.Errors) {
                Write-Host "    - $e"
            }
        }
        
        return $false
    }
    
    Write-Success "All $($scripts.Count) scripts validated successfully"
    return $true
}

function Invoke-Tests {
    Write-Host ""
    Write-Info "Running tests..."
    Write-Host ""
    
    $testFile = Join-Path $script:TESTS_DIR "WinMole.Tests.ps1"
    
    if (-not (Test-Path $testFile)) {
        Write-Warn "No tests found at: $testFile"
        return $true
    }
    
    # Check for Pester
    $pester = Get-Module -ListAvailable -Name Pester
    if (-not $pester) {
        Write-Warn "Pester is not installed. Install with:"
        Write-Host "  Install-Module -Name Pester -Force -SkipPublisherCheck"
        return $false
    }
    
    try {
        $results = Invoke-Pester -Path $script:TESTS_DIR -PassThru -Output Detailed
        
        Write-Host ""
        
        if ($results.FailedCount -gt 0) {
            Write-Fail "Tests failed: $($results.FailedCount)/$($results.TotalCount)"
            return $false
        }
        
        Write-Success "All tests passed: $($results.PassedCount)/$($results.TotalCount)"
        return $true
    }
    catch {
        Write-Fail "Test error: $_"
        return $false
    }
}

function Clear-BuildArtifacts {
    Write-Host ""
    Write-Info "Cleaning build artifacts..."
    Write-Host ""
    
    $artifacts = @(
        "bin\analyze.exe"
        "bin\status.exe"
        "go.sum"
    )
    
    foreach ($artifact in $artifacts) {
        $path = Join-Path $script:ROOT $artifact
        if (Test-Path $path) {
            Remove-Item $path -Force
            Write-Success "Removed: $artifact"
        }
    }
    
    Write-Host ""
    Write-Success "Clean complete"
    return $true
}

# ============================================================================
# Main
# ============================================================================

function Main {
    if ($ShowHelp) {
        Show-Help
        return
    }
    
    $success = $true
    
    switch ($Target) {
        "all" {
            if (-not (Test-PowerShellScripts)) { $success = $false }
            if (-not (Build-AllGo)) { $success = $false }
        }
        "go" {
            if (-not (Build-AllGo)) { $success = $false }
        }
        "validate" {
            if (-not (Test-PowerShellScripts)) { $success = $false }
        }
        "test" {
            if (-not (Invoke-Tests)) { $success = $false }
        }
        "clean" {
            if (-not (Clear-BuildArtifacts)) { $success = $false }
        }
    }
    
    Write-Host ""
    
    if (-not $success) {
        Write-Fail "Build failed"
        exit 1
    }
    
    Write-Success "Build completed successfully"
}

# Run
try {
    Main
}
catch {
    Write-Host ""
    Write-Fail "Build error: $_"
    Write-Host ""
    exit 1
}
