#!/usr/bin/env pwsh
# WinMole Installer
# Installs WinMole to the system and adds to PATH

#Requires -Version 5.1
param(
    [string]$InstallDir = "$env:LOCALAPPDATA\WinMole",
    [switch]$AddToPath,
    [switch]$CreateShortcut,
    [switch]$Uninstall,
    [switch]$Force,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ============================================================================
# Configuration
# ============================================================================

$script:VERSION = "1.0.0"
$script:SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ShortcutName = "WinMole"

# Colors
$script:ESC = [char]27
$script:Colors = @{
    Red     = "$($script:ESC)[31m"
    Green   = "$($script:ESC)[32m"
    Yellow  = "$($script:ESC)[33m"
    Blue    = "$($script:ESC)[34m"
    Cyan    = "$($script:ESC)[36m"
    Gray    = "$($script:ESC)[90m"
    NC      = "$($script:ESC)[0m"
}

# ============================================================================
# Helpers
# ============================================================================

function Write-Info {
    param([string]$Message)
    $c = $script:Colors
    Write-Host "  $($c.Blue)INFO$($c.NC)  $Message"
}

function Write-Success {
    param([string]$Message)
    $c = $script:Colors
    Write-Host "  $($c.Green)OK$($c.NC)    $Message"
}

function Write-Warning {
    param([string]$Message)
    $c = $script:Colors
    Write-Host "  $($c.Yellow)WARN$($c.NC)  $Message"
}

function Write-Error {
    param([string]$Message)
    $c = $script:Colors
    Write-Host "  $($c.Red)ERROR$($c.NC) $Message"
}

function Show-Banner {
    $c = $script:Colors
    Write-Host ""
    Write-Host "  $($c.Cyan)╦ ╦╦╔╗╔╔╦╗╔═╗╦  ╔═╗$($c.NC)"
    Write-Host "  $($c.Cyan)║║║║║║║║║║║ ║║  ║╣ $($c.NC)"
    Write-Host "  $($c.Cyan)╚╩╝╩╝╚╝╩ ╩╚═╝╩═╝╚═╝$($c.NC)"
    Write-Host "  $($c.Gray)Windows System Maintenance$($c.NC)"
    Write-Host ""
}

function Show-Help {
    Show-Banner
    
    $c = $script:Colors
    Write-Host "  $($c.Green)USAGE:$($c.NC)"
    Write-Host ""
    Write-Host "    .\install.ps1 [options]"
    Write-Host ""
    Write-Host "  $($c.Green)OPTIONS:$($c.NC)"
    Write-Host ""
    Write-Host "    $($c.Cyan)-InstallDir [path]$($c.NC)   Installation directory"
    Write-Host "                         Default: $env:LOCALAPPDATA\WinMole"
    Write-Host ""
    Write-Host "    $($c.Cyan)-AddToPath$($c.NC)           Add WinMole to user PATH"
    Write-Host ""
    Write-Host "    $($c.Cyan)-CreateShortcut$($c.NC)      Create Start Menu shortcut"
    Write-Host ""
    Write-Host "    $($c.Cyan)-Uninstall$($c.NC)           Remove WinMole from system"
    Write-Host ""
    Write-Host "    $($c.Cyan)-Force$($c.NC)               Overwrite existing installation"
    Write-Host ""
    Write-Host "    $($c.Cyan)-Help$($c.NC)                Show this help message"
    Write-Host ""
    Write-Host "  $($c.Green)EXAMPLES:$($c.NC)"
    Write-Host ""
    Write-Host "    $($c.Gray)# Install with defaults$($c.NC)"
    Write-Host "    .\install.ps1"
    Write-Host ""
    Write-Host "    $($c.Gray)# Install and add to PATH$($c.NC)"
    Write-Host "    .\install.ps1 -AddToPath"
    Write-Host ""
    Write-Host "    $($c.Gray)# Custom install location$($c.NC)"
    Write-Host "    .\install.ps1 -InstallDir C:\Tools\WinMole -AddToPath"
    Write-Host ""
    Write-Host "    $($c.Gray)# Full installation$($c.NC)"
    Write-Host "    .\install.ps1 -AddToPath -CreateShortcut"
    Write-Host ""
    Write-Host "    $($c.Gray)# Uninstall$($c.NC)"
    Write-Host "    .\install.ps1 -Uninstall"
    Write-Host ""
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Add-ToUserPath {
    param([string]$Directory)
    
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    
    if ($currentPath -split ";" | Where-Object { $_ -eq $Directory }) {
        Write-Info "Already in PATH: $Directory"
        return $true
    }
    
    $newPath = if ($currentPath) { "$currentPath;$Directory" } else { $Directory }
    
    try {
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Success "Added to PATH: $Directory"
        
        # Update current session
        $env:PATH = "$env:PATH;$Directory"
        return $true
    }
    catch {
        Write-Error "Failed to update PATH: $_"
        return $false
    }
}

function Remove-FromUserPath {
    param([string]$Directory)
    
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    
    if (-not $currentPath) {
        return $true
    }
    
    $paths = $currentPath -split ";" | Where-Object { $_ -ne $Directory -and $_ -ne "" }
    $newPath = $paths -join ";"
    
    try {
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Success "Removed from PATH: $Directory"
        return $true
    }
    catch {
        Write-Error "Failed to update PATH: $_"
        return $false
    }
}

function New-StartMenuShortcut {
    param(
        [string]$TargetPath,
        [string]$ShortcutName,
        [string]$Description
    )
    
    $startMenuPath = [Environment]::GetFolderPath("StartMenu")
    $programsPath = Join-Path $startMenuPath "Programs"
    $shortcutPath = Join-Path $programsPath "$ShortcutName.lnk"
    
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "powershell.exe"
        $shortcut.Arguments = "-NoExit -ExecutionPolicy Bypass -File `"$TargetPath`""
        $shortcut.Description = $Description
        $shortcut.WorkingDirectory = Split-Path -Parent $TargetPath
        $shortcut.Save()
        
        Write-Success "Created shortcut: $shortcutPath"
        return $true
    }
    catch {
        Write-Error "Failed to create shortcut: $_"
        return $false
    }
}

function Remove-StartMenuShortcut {
    param([string]$ShortcutName)
    
    $startMenuPath = [Environment]::GetFolderPath("StartMenu")
    $programsPath = Join-Path $startMenuPath "Programs"
    $shortcutPath = Join-Path $programsPath "$ShortcutName.lnk"
    
    if (Test-Path $shortcutPath) {
        try {
            Remove-Item $shortcutPath -Force
            Write-Success "Removed shortcut: $shortcutPath"
            return $true
        }
        catch {
            Write-Error "Failed to remove shortcut: $_"
            return $false
        }
    }
    
    return $true
}

# ============================================================================
# Install
# ============================================================================

function Install-WinMole {
    Write-Info "Installing WinMole v$script:VERSION..."
    Write-Host ""
    
    # Check if already installed
    if ((Test-Path $InstallDir) -and -not $Force) {
        Write-Error "WinMole is already installed at: $InstallDir"
        Write-Host ""
        Write-Host "  Use -Force to overwrite or -Uninstall to remove first"
        Write-Host ""
        return $false
    }
    
    # Create install directory
    if (-not (Test-Path $InstallDir)) {
        try {
            New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
            Write-Success "Created directory: $InstallDir"
        }
        catch {
            Write-Error "Failed to create directory: $_"
            return $false
        }
    }
    
    # Copy files
    Write-Info "Copying files..."
    
    $filesToCopy = @(
        "winmole.ps1"
        "go.mod"
        "bin"
        "lib"
        "cmd"
    )
    
    foreach ($item in $filesToCopy) {
        $src = Join-Path $script:SourceDir $item
        $dst = Join-Path $InstallDir $item
        
        if (Test-Path $src) {
            try {
                if ((Get-Item $src).PSIsContainer) {
                    Copy-Item -Path $src -Destination $dst -Recurse -Force
                }
                else {
                    Copy-Item -Path $src -Destination $dst -Force
                }
                Write-Success "Copied: $item"
            }
            catch {
                Write-Error "Failed to copy $item`: $_"
                return $false
            }
        }
    }
    
    # Create scripts and tests directories if they don't exist
    $extraDirs = @("scripts", "tests")
    foreach ($dir in $extraDirs) {
        $dirPath = Join-Path $InstallDir $dir
        if (-not (Test-Path $dirPath)) {
            New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
        }
    }
    
    # Create launcher batch file for easier access
    $batchContent = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -NoLogo -File "%~dp0winmole.ps1" %*
"@
    $batchPath = Join-Path $InstallDir "winmole.cmd"
    Set-Content -Path $batchPath -Value $batchContent -Encoding ASCII
    Write-Success "Created launcher: winmole.cmd"
    
    # Add to PATH if requested
    if ($AddToPath) {
        Write-Host ""
        Add-ToUserPath -Directory $InstallDir
    }
    
    # Create shortcut if requested
    if ($CreateShortcut) {
        Write-Host ""
        $targetPath = Join-Path $InstallDir "winmole.ps1"
        New-StartMenuShortcut -TargetPath $targetPath -ShortcutName $script:ShortcutName -Description "Windows System Maintenance Toolkit"
    }
    
    Write-Host ""
    Write-Success "WinMole installed successfully!"
    Write-Host ""
    Write-Host "  Location: $InstallDir"
    Write-Host ""
    
    if ($AddToPath) {
        Write-Host "  Run 'winmole' from any terminal to start"
    }
    else {
        Write-Host "  Run the following to start:"
        Write-Host "    & `"$InstallDir\winmole.ps1`""
        Write-Host ""
        Write-Host "  Or add to PATH with:"
        Write-Host "    .\install.ps1 -AddToPath"
    }
    
    Write-Host ""
    return $true
}

# ============================================================================
# Uninstall
# ============================================================================

function Uninstall-WinMole {
    Write-Info "Uninstalling WinMole..."
    Write-Host ""
    
    # Check for existing installation
    $configPath = Join-Path $env:LOCALAPPDATA "WinMole"
    $installPath = if (Test-Path $InstallDir) { $InstallDir } elseif (Test-Path $configPath) { $configPath } else { $null }
    
    if (-not $installPath) {
        Write-Warning "WinMole is not installed"
        return $true
    }
    
    # Remove from PATH
    Remove-FromUserPath -Directory $installPath
    
    # Remove shortcut
    Remove-StartMenuShortcut -ShortcutName $script:ShortcutName
    
    # Remove installation directory
    try {
        Remove-Item -Path $installPath -Recurse -Force
        Write-Success "Removed directory: $installPath"
    }
    catch {
        Write-Error "Failed to remove directory: $_"
        return $false
    }
    
    # Remove config directory if different from install
    $configDir = Join-Path $env:USERPROFILE ".config\winmole"
    if (Test-Path $configDir) {
        Write-Info "Found config directory: $configDir"
        $response = Read-Host "  Remove config files? (y/N)"
        if ($response -eq "y" -or $response -eq "Y") {
            try {
                Remove-Item -Path $configDir -Recurse -Force
                Write-Success "Removed config: $configDir"
            }
            catch {
                Write-Warning "Failed to remove config: $_"
            }
        }
    }
    
    Write-Host ""
    Write-Success "WinMole uninstalled successfully!"
    Write-Host ""
    return $true
}

# ============================================================================
# Main
# ============================================================================

function Main {
    if ($Help) {
        Show-Help
        return
    }
    
    Show-Banner
    
    if ($Uninstall) {
        Uninstall-WinMole
    }
    else {
        Install-WinMole
    }
}

# Run
try {
    Main
}
catch {
    Write-Host ""
    Write-Error "Installation failed: $_"
    Write-Host ""
    exit 1
}
