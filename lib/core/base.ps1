# WinMole - Base Definitions and Utilities
# Core definitions, constants, and basic utility functions used by all modules

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Prevent multiple sourcing
if ((Get-Variable -Name 'WINMOLE_BASE_LOADED' -Scope Script -ErrorAction SilentlyContinue) -and $script:WINMOLE_BASE_LOADED) { return }
$script:WINMOLE_BASE_LOADED = $true

# ============================================================================
# Color Definitions (ANSI escape codes for modern terminals)
# ============================================================================
$script:ESC = [char]27
$script:Colors = @{
    Green      = "$ESC[0;32m"
    Blue       = "$ESC[0;34m"
    Cyan       = "$ESC[0;36m"
    Yellow     = "$ESC[0;33m"
    Purple     = "$ESC[0;35m"
    PurpleBold = "$ESC[1;35m"
    Red        = "$ESC[0;31m"
    Gray       = "$ESC[0;90m"
    White      = "$ESC[0;37m"
    NC         = "$ESC[0m"  # No Color / Reset
}

# ============================================================================
# Icon Definitions
# ============================================================================
$script:Icons = @{
    Confirm  = [char]0x25CE  # ◎
    Admin    = [char]0x2699  # ⚙
    Success  = [char]0x2713  # ✓
    Error    = [char]0x263B  # ☻
    Warning  = [char]0x25CF  # ●
    Empty    = [char]0x25CB  # ○
    Solid    = [char]0x25CF  # ●
    List     = [char]0x2022  # •
    Arrow    = [char]0x27A4  # ➤
    DryRun   = [char]0x2192  # →
    NavUp    = [char]0x2191  # ↑
    NavDown  = [char]0x2193  # ↓
    Folder   = [char]0x25A0  # ■ (folder substitute)
    File     = [char]0x25A1  # □ (file substitute)
    Trash    = [char]0x2718  # ✘ (trash substitute)
}

# ============================================================================
# Global Configuration Constants
# ============================================================================
$script:Config = @{
    TempFileAgeDays        = 7       # Temp file retention (days)
    OrphanAgeDays          = 60      # Orphaned data retention (days)
    MaxParallelJobs        = 15      # Parallel job limit
    LogAgeDays             = 7       # Log retention (days)
    CrashReportAgeDays     = 7       # Crash report retention (days)
    MaxIterations          = 100     # Max iterations for scans
    ConfigPath             = "$env:USERPROFILE\.config\winmole"
    CachePath              = "$env:USERPROFILE\.cache\winmole"
    WhitelistFile          = "$env:USERPROFILE\.config\winmole\whitelist.txt"
}

# ============================================================================
# Default Whitelist Patterns (paths to never clean)
# ============================================================================
$script:DefaultWhitelistPatterns = @(
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"     # Windows Explorer cache
    "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"        # User fonts
    "$env:APPDATA\Microsoft\Windows\Recent"            # Recent files (used by shell)
    "$env:LOCALAPPDATA\Packages\*"                     # UWP app data
    "$env:USERPROFILE\.vscode\extensions"              # VS Code extensions
    "$env:USERPROFILE\.nuget"                          # NuGet packages
    "$env:USERPROFILE\.cargo"                          # Rust packages
    "$env:USERPROFILE\.rustup"                         # Rust toolchain
    "$env:USERPROFILE\.m2\repository"                  # Maven repository
    "$env:USERPROFILE\.gradle\caches\modules-2\files-*" # Gradle modules
    "$env:USERPROFILE\.ollama\models"                  # Ollama AI models
    "$env:LOCALAPPDATA\JetBrains"                      # JetBrains IDEs
)

# ============================================================================
# Protected System Paths (NEVER touch these)
# ============================================================================
$script:ProtectedPaths = @(
    "C:\Windows"
    "C:\Windows\System32"
    "C:\Windows\SysWOW64"
    "C:\Program Files\Windows Defender"
    "C:\Program Files (x86)\Windows Defender"
    "C:\ProgramData\Microsoft\Windows Defender"
    "$env:SYSTEMROOT"
    "$env:WINDIR"
)

# ============================================================================
# System Utilities
# ============================================================================

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Check if running with administrator privileges
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-FreeSpace {
    <#
    .SYNOPSIS
        Get free disk space on system drive
    .OUTPUTS
        Human-readable string (e.g., "100GB")
    #>
    param([string]$Drive = $env:SystemDrive)
    
    $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$Drive'" -ErrorAction SilentlyContinue
    if ($disk) {
        return Format-ByteSize -Bytes $disk.FreeSpace
    }
    return "Unknown"
}

function Get-WindowsVersion {
    <#
    .SYNOPSIS
        Get Windows version information
    #>
    $os = Get-WmiObject Win32_OperatingSystem
    return @{
        Name    = $os.Caption
        Version = $os.Version
        Build   = $os.BuildNumber
        Arch    = $os.OSArchitecture
    }
}

function Get-CPUCores {
    <#
    .SYNOPSIS
        Get number of CPU cores
    #>
    return (Get-WmiObject Win32_Processor).NumberOfLogicalProcessors
}

function Get-OptimalParallelJobs {
    <#
    .SYNOPSIS
        Get optimal number of parallel jobs based on CPU cores
    #>
    param(
        [ValidateSet('scan', 'io', 'compute', 'default')]
        [string]$OperationType = 'default'
    )
    
    $cores = Get-CPUCores
    switch ($OperationType) {
        'scan'    { return [Math]::Min($cores * 2, 32) }
        'io'      { return [Math]::Min($cores * 2, 32) }
        'compute' { return $cores }
        default   { return [Math]::Min($cores + 2, 20) }
    }
}

# ============================================================================
# Path Utilities
# ============================================================================

function Test-ProtectedPath {
    <#
    .SYNOPSIS
        Check if a path is protected and should never be modified
    #>
    param([string]$Path)
    
    $normalizedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    
    foreach ($protected in $script:ProtectedPaths) {
        $normalizedProtected = [System.IO.Path]::GetFullPath($protected).TrimEnd('\')
        if ($normalizedPath -eq $normalizedProtected -or 
            $normalizedPath.StartsWith("$normalizedProtected\", [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Test-Whitelisted {
    <#
    .SYNOPSIS
        Check if path matches a whitelist pattern
    #>
    param([string]$Path)
    
    # Check default patterns
    foreach ($pattern in $script:DefaultWhitelistPatterns) {
        $expandedPattern = [Environment]::ExpandEnvironmentVariables($pattern)
        if ($Path -like $expandedPattern) {
            return $true
        }
    }
    
    # Check user whitelist file
    if (Test-Path $script:Config.WhitelistFile) {
        $userPatterns = Get-Content $script:Config.WhitelistFile -ErrorAction SilentlyContinue
        foreach ($pattern in $userPatterns) {
            $pattern = $pattern.Trim()
            if ($pattern -and -not $pattern.StartsWith('#')) {
                if ($Path -like $pattern) {
                    return $true
                }
            }
        }
    }
    
    return $false
}

function Resolve-SafePath {
    <#
    .SYNOPSIS
        Resolve and validate a path for safe operations
    #>
    param([string]$Path)
    
    try {
        $resolved = [System.IO.Path]::GetFullPath($Path)
        return $resolved
    }
    catch {
        return $null
    }
}

# ============================================================================
# Formatting Utilities
# ============================================================================

function Format-ByteSize {
    <#
    .SYNOPSIS
        Convert bytes to human-readable format
    #>
    param([long]$Bytes)
    
    if ($Bytes -ge 1TB) {
        return "{0:N2}TB" -f ($Bytes / 1TB)
    }
    elseif ($Bytes -ge 1GB) {
        return "{0:N2}GB" -f ($Bytes / 1GB)
    }
    elseif ($Bytes -ge 1MB) {
        return "{0:N1}MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return "{0:N0}KB" -f ($Bytes / 1KB)
    }
    else {
        return "{0}B" -f $Bytes
    }
}

function Format-Number {
    <#
    .SYNOPSIS
        Format a number with thousands separators
    #>
    param([long]$Number)
    return $Number.ToString("N0")
}

function Format-TimeSpan {
    <#
    .SYNOPSIS
        Format a timespan to human-readable string
    #>
    param([TimeSpan]$Duration)
    
    if ($Duration.TotalHours -ge 1) {
        return "{0:N1}h" -f $Duration.TotalHours
    }
    elseif ($Duration.TotalMinutes -ge 1) {
        return "{0:N0}m" -f $Duration.TotalMinutes
    }
    else {
        return "{0:N0}s" -f $Duration.TotalSeconds
    }
}

# ============================================================================
# Environment Detection
# ============================================================================

function Get-UserHome {
    <#
    .SYNOPSIS
        Get the current user's home directory
    #>
    return $env:USERPROFILE
}

function Get-TempPath {
    <#
    .SYNOPSIS
        Get the system temp path
    #>
    return [System.IO.Path]::GetTempPath()
}

function Get-ConfigPath {
    <#
    .SYNOPSIS
        Get WinMole config directory, creating it if needed
    #>
    $path = $script:Config.ConfigPath
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    return $path
}

function Get-CachePath {
    <#
    .SYNOPSIS
        Get WinMole cache directory, creating it if needed
    #>
    $path = $script:Config.CachePath
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    return $path
}

# ============================================================================
# Temporary File Management
# ============================================================================

$script:TempFiles = [System.Collections.ArrayList]::new()
$script:TempDirs = [System.Collections.ArrayList]::new()

function New-TempFile {
    <#
    .SYNOPSIS
        Create a tracked temporary file
    #>
    param([string]$Prefix = "winmole")
    
    $tempPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$Prefix-$([Guid]::NewGuid().ToString('N').Substring(0,8)).tmp")
    New-Item -ItemType File -Path $tempPath -Force | Out-Null
    [void]$script:TempFiles.Add($tempPath)
    return $tempPath
}

function New-TempDirectory {
    <#
    .SYNOPSIS
        Create a tracked temporary directory
    #>
    param([string]$Prefix = "winmole")
    
    $tempPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$Prefix-$([Guid]::NewGuid().ToString('N').Substring(0,8))")
    New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
    [void]$script:TempDirs.Add($tempPath)
    return $tempPath
}

function Clear-TempFiles {
    <#
    .SYNOPSIS
        Clean up all tracked temporary files and directories
    #>
    foreach ($file in $script:TempFiles) {
        if (Test-Path $file) {
            Remove-Item $file -Force -ErrorAction SilentlyContinue
        }
    }
    $script:TempFiles.Clear()
    
    foreach ($dir in $script:TempDirs) {
        if (Test-Path $dir) {
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $script:TempDirs.Clear()
}

# ============================================================================
# Exports (functions and variables are available via dot-sourcing)
# ============================================================================
# Variables: Colors, Icons, Config, ProtectedPaths, DefaultWhitelistPatterns
# Functions: Test-IsAdmin, Get-FreeSpace, Get-WindowsVersion, etc.
