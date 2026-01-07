# WinMole - System Cleanup Module
# Cleans system-level caches, logs, and temporary files (requires admin)

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Import core
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$coreDir = Join-Path (Split-Path -Parent $scriptDir) "core"
. "$coreDir\common.ps1"

# ============================================================================
# Windows System Caches
# ============================================================================

function Clear-SystemCaches {
    <#
    .SYNOPSIS
        Clean Windows system-level caches (requires admin)
    #>
    if (-not (Test-IsAdmin)) {
        Write-Warning "System cleanup requires administrator privileges"
        return
    }
    
    Start-Section "System Caches"
    
    # Windows Temp
    $winTemp = "$env:SystemRoot\Temp"
    if (Test-Path $winTemp) {
        Clear-DirectoryContents -Path $winTemp -Description "Windows Temp"
    }
    
    # Font cache
    $fontCache = "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache"
    if (Test-Path $fontCache) {
        Remove-OldFiles -Path $fontCache -DaysOld 30 -Description "Font cache"
    }
    
    # Windows Installer cache (be careful - only orphaned patches)
    $installerCache = "$env:SystemRoot\Installer\`$PatchCache`$"
    if (Test-Path $installerCache) {
        Write-Info "Windows Installer patch cache found - use Disk Cleanup tool for safe removal"
    }
    
    Stop-Section
}

# ============================================================================
# Windows Logs
# ============================================================================

function Clear-SystemLogs {
    <#
    .SYNOPSIS
        Clean Windows system logs (requires admin)
    #>
    if (-not (Test-IsAdmin)) {
        Write-Warning "System log cleanup requires administrator privileges"
        return
    }
    
    Start-Section "System Logs"
    
    # Windows Logs
    $windowsLogs = "$env:SystemRoot\Logs"
    if (Test-Path $windowsLogs) {
        Remove-OldFiles -Path $windowsLogs -DaysOld $script:Config.LogAgeDays -Description "Windows logs"
    }
    
    # CBS logs (Component Based Servicing)
    $cbsLogs = "$env:SystemRoot\Logs\CBS"
    if (Test-Path $cbsLogs) {
        Remove-OldFiles -Path $cbsLogs -DaysOld 14 -Filter "*.log" -Description "CBS logs"
    }
    
    # DISM logs
    $dismLogs = "$env:SystemRoot\Logs\DISM"
    if (Test-Path $dismLogs) {
        Remove-OldFiles -Path $dismLogs -DaysOld 14 -Description "DISM logs"
    }
    
    # Windows Error Reporting
    $werSystem = "$env:ProgramData\Microsoft\Windows\WER"
    if (Test-Path $werSystem) {
        Clear-DirectoryContents -Path "$werSystem\ReportArchive" -Description "System Error Reports"
        Clear-DirectoryContents -Path "$werSystem\ReportQueue" -Description "System Error Queue"
    }
    
    # Event logs (just clear old backups, not active logs)
    $eventLogBackups = "$env:SystemRoot\System32\winevt\Logs"
    if (Test-Path $eventLogBackups) {
        $oldBackups = Get-ChildItem -Path $eventLogBackups -Filter "Archive-*.evtx" -ErrorAction SilentlyContinue
        if ($oldBackups) {
            Remove-SafeItems -Paths ($oldBackups | ForEach-Object { $_.FullName }) -Description "Event log archives"
        }
    }
    
    # IIS logs (if installed)
    $iisLogs = "$env:SystemDrive\inetpub\logs\LogFiles"
    if (Test-Path $iisLogs) {
        Remove-OldFiles -Path $iisLogs -DaysOld 30 -Description "IIS logs"
    }
    
    Stop-Section
}

# ============================================================================
# Memory Dumps
# ============================================================================

function Clear-MemoryDumps {
    <#
    .SYNOPSIS
        Clean system memory dumps (requires admin)
    #>
    if (-not (Test-IsAdmin)) {
        Write-Warning "Memory dump cleanup requires administrator privileges"
        return
    }
    
    Start-Section "Memory Dumps"
    
    # System minidumps
    $minidump = "$env:SystemRoot\Minidump"
    if (Test-Path $minidump) {
        Remove-OldFiles -Path $minidump -DaysOld $script:Config.CrashReportAgeDays -Description "Minidumps"
    }
    
    # Full memory dump
    $memoryDmp = "$env:SystemRoot\MEMORY.DMP"
    if (Test-Path $memoryDmp) {
        $dmpSize = (Get-Item $memoryDmp).Length
        if ($dmpSize -gt 0) {
            Remove-SafeItem -Path $memoryDmp -Description "Full memory dump ($(Format-ByteSize $dmpSize))"
        }
    }
    
    # LiveKernelReports
    $liveKernel = "$env:SystemRoot\LiveKernelReports"
    if (Test-Path $liveKernel) {
        Remove-OldFiles -Path $liveKernel -DaysOld 7 -Description "LiveKernel reports"
    }
    
    Stop-Section
}

# ============================================================================
# Windows Defender
# ============================================================================

function Clear-DefenderCache {
    <#
    .SYNOPSIS
        Clean Windows Defender caches and history
    #>
    if (-not (Test-IsAdmin)) {
        Write-Warning "Defender cleanup requires administrator privileges"
        return
    }
    
    Start-Section "Windows Defender"
    
    # Defender scan history
    $defenderHistory = "$env:ProgramData\Microsoft\Windows Defender\Scans\History"
    if (Test-Path $defenderHistory) {
        Remove-OldFiles -Path $defenderHistory -DaysOld 30 -Description "Defender scan history"
    }
    
    # Defender quarantine (be careful - don't auto-clean)
    $quarantine = "$env:ProgramData\Microsoft\Windows Defender\Quarantine"
    if (Test-Path $quarantine) {
        $quarantineItems = Get-ChildItem -Path $quarantine -Recurse -ErrorAction SilentlyContinue
        if ($quarantineItems) {
            Write-Warning "Defender quarantine has items - review in Windows Security before cleaning"
        }
    }
    
    Stop-Section
}

# ============================================================================
# Disk Cleanup Integration
# ============================================================================

function Invoke-DiskCleanup {
    <#
    .SYNOPSIS
        Run Windows Disk Cleanup utility with common options
    #>
    param(
        [switch]$SystemFiles,
        [switch]$Silent
    )
    
    Start-Section "Disk Cleanup"
    
    if (Test-DryRunMode) {
        Write-DryRun "Would run Windows Disk Cleanup"
        Stop-Section
        return
    }
    
    # Create a sageset with our preferred options
    $sagesetNum = 99
    $cleanupKeys = @(
        "Active Setup Temp Folders"
        "BranchCache"
        "Downloaded Program Files"
        "Internet Cache Files"
        "Memory Dump Files"
        "Old ChkDsk Files"
        "Previous Installations"
        "Recycle Bin"
        "Setup Log Files"
        "System error memory dump files"
        "System error minidump files"
        "Temporary Files"
        "Temporary Setup Files"
        "Thumbnail Cache"
        "Update Cleanup"
        "Upgrade Discarded Files"
        "Windows Error Reporting Archive Files"
        "Windows Error Reporting Queue Files"
        "Windows Error Reporting System Archive Files"
        "Windows Error Reporting System Queue Files"
        "Windows Upgrade Log Files"
    )
    
    # Set registry keys for sageset
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
    foreach ($key in $cleanupKeys) {
        $keyPath = Join-Path $regPath $key
        if (Test-Path $keyPath) {
            Set-ItemProperty -Path $keyPath -Name "StateFlags$sagesetNum" -Value 2 -ErrorAction SilentlyContinue
        }
    }
    
    Write-Info "Running Disk Cleanup..."
    
    if ($Silent) {
        Start-Process cleanmgr.exe -ArgumentList "/sagerun:$sagesetNum" -Wait -WindowStyle Hidden
    }
    else {
        Start-Process cleanmgr.exe -ArgumentList "/sagerun:$sagesetNum" -Wait
    }
    
    Write-Success "Disk Cleanup completed"
    
    Stop-Section
}

# ============================================================================
# Storage Sense
# ============================================================================

function Invoke-StorageSense {
    <#
    .SYNOPSIS
        Trigger Windows Storage Sense cleanup
    #>
    Start-Section "Storage Sense"
    
    if (Test-DryRunMode) {
        Write-DryRun "Would trigger Storage Sense"
        Stop-Section
        return
    }
    
    # Check if Storage Sense is available (Windows 10 1809+)
    $storageSenseKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
    if (-not (Test-Path $storageSenseKey)) {
        Write-Warning "Storage Sense not available on this system"
        Stop-Section
        return
    }
    
    Write-Info "Triggering Storage Sense..."
    
    # Run storage sense
    $ssPath = "$env:SystemRoot\System32\StorSenseConfig.exe"
    if (Test-Path $ssPath) {
        Start-Process $ssPath -ArgumentList "/cleanup" -Wait -ErrorAction SilentlyContinue
        Write-Success "Storage Sense cleanup triggered"
    }
    else {
        Write-Warning "Storage Sense executable not found"
    }
    
    Stop-Section
}

# ============================================================================
# Main System Cleanup
# ============================================================================

function Invoke-SystemCleanup {
    <#
    .SYNOPSIS
        Run all system-level cleanup operations
    #>
    param(
        [switch]$IncludeLogs,
        [switch]$IncludeDumps,
        [switch]$IncludeDefender,
        [switch]$IncludeDiskCleanup,
        [switch]$All
    )
    
    if (-not (Test-IsAdmin)) {
        Write-Error "System cleanup requires administrator privileges"
        Write-Info "Please run WinMole as Administrator"
        return
    }
    
    Reset-CleanupStats
    
    # Always clean system caches
    Clear-SystemCaches
    
    if ($All -or $IncludeLogs) {
        Clear-SystemLogs
    }
    
    if ($All -or $IncludeDumps) {
        Clear-MemoryDumps
    }
    
    if ($All -or $IncludeDefender) {
        Clear-DefenderCache
    }
    
    if ($All -or $IncludeDiskCleanup) {
        Invoke-DiskCleanup -Silent
    }
    
    $stats = Get-CleanupStats
    Show-Summary -SizeBytes ($stats.TotalSizeKB * 1024) -ItemCount $stats.TotalItems -Action "Cleaned"
}

# ============================================================================
# Exports (functions are available via dot-sourcing)
# ============================================================================
# Functions: Clear-SystemCaches, Clear-SystemLogs, Invoke-SystemCleanup, etc.
