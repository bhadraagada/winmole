# WinMole - Optimize Command
# System optimization and maintenance tasks

#Requires -Version 5.1
param(
    [switch]$All,
    [switch]$Defrag,
    [switch]$Services,
    [switch]$Startup,
    [switch]$Network,
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Get script location
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libDir = Join-Path (Split-Path -Parent $scriptDir) "lib"

# Import modules
. "$libDir\core\common.ps1"

# ============================================================================
# Help
# ============================================================================

function Show-OptimizeHelp {
    $cyan = $script:Colors.Cyan
    $gray = $script:Colors.Gray
    $nc = $script:Colors.NC
    
    Write-Host ""
    Write-Host "  ${cyan}WinMole Optimize${nc} - System optimization"
    Write-Host ""
    Write-Host "  ${gray}USAGE:${nc}"
    Write-Host "    winmole optimize [options]"
    Write-Host ""
    Write-Host "  ${gray}OPTIONS:${nc}"
    Write-Host "    -All            Run all optimization tasks"
    Write-Host "    -Defrag         Optimize/defragment drives"
    Write-Host "    -Services       Optimize Windows services"
    Write-Host "    -Startup        Manage startup programs"
    Write-Host "    -Network        Reset network configuration"
    Write-Host "    -DryRun         Preview changes without applying"
    Write-Host "    -Help           Show this help"
    Write-Host ""
    Write-Host "  ${gray}EXAMPLES:${nc}"
    Write-Host "    winmole optimize           # Interactive mode"
    Write-Host "    winmole optimize -All      # Run all optimizations"
    Write-Host "    winmole optimize -Startup  # Manage startup items"
    Write-Host ""
}

# ============================================================================
# Drive Optimization
# ============================================================================

function Optimize-Drives {
    <#
    .SYNOPSIS
        Optimize/defragment drives (SSDs get TRIM, HDDs get defrag)
    #>
    Start-Section "Drive Optimization"
    
    if (-not (Test-IsAdmin)) {
        Write-Warning "Drive optimization requires administrator privileges"
        Stop-Section
        return
    }
    
    # Get fixed drives
    $drives = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" | 
              Where-Object { $_.Size -gt 0 }
    
    foreach ($drive in $drives) {
        $letter = $drive.DeviceID
        
        # Check if SSD or HDD
        $physicalDisk = Get-PhysicalDisk -ErrorAction SilentlyContinue | 
                        Where-Object { $_.MediaType -ne $null } |
                        Select-Object -First 1
        
        $isSSD = $physicalDisk.MediaType -eq "SSD"
        
        if (Test-DryRunMode) {
            if ($isSSD) {
                Write-DryRun "Would TRIM optimize $letter"
            }
            else {
                Write-DryRun "Would defragment $letter"
            }
            continue
        }
        
        Write-Info "Optimizing $letter..."
        
        try {
            if ($isSSD) {
                # TRIM for SSD
                Optimize-Volume -DriveLetter $letter.TrimEnd(':') -ReTrim -ErrorAction SilentlyContinue
                Write-Success "$letter TRIM optimization complete"
            }
            else {
                # Defrag for HDD
                Optimize-Volume -DriveLetter $letter.TrimEnd(':') -Defrag -ErrorAction SilentlyContinue
                Write-Success "$letter defragmentation complete"
            }
        }
        catch {
            Write-Warning "Could not optimize $letter : $_"
        }
    }
    
    Stop-Section
}

# ============================================================================
# Services Optimization
# ============================================================================

$script:OptionalServices = @{
    "DiagTrack" = @{
        Name        = "Connected User Experiences and Telemetry"
        Description = "Microsoft telemetry service"
        Safe        = $true
    }
    "dmwappushservice" = @{
        Name        = "WAP Push Message Routing Service"
        Description = "Telemetry routing"
        Safe        = $true
    }
    "SysMain" = @{
        Name        = "Superfetch"
        Description = "Preloads apps into memory (disable on SSD)"
        Safe        = $true
    }
    "WSearch" = @{
        Name        = "Windows Search"
        Description = "Indexing service (high disk usage)"
        Safe        = $false  # Many apps depend on this
    }
    "Fax" = @{
        Name        = "Fax"
        Description = "Fax service"
        Safe        = $true
    }
    "XblAuthManager" = @{
        Name        = "Xbox Live Auth Manager"
        Description = "Xbox authentication"
        Safe        = $true
    }
    "XblGameSave" = @{
        Name        = "Xbox Live Game Save"
        Description = "Xbox cloud saves"
        Safe        = $true
    }
}

function Optimize-Services {
    <#
    .SYNOPSIS
        Optimize Windows services
    #>
    Start-Section "Windows Services"
    
    if (-not (Test-IsAdmin)) {
        Write-Warning "Service optimization requires administrator privileges"
        Stop-Section
        return
    }
    
    foreach ($serviceName in $script:OptionalServices.Keys) {
        $serviceInfo = $script:OptionalServices[$serviceName]
        
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $service) { continue }
        
        $currentStartup = (Get-WmiObject Win32_Service -Filter "Name='$serviceName'").StartMode
        
        if ($currentStartup -eq "Disabled") {
            Write-Info "$($serviceInfo.Name) - already disabled"
            continue
        }
        
        if ($serviceInfo.Safe) {
            if (Test-DryRunMode) {
                Write-DryRun "Would disable $($serviceInfo.Name)"
            }
            else {
                try {
                    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                    Set-Service -Name $serviceName -StartupType Disabled -ErrorAction Stop
                    Write-Success "Disabled $($serviceInfo.Name)"
                }
                catch {
                    Write-Warning "Could not disable $($serviceInfo.Name)"
                }
            }
        }
        else {
            Write-Info "$($serviceInfo.Name) - skipped (may break functionality)"
        }
    }
    
    Stop-Section
}

# ============================================================================
# Startup Management
# ============================================================================

function Get-StartupItems {
    <#
    .SYNOPSIS
        Get list of startup programs
    #>
    $items = [System.Collections.ArrayList]::new()
    
    # Registry startup locations
    $regPaths = @(
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Scope = "User" }
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Scope = "Machine" }
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Scope = "Machine (32-bit)" }
    )
    
    foreach ($reg in $regPaths) {
        if (Test-Path $reg.Path) {
            $entries = Get-ItemProperty $reg.Path -ErrorAction SilentlyContinue
            
            foreach ($prop in $entries.PSObject.Properties) {
                if ($prop.Name -notlike "PS*") {
                    [void]$items.Add(@{
                        Name     = $prop.Name
                        Command  = $prop.Value
                        Location = $reg.Path
                        Scope    = $reg.Scope
                        Type     = "Registry"
                    })
                }
            }
        }
    }
    
    # Startup folders
    $startupFolders = @(
        @{ Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Scope = "User" }
        @{ Path = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"; Scope = "All Users" }
    )
    
    foreach ($folder in $startupFolders) {
        if (Test-Path $folder.Path) {
            $files = Get-ChildItem $folder.Path -File -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                [void]$items.Add(@{
                    Name     = $file.BaseName
                    Command  = $file.FullName
                    Location = $folder.Path
                    Scope    = $folder.Scope
                    Type     = "Folder"
                })
            }
        }
    }
    
    # Task Scheduler startup tasks
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | 
                 Where-Object { $_.Triggers.GetType().Name -match "BootTrigger|LogonTrigger" -and $_.State -eq "Ready" }
        
        foreach ($task in $tasks) {
            [void]$items.Add(@{
                Name     = $task.TaskName
                Command  = $task.Actions.Execute
                Location = $task.TaskPath
                Scope    = "Scheduled Task"
                Type     = "Task"
            })
        }
    }
    catch {
        Write-Debug "Could not enumerate scheduled tasks"
    }
    
    return $items
}

function Show-StartupItems {
    <#
    .SYNOPSIS
        Display and manage startup items
    #>
    Start-Section "Startup Programs"
    
    $items = Get-StartupItems
    
    if ($items.Count -eq 0) {
        Write-Info "No startup items found"
        Stop-Section
        return
    }
    
    $cyan = $script:Colors.Cyan
    $gray = $script:Colors.Gray
    $nc = $script:Colors.NC
    
    Write-Host ""
    Write-Host "  Found $($items.Count) startup items:"
    Write-Host ""
    
    $grouped = $items | Group-Object Scope
    foreach ($group in $grouped) {
        Write-Host "  ${cyan}$($group.Name):${nc}"
        foreach ($item in $group.Group) {
            Write-Host "    $($item.Name) ${gray}($($item.Type))${nc}"
        }
        Write-Host ""
    }
    
    Stop-Section
}

function Manage-StartupItems {
    <#
    .SYNOPSIS
        Interactive startup item management
    #>
    $items = Get-StartupItems | Where-Object { $_.Type -eq "Registry" }
    
    if ($items.Count -eq 0) {
        Write-Info "No manageable startup items found"
        return
    }
    
    $options = $items | ForEach-Object {
        @{
            Name        = $_.Name
            Description = $_.Scope
            Item        = $_
        }
    }
    
    $selected = Show-SelectionList -Title "Select startup items to disable" -Items $options -MultiSelect
    
    if ($selected.Count -eq 0) {
        return
    }
    
    foreach ($item in $selected) {
        $startupItem = $item.Item
        
        if (Test-DryRunMode) {
            Write-DryRun "Would disable startup: $($startupItem.Name)"
            continue
        }
        
        try {
            Remove-ItemProperty -Path $startupItem.Location -Name $startupItem.Name -ErrorAction Stop
            Write-Success "Disabled startup: $($startupItem.Name)"
        }
        catch {
            Write-Warning "Could not disable: $($startupItem.Name)"
        }
    }
}

# ============================================================================
# Network Reset
# ============================================================================

function Reset-NetworkConfig {
    <#
    .SYNOPSIS
        Reset network configuration
    #>
    Start-Section "Network Reset"
    
    if (-not (Test-IsAdmin)) {
        Write-Warning "Network reset requires administrator privileges"
        Stop-Section
        return
    }
    
    if (Test-DryRunMode) {
        Write-DryRun "Would flush DNS cache"
        Write-DryRun "Would reset Winsock catalog"
        Write-DryRun "Would reset TCP/IP stack"
        Stop-Section
        return
    }
    
    # Flush DNS
    Write-Info "Flushing DNS cache..."
    ipconfig /flushdns | Out-Null
    Write-Success "DNS cache flushed"
    
    # Reset Winsock
    Write-Info "Resetting Winsock catalog..."
    netsh winsock reset | Out-Null
    Write-Success "Winsock catalog reset"
    
    # Reset TCP/IP
    Write-Info "Resetting TCP/IP stack..."
    netsh int ip reset | Out-Null
    Write-Success "TCP/IP stack reset"
    
    Write-Warning "Restart your computer for changes to take effect"
    
    Stop-Section
}

# ============================================================================
# System Health Check
# ============================================================================

function Test-SystemHealth {
    <#
    .SYNOPSIS
        Run system health checks
    #>
    Start-Section "System Health"
    
    # Check disk space
    $drives = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3"
    foreach ($drive in $drives) {
        $freePercent = [Math]::Round(($drive.FreeSpace / $drive.Size) * 100)
        if ($freePercent -lt 10) {
            Write-Warning "$($drive.DeviceID) has only $freePercent% free space"
        }
        else {
            Write-Success "$($drive.DeviceID) has $freePercent% free space"
        }
    }
    
    # Check Windows Update status
    $lastUpdate = (Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1).InstalledOn
    $daysSinceUpdate = ((Get-Date) - $lastUpdate).Days
    if ($daysSinceUpdate -gt 30) {
        Write-Warning "Last Windows update was $daysSinceUpdate days ago"
    }
    else {
        Write-Success "Windows updated $daysSinceUpdate days ago"
    }
    
    # Check system file integrity (quick check)
    if (Test-IsAdmin) {
        Write-Info "Checking system integrity..."
        $sfcResult = sfc /verifyonly 2>&1
        if ($sfcResult -match "did not find any integrity violations") {
            Write-Success "System files are intact"
        }
        else {
            Write-Warning "System file issues detected - run 'sfc /scannow' as admin"
        }
    }
    
    Stop-Section
}

# ============================================================================
# Interactive Menu
# ============================================================================

function Show-OptimizeMenu {
    $options = @(
        @{ Name = "Drive Optimization"; Description = "TRIM/Defrag drives"; Action = "defrag" }
        @{ Name = "Service Optimization"; Description = "Disable unnecessary services"; Action = "services" }
        @{ Name = "Startup Management"; Description = "View/disable startup programs"; Action = "startup" }
        @{ Name = "Network Reset"; Description = "Reset network configuration"; Action = "network" }
        @{ Name = "System Health Check"; Description = "Check system status"; Action = "health" }
        @{ Name = "Run All"; Description = "All optimizations"; Action = "all" }
    )
    
    $selected = Show-Menu -Title "Select optimization task" -Options $options -AllowBack
    
    if ($null -eq $selected) {
        return $null
    }
    
    return $selected.Action
}

# ============================================================================
# Main
# ============================================================================

function Main {
    Initialize-WinMole
    
    if ($Help) {
        Show-OptimizeHelp
        return
    }
    
    if ($DryRun -or $env:WINMOLE_DRY_RUN -eq "1") {
        Set-DryRunMode -Enabled $true
        Write-Host ""
        Write-Warning "DRY RUN MODE - No changes will be made"
    }
    
    # Determine what to run
    $runDefrag = $false
    $runServices = $false
    $runStartup = $false
    $runNetwork = $false
    $runHealth = $false
    
    $noFlags = -not ($All -or $Defrag -or $Services -or $Startup -or $Network)
    
    if ($noFlags) {
        Clear-Host
        Show-Banner
        
        $action = Show-OptimizeMenu
        
        if ($null -eq $action) {
            Write-Host ""
            return
        }
        
        switch ($action) {
            "defrag" { $runDefrag = $true }
            "services" { $runServices = $true }
            "startup" { $runStartup = $true }
            "network" { $runNetwork = $true }
            "health" { $runHealth = $true }
            "all" {
                $runDefrag = $true
                $runServices = $true
                $runStartup = $true
                $runHealth = $true
            }
        }
    }
    else {
        if ($All) {
            $runDefrag = $true
            $runServices = $true
            $runStartup = $true
            $runNetwork = $true
            $runHealth = $true
        }
        else {
            $runDefrag = $Defrag
            $runServices = $Services
            $runStartup = $Startup
            $runNetwork = $Network
        }
    }
    
    Write-Host ""
    
    if ($runHealth) { Test-SystemHealth }
    if ($runDefrag) { Optimize-Drives }
    if ($runServices) { Optimize-Services }
    if ($runStartup) { 
        Show-StartupItems
        if (Read-Confirmation -Prompt "Manage startup items?" -Default $false) {
            Manage-StartupItems
        }
    }
    if ($runNetwork) { Reset-NetworkConfig }
    
    Write-Host ""
    Write-Success "Optimization complete"
    Write-Host ""
}

# Run
try {
    Main
}
finally {
    Clear-TempFiles
}
