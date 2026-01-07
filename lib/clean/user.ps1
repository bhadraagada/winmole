# WinMole - User Cleanup Module
# Cleans user-level caches, temp files, and logs

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Import core
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$coreDir = Join-Path (Split-Path -Parent $scriptDir) "core"
. "$coreDir\common.ps1"

# ============================================================================
# User Cache Cleanup
# ============================================================================

function Clear-UserCaches {
    <#
    .SYNOPSIS
        Clean user-level application caches
    #>
    Start-Section "User Caches"
    
    # Windows Temp folder
    $tempPath = [System.IO.Path]::GetTempPath()
    if (Test-Path $tempPath -ErrorAction SilentlyContinue) {
        Start-Spinner "Scanning Windows Temp..."
        $null = Clear-DirectoryContents -Path $tempPath -Description "Windows Temp"
        Stop-Spinner
    }
    
    # User Temp folder
    $userTemp = "$env:LOCALAPPDATA\Temp"
    if (Test-Path $userTemp -ErrorAction SilentlyContinue) {
        $null = Clear-DirectoryContents -Path $userTemp -Description "User Temp"
    }
    
    # Windows Prefetch (requires admin)
    if (Test-IsAdmin) {
        $prefetch = "$env:SystemRoot\Prefetch"
        if (Test-Path $prefetch -ErrorAction SilentlyContinue) {
            $null = Remove-OldFiles -Path $prefetch -DaysOld 30 -Description "Windows Prefetch"
        }
    }
    
    # Recent files list (just clears shortcuts, not actual files)
    $recent = "$env:APPDATA\Microsoft\Windows\Recent"
    if (Test-Path $recent -ErrorAction SilentlyContinue) {
        $null = Remove-OldFiles -Path $recent -DaysOld 30 -Filter "*.lnk" -Description "Recent shortcuts"
    }
    
    # Thumbnail cache
    $thumbCache = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    if (Test-Path $thumbCache -ErrorAction SilentlyContinue) {
        $thumbFiles = Get-ChildItem -Path $thumbCache -Filter "thumbcache_*.db" -ErrorAction SilentlyContinue
        if ($thumbFiles) {
            # These are locked while Explorer is running - skip if locked
            foreach ($file in $thumbFiles) {
                try {
                    $null = Remove-SafeItem -Path $file.FullName -Description "Thumbnail cache"
                }
                catch {
                    Write-Debug "Thumbnail cache locked: $($file.Name)"
                }
            }
        }
    }
    
    # Windows Icon Cache
    $iconCache = "$env:LOCALAPPDATA\IconCache.db"
    if (Test-Path $iconCache -ErrorAction SilentlyContinue) {
        $null = Remove-SafeItem -Path $iconCache -Description "Icon cache"
    }
    
    Stop-Section
}

function Clear-UserLogs {
    <#
    .SYNOPSIS
        Clean user-level log files
    #>
    Start-Section "User Logs"
    
    # Windows Error Reporting
    $werLocal = "$env:LOCALAPPDATA\Microsoft\Windows\WER"
    if (Test-Path $werLocal -ErrorAction SilentlyContinue) {
        $null = Clear-DirectoryContents -Path "$werLocal\ReportArchive" -Description "Error Reports (Local)"
        $null = Clear-DirectoryContents -Path "$werLocal\ReportQueue" -Description "Error Report Queue"
    }
    
    # Crash dumps
    $crashDumps = "$env:LOCALAPPDATA\CrashDumps"
    if (Test-Path $crashDumps -ErrorAction SilentlyContinue) {
        $null = Remove-OldFiles -Path $crashDumps -DaysOld $script:Config.CrashReportAgeDays -Description "Crash dumps"
    }
    
    # Windows Defender logs (user level)
    $defenderLogs = "$env:ProgramData\Microsoft\Windows Defender\Scans\History"
    if (Test-IsAdmin) {
        try {
            if (Test-Path $defenderLogs -ErrorAction SilentlyContinue) {
                $null = Remove-OldFiles -Path $defenderLogs -DaysOld 30 -Description "Defender scan history"
            }
        }
        catch {
            Write-Debug "Could not access Defender logs: $_"
        }
    }
    
    Stop-Section
}

function Clear-RecycleBin {
    <#
    .SYNOPSIS
        Empty the Recycle Bin
    #>
    Start-Section "Recycle Bin"
    
    if (Test-Whitelisted "$env:USERPROFILE\`$Recycle.Bin") {
        Write-Info "Recycle Bin - whitelist protected"
        Stop-Section
        return
    }
    
    try {
        # Get recycle bin size first
        $shell = New-Object -ComObject Shell.Application
        $recycleBin = $shell.Namespace(0xA)  # Recycle Bin
        $items = $recycleBin.Items()
        
        if ($items.Count -gt 0) {
            $totalSize = 0
            foreach ($item in $items) {
                $totalSize += $item.ExtendedProperty("Size")
            }
            
            if (Test-DryRunMode) {
                Write-DryRun "Recycle Bin ($($items.Count) items, $(Format-ByteSize $totalSize) dry)"
            }
            else {
                # Clear recycle bin
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                Write-Success "Recycle Bin ($($items.Count) items, $(Format-ByteSize $totalSize))"
            }
            Set-SectionActivity
        }
    }
    catch {
        Write-Debug "Could not access Recycle Bin: $_"
    }
    
    Stop-Section
}

# ============================================================================
# Browser Cleanup
# ============================================================================

function Clear-BrowserCaches {
    <#
    .SYNOPSIS
        Clean browser caches for common browsers
    #>
    Start-Section "Browser Caches"
    
    # Chrome
    Clear-ChromeCache
    
    # Edge
    Clear-EdgeCache
    
    # Firefox
    Clear-FirefoxCache
    
    # Brave
    Clear-BraveCache
    
    # Opera
    Clear-OperaCache
    
    Stop-Section
}

function Clear-ChromeCache {
    <#
    .SYNOPSIS
        Clean Google Chrome cache
    #>
    $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    if (-not (Test-Path $chromePath)) { return }
    
    # Check if Chrome is running
    $chromeRunning = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
    if ($chromeRunning) {
        Write-Warning "Chrome is running - some caches skipped"
    }
    
    $profiles = Get-ChildItem -Path $chromePath -Directory -ErrorAction SilentlyContinue | 
                Where-Object { $_.Name -match "^(Default|Profile \d+)$" }
    
    foreach ($profile in $profiles) {
        $cacheDirs = @(
            "Cache"
            "Code Cache"
            "GPUCache"
            "Service Worker\CacheStorage"
            "Service Worker\ScriptCache"
        )
        
        foreach ($cacheDir in $cacheDirs) {
            $cachePath = Join-Path $profile.FullName $cacheDir
            if (Test-Path $cachePath -ErrorAction SilentlyContinue) {
                $null = Clear-DirectoryContents -Path $cachePath -Description "Chrome $($profile.Name) cache"
            }
        }
    }
}

function Clear-EdgeCache {
    <#
    .SYNOPSIS
        Clean Microsoft Edge cache
    #>
    $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    if (-not (Test-Path $edgePath)) { return }
    
    $edgeRunning = Get-Process -Name "msedge" -ErrorAction SilentlyContinue
    if ($edgeRunning) {
        Write-Warning "Edge is running - some caches skipped"
    }
    
    $profiles = Get-ChildItem -Path $edgePath -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "^(Default|Profile \d+)$" }
    
    foreach ($profile in $profiles) {
        $cacheDirs = @("Cache", "Code Cache", "GPUCache")
        
        foreach ($cacheDir in $cacheDirs) {
            $cachePath = Join-Path $profile.FullName $cacheDir
            if (Test-Path $cachePath -ErrorAction SilentlyContinue) {
                $null = Clear-DirectoryContents -Path $cachePath -Description "Edge $($profile.Name) cache"
            }
        }
    }
}

function Clear-FirefoxCache {
    <#
    .SYNOPSIS
        Clean Mozilla Firefox cache
    #>
    $firefoxPath = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (-not (Test-Path $firefoxPath)) { return }
    
    $firefoxRunning = Get-Process -Name "firefox" -ErrorAction SilentlyContinue
    if ($firefoxRunning) {
        Write-Warning "Firefox is running - some caches skipped"
    }
    
    $profiles = Get-ChildItem -Path $firefoxPath -Directory -ErrorAction SilentlyContinue
    
    foreach ($profile in $profiles) {
        $cache2 = Join-Path $profile.FullName "cache2"
        if (Test-Path $cache2 -ErrorAction SilentlyContinue) {
            $null = Clear-DirectoryContents -Path $cache2 -Description "Firefox cache"
        }
        
        $startupCache = Join-Path $profile.FullName "startupCache"
        if (Test-Path $startupCache -ErrorAction SilentlyContinue) {
            $null = Clear-DirectoryContents -Path $startupCache -Description "Firefox startup cache"
        }
    }
}

function Clear-BraveCache {
    <#
    .SYNOPSIS
        Clean Brave browser cache
    #>
    $bravePath = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
    if (-not (Test-Path $bravePath)) { return }
    
    $braveRunning = Get-Process -Name "brave" -ErrorAction SilentlyContinue
    if ($braveRunning) {
        Write-Warning "Brave is running - some caches skipped"
    }
    
    $profiles = Get-ChildItem -Path $bravePath -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "^(Default|Profile \d+)$" }
    
    foreach ($profile in $profiles) {
        $cachePath = Join-Path $profile.FullName "Cache"
        if (Test-Path $cachePath -ErrorAction SilentlyContinue) {
            $null = Clear-DirectoryContents -Path $cachePath -Description "Brave cache"
        }
    }
}

function Clear-OperaCache {
    <#
    .SYNOPSIS
        Clean Opera browser cache
    #>
    $operaPath = "$env:APPDATA\Opera Software\Opera Stable"
    if (-not (Test-Path $operaPath)) { return }
    
    $operaRunning = Get-Process -Name "opera" -ErrorAction SilentlyContinue
    if ($operaRunning) {
        Write-Warning "Opera is running - some caches skipped"
    }
    
    $cachePath = Join-Path $operaPath "Cache"
    if (Test-Path $cachePath -ErrorAction SilentlyContinue) {
        $null = Clear-DirectoryContents -Path $cachePath -Description "Opera cache"
    }
}

# ============================================================================
# Application Cache Cleanup
# ============================================================================

function Clear-ApplicationCaches {
    <#
    .SYNOPSIS
        Clean common application caches
    #>
    Start-Section "Application Caches"
    
    # Discord
    $discordCache = "$env:APPDATA\discord\Cache"
    if (Test-Path $discordCache -ErrorAction SilentlyContinue) {
        $null = Clear-DirectoryContents -Path $discordCache -Description "Discord cache"
    }
    
    # Slack
    $slackCache = "$env:APPDATA\Slack\Cache"
    if (Test-Path $slackCache -ErrorAction SilentlyContinue) {
        $null = Clear-DirectoryContents -Path $slackCache -Description "Slack cache"
    }
    
    # Teams
    $teamsCache = "$env:APPDATA\Microsoft\Teams\Cache"
    if (Test-Path $teamsCache -ErrorAction SilentlyContinue) {
        $null = Clear-DirectoryContents -Path $teamsCache -Description "Teams cache"
    }
    
    # Spotify
    $spotifyCache = "$env:LOCALAPPDATA\Spotify\Data"
    if (Test-Path $spotifyCache -ErrorAction SilentlyContinue) {
        $null = Clear-DirectoryContents -Path $spotifyCache -Description "Spotify cache"
    }
    
    # VS Code
    $vscodeCache = "$env:APPDATA\Code\Cache"
    if (Test-Path $vscodeCache -ErrorAction SilentlyContinue) {
        $null = Clear-DirectoryContents -Path $vscodeCache -Description "VS Code cache"
    }
    $vscodeCachedData = "$env:APPDATA\Code\CachedData"
    if (Test-Path $vscodeCachedData -ErrorAction SilentlyContinue) {
        $null = Clear-DirectoryContents -Path $vscodeCachedData -Description "VS Code cached data"
    }
    
    # Zoom
    $zoomCache = "$env:APPDATA\Zoom\data"
    if (Test-Path $zoomCache -ErrorAction SilentlyContinue) {
        $null = Remove-OldFiles -Path $zoomCache -DaysOld 7 -Description "Zoom cache"
    }
    
    # Adobe
    $adobeCache = "$env:LOCALAPPDATA\Adobe"
    if (Test-Path $adobeCache -ErrorAction SilentlyContinue) {
        $adobeCacheDirs = Get-ChildItem -Path $adobeCache -Directory -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match "Cache|Tmp" }
        foreach ($dir in $adobeCacheDirs) {
            $null = Clear-DirectoryContents -Path $dir.FullName -Description "Adobe cache"
        }
    }
    
    # Steam (download cache only - not game data)
    $steamCache = "$env:LOCALAPPDATA\Steam\htmlcache"
    if (Test-Path $steamCache -ErrorAction SilentlyContinue) {
        $null = Clear-DirectoryContents -Path $steamCache -Description "Steam HTML cache"
    }
    
    # Epic Games Launcher
    $epicCache = "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache"
    if (Test-Path $epicCache -ErrorAction SilentlyContinue) {
        $null = Clear-DirectoryContents -Path $epicCache -Description "Epic Games cache"
    }
    
    Stop-Section
}

# ============================================================================
# Windows Update Cleanup
# ============================================================================

function Clear-WindowsUpdateCache {
    <#
    .SYNOPSIS
        Clean Windows Update cache (requires admin)
    #>
    if (-not (Test-IsAdmin)) {
        Write-Debug "Skipping Windows Update cache - requires admin"
        return
    }
    
    Start-Section "Windows Update Cache"
    
    # SoftwareDistribution download folder
    $softDist = "$env:SystemRoot\SoftwareDistribution\Download"
    if (Test-Path $softDist -ErrorAction SilentlyContinue) {
        # Stop Windows Update service temporarily
        $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        $wasRunning = $wuService.Status -eq 'Running'
        
        if ($wasRunning -and -not (Test-DryRunMode)) {
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        
        $null = Clear-DirectoryContents -Path $softDist -Description "Windows Update downloads"
        
        if ($wasRunning -and -not (Test-DryRunMode)) {
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        }
    }
    
    # Delivery Optimization cache
    $deliveryOpt = "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
    if (Test-Path $deliveryOpt -ErrorAction SilentlyContinue) {
        $null = Clear-DirectoryContents -Path $deliveryOpt -Description "Delivery Optimization cache"
    }
    
    Stop-Section
}

# ============================================================================
# Main Cleanup Function
# ============================================================================

function Invoke-UserCleanup {
    <#
    .SYNOPSIS
        Run all user-level cleanup operations
    #>
    param(
        [switch]$IncludeBrowsers,
        [switch]$IncludeApps,
        [switch]$IncludeRecycleBin,
        [switch]$IncludeWindowsUpdate,
        [switch]$All
    )
    
    Reset-CleanupStats
    
    # Always clean basic caches and logs
    Clear-UserCaches
    Clear-UserLogs
    
    # Optional cleanups
    if ($All -or $IncludeBrowsers) {
        Clear-BrowserCaches
    }
    
    if ($All -or $IncludeApps) {
        Clear-ApplicationCaches
    }
    
    if ($All -or $IncludeRecycleBin) {
        Clear-RecycleBin
    }
    
    if ($All -or $IncludeWindowsUpdate) {
        Clear-WindowsUpdateCache
    }
    
    # Clean empty directories
    Start-Section "Empty Directories"
    $null = Remove-EmptyDirectories -Path "$env:LOCALAPPDATA" -Description "Empty folders (LocalAppData)"
    $null = Remove-EmptyDirectories -Path "$env:APPDATA" -Description "Empty folders (AppData)"
    Stop-Section
    
    # Show summary
    $stats = Get-CleanupStats
    Show-Summary -SizeBytes ($stats.TotalSizeKB * 1024) -ItemCount $stats.TotalItems -Action "Cleaned"
}

# ============================================================================
# Exports (functions are available via dot-sourcing)
# ============================================================================
# Functions: Clear-UserCaches, Clear-BrowserCaches, Invoke-UserCleanup, etc.
