# WinMole - Uninstall Command
# Smart application uninstaller with leftover detection

#Requires -Version 5.1
param(
    [string]$AppName,
    [switch]$List,
    [switch]$Leftovers,
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

function Show-UninstallHelp {
    $cyan = $script:Colors.Cyan
    $gray = $script:Colors.Gray
    $nc = $script:Colors.NC
    
    Write-Host ""
    Write-Host "  ${cyan}WinMole Uninstall${nc} - Smart app removal"
    Write-Host ""
    Write-Host "  ${gray}USAGE:${nc}"
    Write-Host "    winmole uninstall [options]"
    Write-Host "    winmole uninstall <app-name>"
    Write-Host ""
    Write-Host "  ${gray}OPTIONS:${nc}"
    Write-Host "    -List           List installed applications"
    Write-Host "    -Leftovers      Scan for leftover files from uninstalled apps"
    Write-Host "    -DryRun         Preview changes without deleting"
    Write-Host "    -Help           Show this help"
    Write-Host ""
    Write-Host "  ${gray}EXAMPLES:${nc}"
    Write-Host "    winmole uninstall                # Interactive mode"
    Write-Host "    winmole uninstall -List          # List all apps"
    Write-Host "    winmole uninstall 'VLC'          # Uninstall VLC"
    Write-Host "    winmole uninstall -Leftovers     # Find leftover files"
    Write-Host ""
}

# ============================================================================
# Application Discovery
# ============================================================================

function Get-InstalledApps {
    <#
    .SYNOPSIS
        Get list of installed applications from registry and Windows
    #>
    $apps = [System.Collections.ArrayList]::new()
    
    # Registry locations for installed apps
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($path in $regPaths) {
        $regApps = Get-ItemProperty $path -ErrorAction SilentlyContinue | 
                   Where-Object { $_.DisplayName -and $_.UninstallString }
        
        foreach ($app in $regApps) {
            $appInfo = @{
                Name            = $app.DisplayName
                Version         = $app.DisplayVersion
                Publisher       = $app.Publisher
                InstallLocation = $app.InstallLocation
                UninstallString = $app.UninstallString
                QuietUninstall  = $app.QuietUninstallString
                EstimatedSize   = if ($app.EstimatedSize) { $app.EstimatedSize * 1024 } else { 0 }
                InstallDate     = $app.InstallDate
                Type            = "Win32"
            }
            [void]$apps.Add($appInfo)
        }
    }
    
    # UWP / Store apps
    try {
        $uwpApps = Get-AppxPackage -ErrorAction SilentlyContinue | 
                   Where-Object { $_.IsFramework -eq $false }
        
        foreach ($app in $uwpApps) {
            $appInfo = @{
                Name            = $app.Name
                Version         = $app.Version
                Publisher       = $app.Publisher
                InstallLocation = $app.InstallLocation
                UninstallString = $null
                QuietUninstall  = $null
                EstimatedSize   = 0
                InstallDate     = $null
                Type            = "UWP"
                PackageFullName = $app.PackageFullName
            }
            [void]$apps.Add($appInfo)
        }
    }
    catch {
        Write-Debug "Could not enumerate UWP apps: $_"
    }
    
    # Remove duplicates by name and sort
    $uniqueApps = $apps | Group-Object Name | ForEach-Object { $_.Group[0] } | Sort-Object Name
    
    return $uniqueApps
}

function Find-App {
    <#
    .SYNOPSIS
        Find an app by name (partial match)
    #>
    param([string]$SearchTerm)
    
    $apps = Get-InstalledApps
    $matches = $apps | Where-Object { $_.Name -like "*$SearchTerm*" }
    
    return $matches
}

# ============================================================================
# Uninstallation
# ============================================================================

function Uninstall-Application {
    <#
    .SYNOPSIS
        Uninstall an application
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$App,
        
        [switch]$CleanLeftovers
    )
    
    $name = $App.Name
    Write-Info "Uninstalling: $name"
    
    if (Test-DryRunMode) {
        Write-DryRun "Would uninstall $name"
        if ($CleanLeftovers) {
            Write-DryRun "Would clean leftover files for $name"
        }
        return $true
    }
    
    try {
        if ($App.Type -eq "UWP") {
            # UWP app removal
            Remove-AppxPackage -Package $App.PackageFullName -ErrorAction Stop
            Write-Success "Uninstalled UWP app: $name"
        }
        else {
            # Win32 app removal
            $uninstallCmd = if ($App.QuietUninstall) { $App.QuietUninstall } else { $App.UninstallString }
            
            if ($uninstallCmd -match "^msiexec") {
                # MSI uninstall
                $productCode = if ($uninstallCmd -match '\{[A-F0-9-]+\}') { $Matches[0] } else { $null }
                if ($productCode) {
                    Start-Process msiexec.exe -ArgumentList "/x $productCode /qn" -Wait -ErrorAction Stop
                }
                else {
                    Start-Process cmd.exe -ArgumentList "/c $uninstallCmd" -Wait
                }
            }
            else {
                # Regular uninstaller
                Start-Process cmd.exe -ArgumentList "/c `"$uninstallCmd`" /S" -Wait -ErrorAction SilentlyContinue
            }
            
            Write-Success "Uninstalled: $name"
        }
        
        # Clean leftovers if requested
        if ($CleanLeftovers) {
            $leftoverSize = Remove-AppLeftovers -AppName $name
            if ($leftoverSize -gt 0) {
                Write-Success "Cleaned $(Format-ByteSize $leftoverSize) of leftover files"
            }
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to uninstall $name : $_"
        return $false
    }
}

# ============================================================================
# Leftover Detection and Cleanup
# ============================================================================

function Get-AppLeftovers {
    <#
    .SYNOPSIS
        Find leftover files for an application
    #>
    param([string]$AppName)
    
    $leftovers = [System.Collections.ArrayList]::new()
    
    # Common locations to check
    $searchPaths = @(
        "$env:APPDATA"
        "$env:LOCALAPPDATA"
        "$env:ProgramData"
        "$env:ProgramFiles"
        "${env:ProgramFiles(x86)}"
        "$env:USERPROFILE\Documents"
    )
    
    # Simplify app name for matching
    $searchTerms = @($AppName)
    $simplified = $AppName -replace '[^a-zA-Z0-9]', ''
    if ($simplified -ne $AppName) {
        $searchTerms += $simplified
    }
    
    foreach ($basePath in $searchPaths) {
        if (-not (Test-Path $basePath)) { continue }
        
        foreach ($term in $searchTerms) {
            # Search for directories matching the app name
            $matchedDirs = Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name -like "*$term*" }
            
            foreach ($dir in $matchedDirs) {
                $size = Get-PathSize -Path $dir.FullName
                [void]$leftovers.Add(@{
                    Path = $dir.FullName
                    Size = $size
                    Type = "Directory"
                })
            }
        }
    }
    
    # Check registry for leftover entries
    $regPaths = @(
        "HKCU:\SOFTWARE\$AppName"
        "HKLM:\SOFTWARE\$AppName"
    )
    
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            [void]$leftovers.Add(@{
                Path = $regPath
                Size = 0
                Type = "Registry"
            })
        }
    }
    
    return $leftovers
}

function Remove-AppLeftovers {
    <#
    .SYNOPSIS
        Remove leftover files for an application
    #>
    param([string]$AppName)
    
    $leftovers = Get-AppLeftovers -AppName $AppName
    $totalSize = 0
    
    foreach ($leftover in $leftovers) {
        if ($leftover.Type -eq "Directory") {
            if (Test-SafePath -Path $leftover.Path) {
                if (Test-DryRunMode) {
                    Write-DryRun "Would remove: $($leftover.Path)"
                }
                else {
                    Remove-Item -Path $leftover.Path -Recurse -Force -ErrorAction SilentlyContinue
                }
                $totalSize += $leftover.Size
            }
        }
        elseif ($leftover.Type -eq "Registry") {
            if (Test-DryRunMode) {
                Write-DryRun "Would remove registry: $($leftover.Path)"
            }
            else {
                Remove-Item -Path $leftover.Path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    return $totalSize
}

function Find-AllLeftovers {
    <#
    .SYNOPSIS
        Find leftover files from all previously uninstalled applications
    #>
    Start-Section "Scanning for Leftovers"
    
    $installedApps = Get-InstalledApps | ForEach-Object { $_.Name }
    $leftovers = [System.Collections.ArrayList]::new()
    
    $searchPaths = @(
        "$env:APPDATA"
        "$env:LOCALAPPDATA"
    )
    
    $spinner = 0
    $total = 0
    
    foreach ($basePath in $searchPaths) {
        if (-not (Test-Path $basePath)) { continue }
        
        $dirs = Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue
        $total += $dirs.Count
    }
    
    $checked = 0
    
    foreach ($basePath in $searchPaths) {
        if (-not (Test-Path $basePath)) { continue }
        
        $dirs = Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue
        
        foreach ($dir in $dirs) {
            $checked++
            
            if ($checked % 10 -eq 0) {
                Update-Spinner "Checking directories... ($checked/$total)"
            }
            
            # Check if this directory belongs to an installed app
            $belongsToApp = $false
            foreach ($appName in $installedApps) {
                if ($dir.Name -like "*$appName*" -or $appName -like "*$($dir.Name)*") {
                    $belongsToApp = $true
                    break
                }
            }
            
            if (-not $belongsToApp) {
                # Check if directory is old (not modified recently)
                $lastMod = $dir.LastWriteTime
                if ($lastMod -lt (Get-Date).AddDays(-60)) {
                    $size = Get-PathSize -Path $dir.FullName
                    if ($size -gt 1MB) {  # Only report significant leftovers
                        [void]$leftovers.Add(@{
                            Path = $dir.FullName
                            Size = $size
                            LastModified = $lastMod
                        })
                    }
                }
            }
        }
    }
    
    Stop-Spinner
    Stop-Section
    
    return $leftovers | Sort-Object Size -Descending
}

# ============================================================================
# Interactive Mode
# ============================================================================

function Show-AppList {
    $apps = Get-InstalledApps
    
    $cyan = $script:Colors.Cyan
    $gray = $script:Colors.Gray
    $nc = $script:Colors.NC
    
    Write-Host ""
    Write-Host "  ${cyan}Installed Applications${nc} ($($apps.Count) total)"
    Write-Host ""
    
    foreach ($app in $apps | Select-Object -First 50) {
        $size = if ($app.EstimatedSize -gt 0) { Format-ByteSize $app.EstimatedSize } else { "?" }
        $type = if ($app.Type -eq "UWP") { "[UWP]" } else { "" }
        Write-Host "  $($app.Name) ${gray}$size $type${nc}"
    }
    
    if ($apps.Count -gt 50) {
        Write-Host ""
        Write-Host "  ${gray}... and $($apps.Count - 50) more${nc}"
    }
    Write-Host ""
}

function Show-UninstallMenu {
    $apps = Get-InstalledApps | Where-Object { $_.Type -eq "Win32" } | Select-Object -First 20
    
    $options = $apps | ForEach-Object {
        @{
            Name = $_.Name
            Description = if ($_.EstimatedSize -gt 0) { Format-ByteSize $_.EstimatedSize } else { "" }
            App = $_
        }
    }
    
    $selected = Show-SelectionList -Title "Select apps to uninstall" -Items $options -MultiSelect
    
    return $selected
}

# ============================================================================
# Main
# ============================================================================

function Main {
    Initialize-WinMole
    
    if ($Help) {
        Show-UninstallHelp
        return
    }
    
    if ($DryRun -or $env:WINMOLE_DRY_RUN -eq "1") {
        Set-DryRunMode -Enabled $true
        Write-Host ""
        Write-Warning "DRY RUN MODE - No changes will be made"
    }
    
    if ($List) {
        Show-AppList
        return
    }
    
    if ($Leftovers) {
        $leftovers = Find-AllLeftovers
        
        if ($leftovers.Count -eq 0) {
            Write-Host ""
            Write-Success "No significant leftover files found"
            Write-Host ""
            return
        }
        
        Write-Host ""
        Write-Host "  Found $($leftovers.Count) potential leftover directories:"
        Write-Host ""
        
        $totalSize = 0
        foreach ($leftover in $leftovers | Select-Object -First 20) {
            Write-Host "  $(Format-ByteSize $leftover.Size)  $($leftover.Path)"
            $totalSize += $leftover.Size
        }
        
        Write-Host ""
        Write-Host "  Total: $(Format-ByteSize $totalSize)"
        Write-Host ""
        
        if (Read-Confirmation -Prompt "Clean these leftovers?" -Default $false) {
            foreach ($leftover in $leftovers) {
                if (Test-SafePath -Path $leftover.Path) {
                    Remove-SafeItem -Path $leftover.Path -Description (Split-Path -Leaf $leftover.Path)
                }
            }
            Show-Summary -SizeBytes $totalSize -ItemCount $leftovers.Count -Action "Cleaned"
        }
        
        return
    }
    
    if ($AppName) {
        $matches = Find-App -SearchTerm $AppName
        
        if ($matches.Count -eq 0) {
            Write-Error "No applications found matching '$AppName'"
            return
        }
        
        if ($matches.Count -eq 1) {
            $app = $matches[0]
            Write-Host ""
            Write-Host "  Found: $($app.Name)"
            
            if (Read-Confirmation -Prompt "Uninstall $($app.Name)?" -Default $false) {
                Uninstall-Application -App $app -CleanLeftovers
            }
        }
        else {
            Write-Host ""
            Write-Host "  Multiple matches found:"
            for ($i = 0; $i -lt $matches.Count; $i++) {
                Write-Host "  [$i] $($matches[$i].Name)"
            }
            Write-Host ""
            $choice = Read-Host "  Enter number to uninstall (or press Enter to cancel)"
            
            if ($choice -match '^\d+$' -and [int]$choice -lt $matches.Count) {
                $app = $matches[[int]$choice]
                Uninstall-Application -App $app -CleanLeftovers
            }
        }
        
        return
    }
    
    # Interactive mode
    Clear-Host
    Show-Banner
    
    $selected = Show-UninstallMenu
    
    if ($selected.Count -eq 0) {
        Write-Host ""
        return
    }
    
    foreach ($item in $selected) {
        Uninstall-Application -App $item.App -CleanLeftovers
    }
}

# Run
try {
    Main
}
finally {
    Clear-TempFiles
}
