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
    [switch]$Caches,
    [switch]$GPUShaders,
    [switch]$GameMedia,
    [switch]$Orphaned,
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
. "$libDir\clean\caches.ps1"
. "$libDir\clean\apps.ps1"
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
    Write-Host "    -Caches         Clean system and app caches (Store, .NET, GPU)"
    Write-Host "    -GPUShaders     Clean GPU shader caches (NVIDIA, AMD, Intel)"
    Write-Host "    -Dev            Clean developer tool caches"
    Write-Host "    -System         Clean system caches (requires admin)"
    Write-Host "    -RecycleBin     Empty Recycle Bin"
    Write-Host "    -WindowsUpdate  Clean Windows Update cache (requires admin)"
    Write-Host "    -GameMedia      Clean old game recordings and screenshots"
    Write-Host "    -Orphaned       Detect and clean orphaned app data"
    Write-Host "    -Help           Show this help"
    Write-Host ""
    Write-Host "  ${gray}EXAMPLES:${nc}"
    Write-Host "    winmole clean                    # Interactive mode"
    Write-Host "    winmole clean -All               # Full cleanup"
    Write-Host "    winmole clean -User -Browsers    # User + Browser cleanup"
    Write-Host "    winmole clean -All -DryRun       # Preview all changes"
    Write-Host "    winmole clean -Caches -GPUShaders  # Deep cache cleanup"
    Write-Host "    winmole clean -GameMedia          # Clean old game media"
    Write-Host ""
}

# ============================================================================
# Compatibility
# ============================================================================

function Invoke-UserCacheCleanup {
    <#
    .SYNOPSIS
        Run user cache cleanup across mixed install versions.
    #>

    if (Get-Command -Name "Clear-UserCaches" -CommandType Function -ErrorAction SilentlyContinue) {
        Clear-UserCaches
        return
    }

    Start-Section "User caches"

    if (Get-Command -Name "Clear-ThumbnailCache" -CommandType Function -ErrorAction SilentlyContinue) {
        Clear-ThumbnailCache
    }

    if (Get-Command -Name "Clear-ClipboardHistory" -CommandType Function -ErrorAction SilentlyContinue) {
        Clear-ClipboardHistory
    }

    Stop-Section
}

function Invoke-BrowserCacheCleanup {
    <#
    .SYNOPSIS
        Run browser cache cleanup across mixed module versions.
    #>

    if (Get-Command -Name "Clear-BrowserCaches" -CommandType Function -ErrorAction SilentlyContinue) {
        Clear-BrowserCaches
        return
    }

    if (Get-Command -Name "Clear-BrowserCacheFiles" -CommandType Function -ErrorAction SilentlyContinue) {
        Clear-BrowserCacheFiles
    }
}

function Invoke-ApplicationCacheCleanup {
    <#
    .SYNOPSIS
        Run application cache cleanup across mixed module versions.
    #>

    if (Get-Command -Name "Clear-ApplicationCaches" -CommandType Function -ErrorAction SilentlyContinue) {
        Clear-ApplicationCaches
        return
    }

    if (Get-Command -Name "Clear-CommonAppCaches" -CommandType Function -ErrorAction SilentlyContinue) {
        Clear-CommonAppCaches
    }
}

function Invoke-WindowsUpdateCleanup {
    <#
    .SYNOPSIS
        Run Windows Update cache cleanup across mixed module versions.
    #>

    if (Get-Command -Name "Clear-WindowsUpdateCache" -CommandType Function -ErrorAction SilentlyContinue) {
        Clear-WindowsUpdateCache
        return
    }

    if (Get-Command -Name "Clear-WindowsUpdateDownloads" -CommandType Function -ErrorAction SilentlyContinue) {
        Clear-WindowsUpdateDownloads
    }
}

function Invoke-DeveloperCleanup {
    <#
    .SYNOPSIS
        Run developer cache cleanup across mixed module versions.
    #>

    if (Get-Command -Name "Invoke-DevCleanup" -CommandType Function -ErrorAction SilentlyContinue) {
        Invoke-DevCleanup -All
        return
    }

    if (Get-Command -Name "Invoke-DevToolsCleanup" -CommandType Function -ErrorAction SilentlyContinue) {
        Invoke-DevToolsCleanup
    }
}

function Invoke-SystemCleanupCompat {
    <#
    .SYNOPSIS
        Run system cleanup across mixed module versions.
    #>

    if (Get-Command -Name "Invoke-SystemCleanup" -CommandType Function -ErrorAction SilentlyContinue) {
        $command = Get-Command -Name "Invoke-SystemCleanup" -CommandType Function -ErrorAction SilentlyContinue
        $hasAllParameter = $command -and $command.Parameters.ContainsKey("All")

        if ($hasAllParameter) {
            Invoke-SystemCleanup -All
        }
        else {
            Invoke-SystemCleanup -IncludeComponentStore -IncludeDiskCleanup
        }
    }
}

# ============================================================================
# Interactive Mode
# ============================================================================

function Show-CleanMenu {
    $options = @(
        @{ Name = "Quick Clean"; Description = "User caches and temp files"; Action = "quick" }
        @{ Name = "Browser Clean"; Description = "All browser caches"; Action = "browsers" }
        @{ Name = "App Clean"; Description = "Application caches"; Action = "apps" }
        @{ Name = "Cache Clean"; Description = "System, Store, .NET, GPU shader caches"; Action = "caches" }
        @{ Name = "Developer Clean"; Description = "Dev tool caches (npm, pip, etc.)"; Action = "dev" }
        @{ Name = "System Clean"; Description = "System caches (requires admin)"; Action = "system" }
        @{ Name = "Game Media Clean"; Description = "Old recordings, screenshots, replays"; Action = "gamemedia" }
        @{ Name = "Orphaned Apps"; Description = "Detect leftover data from uninstalled apps"; Action = "orphaned" }
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
        Write-WinMoleWarning "DRY RUN MODE - No files will be deleted"
    }
    
    # Determine what to clean
    $cleanUser = $false
    $cleanBrowsers = $false
    $cleanApps = $false
    $cleanCaches = $false
    $cleanGPUShaders = $false
    $cleanDev = $false
    $cleanSystem = $false
    $cleanRecycleBin = $false
    $cleanWinUpdate = $false
    $cleanGameMedia = $false
    $cleanOrphaned = $false
    
    # If no flags specified, run interactive mode
    $noFlags = -not ($All -or $User -or $Browsers -or $Apps -or $Caches -or $GPUShaders -or $Dev -or $System -or $RecycleBin -or $WindowsUpdate -or $GameMedia -or $Orphaned)
    
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
            "caches" { $cleanCaches = $true; $cleanGPUShaders = $true }
            "dev" { $cleanDev = $true }
            "system" { $cleanSystem = $true }
            "gamemedia" { $cleanGameMedia = $true }
            "orphaned" { $cleanOrphaned = $true }
            "all" { 
                $cleanUser = $true
                $cleanBrowsers = $true
                $cleanApps = $true
                $cleanCaches = $true
                $cleanGPUShaders = $true
                $cleanDev = $true
                $cleanSystem = $true
                $cleanRecycleBin = $true
                $cleanGameMedia = $true
                $cleanOrphaned = $true
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
            $cleanCaches = $true
            $cleanGPUShaders = $true
            $cleanDev = $true
            $cleanSystem = $true
            $cleanRecycleBin = $true
            $cleanWinUpdate = $true
            $cleanGameMedia = $true
            $cleanOrphaned = $true
        }
        else {
            $cleanUser = $User
            $cleanBrowsers = $Browsers
            $cleanApps = $Apps
            $cleanCaches = $Caches
            $cleanGPUShaders = $GPUShaders
            $cleanDev = $Dev
            $cleanSystem = $System
            $cleanRecycleBin = $RecycleBin
            $cleanWinUpdate = $WindowsUpdate
            $cleanGameMedia = $GameMedia
            $cleanOrphaned = $Orphaned
        }
    }
    
    # Reset stats
    Reset-CleanupStats
    
    Write-Host ""
    
    # Run cleanups
    if ($cleanUser) {
        Invoke-UserCacheCleanup
        Clear-UserLogs
    }
    
    if ($cleanBrowsers) {
        Invoke-BrowserCacheCleanup
    }
    
    if ($cleanApps) {
        Invoke-ApplicationCacheCleanup
        # Extended app cleanup: productivity, creative, gaming platform caches
        Invoke-AppCleanup
    }
    
    if ($cleanCaches) {
        Clear-CommonAppCaches
        Clear-StoreAppCaches
        Clear-DotNetCaches
        if (Test-IsAdmin) {
            Clear-DeliveryOptimizationCache
            Clear-FontCache
        }
    }
    
    if ($cleanGPUShaders) {
        Clear-GPUShaderCaches
    }
    
    if ($cleanDev) {
        Invoke-DeveloperCleanup
    }
    
    if ($cleanSystem) {
        if (Test-IsAdmin) {
            Invoke-SystemCleanupCompat
        }
        else {
            Write-WinMoleWarning "System cleanup requires admin - skipping"
            Write-Info "Run 'winmole clean -System' as Administrator"
        }
    }
    
    if ($cleanRecycleBin) {
        Clear-RecycleBin
    }
    
    if ($cleanWinUpdate) {
        if (Test-IsAdmin) {
            Invoke-WindowsUpdateCleanup
        }
        else {
            Write-WinMoleWarning "Windows Update cleanup requires admin - skipping"
        }
    }
    
    if ($cleanGameMedia) {
        Clear-GameMediaFiles -DaysOld 90
    }
    
    if ($cleanOrphaned) {
        Clear-OrphanedAppData -DaysOld 60
    }
    
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
    Main | Out-Null
}
finally {
    Clear-TempFiles
    Restore-WinMoleConsoleEncoding
}
