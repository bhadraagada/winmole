# WinMole - Clean Command
# Deep cleanup orchestrator for Windows

#Requires -Version 5.1
param(
    [switch]$DryRun,
    [switch]$All,
    [switch]$User,
    [switch]$Browsers,
    [switch]$Apps,
    [switch]$Dev,
    [switch]$System,
    [switch]$RecycleBin,
    [switch]$WindowsUpdate,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Get script location
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libDir = Join-Path (Split-Path -Parent $scriptDir) "lib"

# Import modules
. "$libDir\core\common.ps1"
. "$libDir\clean\user.ps1"
. "$libDir\clean\dev.ps1"
. "$libDir\clean\system.ps1"

# ============================================================================
# Help
# ============================================================================

function Show-CleanHelp {
    $cyan = $script:Colors.Cyan
    $gray = $script:Colors.Gray
    $nc = $script:Colors.NC
    
    Write-Host ""
    Write-Host "  ${cyan}WinMole Clean${nc} - Deep system cleanup"
    Write-Host ""
    Write-Host "  ${gray}USAGE:${nc}"
    Write-Host "    winmole clean [options]"
    Write-Host ""
    Write-Host "  ${gray}OPTIONS:${nc}"
    Write-Host "    -DryRun         Preview changes without deleting"
    Write-Host "    -All            Run all cleanup operations"
    Write-Host "    -User           Clean user caches and temp files"
    Write-Host "    -Browsers       Clean browser caches"
    Write-Host "    -Apps           Clean application caches"
    Write-Host "    -Dev            Clean developer tool caches"
    Write-Host "    -System         Clean system caches (requires admin)"
    Write-Host "    -RecycleBin     Empty Recycle Bin"
    Write-Host "    -WindowsUpdate  Clean Windows Update cache (requires admin)"
    Write-Host "    -Help           Show this help"
    Write-Host ""
    Write-Host "  ${gray}EXAMPLES:${nc}"
    Write-Host "    winmole clean                    # Interactive mode"
    Write-Host "    winmole clean -All               # Full cleanup"
    Write-Host "    winmole clean -User -Browsers    # User + Browser cleanup"
    Write-Host "    winmole clean -All -DryRun       # Preview all changes"
    Write-Host ""
}

# ============================================================================
# Interactive Mode
# ============================================================================

function Show-CleanMenu {
    $options = @(
        @{ Name = "Quick Clean"; Description = "User caches and temp files"; Action = "quick" }
        @{ Name = "Browser Clean"; Description = "All browser caches"; Action = "browsers" }
        @{ Name = "App Clean"; Description = "Application caches"; Action = "apps" }
        @{ Name = "Developer Clean"; Description = "Dev tool caches (npm, pip, etc.)"; Action = "dev" }
        @{ Name = "System Clean"; Description = "System caches (requires admin)"; Action = "system" }
        @{ Name = "Full Clean"; Description = "Everything above"; Action = "all" }
    )
    
    $selected = Show-Menu -Title "What would you like to clean?" -Options $options -AllowBack
    
    if ($null -eq $selected) {
        return $null
    }
    
    return $selected.Action
}

# ============================================================================
# Main
# ============================================================================

function Main {
    # Initialize
    Initialize-WinMole
    
    # DEBUG: Show parameter values
    Write-Debug "DryRun parameter: $DryRun"
    Write-Debug "User parameter: $User"
    Write-Debug "All parameter: $All"
    
    # Show help if requested
    if ($Help) {
        Show-CleanHelp
        return
    }
    
    # Set dry-run mode
    if ($DryRun -or $env:WINMOLE_DRY_RUN -eq "1") {
        Set-DryRunMode -Enabled $true
        Write-Host ""
        Write-Warning "DRY RUN MODE - No files will be deleted"
    }
    
    # Determine what to clean
    $cleanUser = $false
    $cleanBrowsers = $false
    $cleanApps = $false
    $cleanDev = $false
    $cleanSystem = $false
    $cleanRecycleBin = $false
    $cleanWinUpdate = $false
    
    # If no flags specified, run interactive mode
    $noFlags = -not ($All -or $User -or $Browsers -or $Apps -or $Dev -or $System -or $RecycleBin -or $WindowsUpdate)
    
    if ($noFlags) {
        Clear-Host
        Show-Banner
        
        $action = Show-CleanMenu
        
        if ($null -eq $action) {
            Write-Host ""
            return
        }
        
        switch ($action) {
            "quick" { $cleanUser = $true }
            "browsers" { $cleanBrowsers = $true }
            "apps" { $cleanApps = $true }
            "dev" { $cleanDev = $true }
            "system" { $cleanSystem = $true }
            "all" { 
                $cleanUser = $true
                $cleanBrowsers = $true
                $cleanApps = $true
                $cleanDev = $true
                $cleanSystem = $true
                $cleanRecycleBin = $true
            }
        }
        
        # Confirm before cleaning
        Clear-Host
        Write-Host ""
        if (-not (Read-Confirmation -Prompt "Start cleanup?" -Default $true)) {
            Write-Host ""
            return
        }
    }
    else {
        # Use command-line flags
        if ($All) {
            $cleanUser = $true
            $cleanBrowsers = $true
            $cleanApps = $true
            $cleanDev = $true
            $cleanSystem = $true
            $cleanRecycleBin = $true
            $cleanWinUpdate = $true
        }
        else {
            $cleanUser = $User
            $cleanBrowsers = $Browsers
            $cleanApps = $Apps
            $cleanDev = $Dev
            $cleanSystem = $System
            $cleanRecycleBin = $RecycleBin
            $cleanWinUpdate = $WindowsUpdate
        }
    }
    
    # Reset stats
    Reset-CleanupStats
    
    Write-Host ""
    
    # Run cleanups
    if ($cleanUser) {
        Clear-UserCaches
        Clear-UserLogs
    }
    
    if ($cleanBrowsers) {
        Clear-BrowserCaches
    }
    
    if ($cleanApps) {
        Clear-ApplicationCaches
    }
    
    if ($cleanDev) {
        Invoke-DevCleanup -All
    }
    
    if ($cleanSystem) {
        if (Test-IsAdmin) {
            Invoke-SystemCleanup -All
        }
        else {
            Write-Warning "System cleanup requires admin - skipping"
            Write-Info "Run 'winmole clean -System' as Administrator"
        }
    }
    
    if ($cleanRecycleBin) {
        Clear-RecycleBin
    }
    
    if ($cleanWinUpdate) {
        if (Test-IsAdmin) {
            Clear-WindowsUpdateCache
        }
        else {
            Write-Warning "Windows Update cleanup requires admin - skipping"
        }
    }
    
    # Clean empty directories
    Start-Section "Empty Directories"
    Remove-EmptyDirectories -Path "$env:LOCALAPPDATA" -Description "Empty folders (LocalAppData)"
    Stop-Section
    
    # Show final summary
    $stats = Get-CleanupStats
    if ($stats.TotalItems -gt 0 -or (Test-DryRunMode)) {
        Show-Summary -SizeBytes ($stats.TotalSizeKB * 1024) -ItemCount $stats.TotalItems -Action $(if (Test-DryRunMode) { "Would clean" } else { "Cleaned" })
    }
    else {
        Write-Host ""
        Write-Success "System is already clean!"
        Write-Host ""
    }
    
    # Show free space
    $freeSpace = Get-FreeSpace
    Write-Host "  Free space on $($env:SystemDrive): $freeSpace"
    Write-Host ""
}

# Run
try {
    Main
}
finally {
    Clear-TempFiles
}
