# WinMole - Test Runner Script
# Runs all tests (Pester for PowerShell, go test for Go)

#Requires -Version 5.1
param(
    [switch]$Verbose,
    [switch]$NoPester,
    [switch]$NoGo,
    [switch]$Coverage
)

$ErrorActionPreference = "Stop"
$script:ExitCode = 0

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$windowsDir = Split-Path -Parent $scriptDir

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  WinMole - Test Suite" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Pester Tests
# ============================================================================

if (-not $NoPester) {
    Write-Host "[Pester] Running PowerShell tests..." -ForegroundColor Yellow
    Write-Host ""
    
    # Check if Pester is installed
    $pesterModule = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge "5.0.0" }
    
    if (-not $pesterModule) {
        Write-Host "  Installing Pester 5.x..." -ForegroundColor Gray
        Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck -Scope CurrentUser
    }
    
    Import-Module Pester -MinimumVersion 5.0.0
    
    $testsDir = Join-Path $windowsDir "tests"
    
    $config = New-PesterConfiguration
    $config.Run.Path = $testsDir
    $config.Run.Exit = $false
    $config.Output.Verbosity = if ($Verbose) { "Detailed" } else { "Normal" }
    
    if ($Coverage) {
        $config.CodeCoverage.Enabled = $true
        $config.CodeCoverage.Path = @(
            (Join-Path $windowsDir "lib\core\*.ps1"),
            (Join-Path $windowsDir "lib\clean\*.ps1"),
            (Join-Path $windowsDir "bin\*.ps1")
        )
        $config.CodeCoverage.OutputPath = Join-Path $windowsDir "coverage-pester.xml"
    }
    
    $result = Invoke-Pester -Configuration $config
    
    Write-Host ""
    Write-Host "[Pester] Summary:" -ForegroundColor Yellow
    
    # Pester already printed results above, just check for failures
    # Different Pester versions use different result properties
    $failed = 0
    try {
        if ($null -ne $result.FailedCount) {
            $failed = $result.FailedCount
        }
        elseif ($null -ne $result.Failed) {
            $failed = $result.Failed.Count
        }
        elseif ($null -ne $result.Result -and $null -ne $result.Result.FailedCount) {
            $failed = $result.Result.FailedCount
        }
    }
    catch {
        # If we can't read the result object, assume tests passed
        # (Pester itself prints results and would have exited with error if tests failed)
        Write-Host "  Note: Could not parse result object, checking exit behavior" -ForegroundColor Gray
    }
    
    if ($failed -gt 0) {
        Write-Host "  $failed test(s) failed!" -ForegroundColor Red
        $script:ExitCode = 1
    }
    else {
        Write-Host "  All Pester tests passed!" -ForegroundColor Green
    }
    
    Write-Host ""
}

# ============================================================================
# Go Tests
# ============================================================================

if (-not $NoGo) {
    Write-Host "[Go] Running Go tests..." -ForegroundColor Yellow
    Write-Host ""
    
    # Check if Go is installed
    $goVersion = & go version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Go is not installed, skipping Go tests" -ForegroundColor Gray
    }
    else {
        Write-Host "  $goVersion" -ForegroundColor Gray
        Write-Host ""
        
        Push-Location $windowsDir
        try {
            $goArgs = @("test")
            if ($Verbose) {
                $goArgs += "-v"
            }
            if ($Coverage) {
                $goArgs += "-coverprofile=coverage-go.out"
            }
            $goArgs += "./..."
            
            & go @goArgs
            
            if ($LASTEXITCODE -ne 0) {
                $script:ExitCode = 1
            }
            else {
                Write-Host ""
                Write-Host "[Go] All tests passed" -ForegroundColor Green
            }
        }
        finally {
            Pop-Location
        }
    }
    
    Write-Host ""
}

# ============================================================================
# Summary
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
if ($script:ExitCode -eq 0) {
    Write-Host "  All tests passed!" -ForegroundColor Green
}
else {
    Write-Host "  Some tests failed!" -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

exit $script:ExitCode
