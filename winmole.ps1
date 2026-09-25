#!/usr/bin/env pwsh
# WinMole - Windows System Maintenance Toolkit
# Main CLI entry point

#Requires -Version 5.1
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$CommandArgs,

    [Alias('v')]
    [switch]$Version,
    
    [Alias('h')]
    [switch]$ShowHelp
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Get script directory
$script:WINMOLE_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:WINMOLE_BIN = Join-Path $script:WINMOLE_ROOT "bin"
$script:WINMOLE_LIB = Join-Path $script:WINMOLE_ROOT "lib"

# Import core
. "$script:WINMOLE_LIB\core\common.ps1"

# ============================================================================
# Version Info
# ============================================================================

$script:WINMOLE_VER = "1.0.0"
$script:WINMOLE_BUILD = "2026-01-07"

function Show-Version {
    $info = Get-WinMoleVersion
    Write-Host "WinMole v$($info.Version)"
    Write-Host "Built: $($info.BuildDate)"
    Write-Host "PowerShell: $($info.PowerShell)"
    Write-Host "Windows: $($info.Windows)"
}

# ============================================================================
# Help
# ============================================================================

function Show-MainHelp {
    $cyan = $script:Colors.Cyan
    $gray = $script:Colors.Gray
    $green = $script:Colors.Green
    $nc = $script:Colors.NC

    Show-Banner

    Write-Host "  ${cyan}Windows System Maintenance Toolkit${nc}"
    Write-Host "  ${gray}Clean, optimize, and maintain your Windows system${nc}"
    Write-Host ""
    Write-Host "  ${green}COMMANDS:${nc}"
    Write-Host ""
    Write-Host "    ${cyan}clean${nc}       Deep system cleanup"
    Write-Host "    ${cyan}uninstall${nc}   Smart application uninstaller"
    Write-Host "    ${cyan}optimize${nc}    System optimization and repairs"
    Write-Host "    ${cyan}analyze${nc}     Disk space analyzer"
    Write-Host "    ${cyan}status${nc}      System monitor"
    Write-Host "    ${cyan}purge${nc}       Clean project artifacts"
    Write-Host ""
    Write-Host "  ${green}OPTIONS:${nc}"
    Write-Host ""
    Write-Host "    ${cyan}--version${nc}   Show version information"
    Write-Host "    ${cyan}--help${nc}      Show this help message"
    Write-Host ""
    Write-Host "  ${green}EXAMPLES:${nc}"
    Write-Host ""
    Write-Host "    ${gray}winmole${nc}                      ${gray}# Interactive menu${nc}"
    Write-Host "    ${gray}winmole clean${nc}                ${gray}# Deep cleanup${nc}"
    Write-Host "    ${gray}winmole clean --dry-run${nc}      ${gray}# Preview cleanup${nc}"
    Write-Host "    ${gray}winmole uninstall${nc}            ${gray}# Uninstall apps${nc}"
    Write-Host "    ${gray}winmole analyze${nc}              ${gray}# Disk analyzer${nc}"
    Write-Host "    ${gray}winmole status${nc}               ${gray}# System monitor${nc}"
    Write-Host "    ${gray}winmole optimize${nc}             ${gray}# Optimize system (includes repairs)${nc}"
    Write-Host "    ${gray}winmole optimize --dry-run${nc}   ${gray}# Preview optimizations${nc}"
    Write-Host "    ${gray}winmole purge${nc}                ${gray}# Clean dev artifacts${nc}"
    Write-Host ""
    Write-Host "  ${green}ENVIRONMENT:${nc}"
    Write-Host ""
    Write-Host "    ${cyan}WINMOLE_DRY_RUN=1${nc}    Preview without changes"
    Write-Host "    ${cyan}WINMOLE_DEBUG=1${nc}      Enable debug output"
    Write-Host ""
    Write-Host "  ${gray}Run '${nc}winmole <command> --help${gray}' for command-specific help${nc}"
    Write-Host ""
}

# ============================================================================
# Interactive Menu
# ============================================================================

function Show-MainMenu {
    $options = @(
        @{
            Name = "Clean"
            Description = "Deep system cleanup"
            Command = "clean"
            Icon = $script:Icons.Trash
        }
        @{
            Name = "Optimize"
            Description = "Optimization & repairs"
            Command = "optimize"
            Icon = $script:Icons.Arrow
        }
        @{
            Name = "Uninstall"
            Description = "Remove applications"
            Command = "uninstall"
            Icon = $script:Icons.Folder
        }
        @{
            Name = "Analyze"
            Description = "Disk space analyzer"
            Command = "analyze"
            Icon = $script:Icons.File
        }
        @{
            Name = "Status"
            Description = "System monitor"
            Command = "status"
            Icon = $script:Icons.Solid
        }
        @{
            Name = "Purge"
            Description = "Clean dev artifacts"
            Command = "purge"
            Icon = $script:Icons.List
        }
    )

    $selected = Show-Menu -Title "What would you like to do?" -Options $options -AllowBack

    if ($null -eq $selected) {
        return $null
    }

    return $selected.Command
}

# ============================================================================
# Command Router
# ============================================================================

function Invoke-WinMoleCommand {
    param(
        [string]$CommandName,
        [string[]]$Arguments
    )

    $scriptPath = Join-Path $script:WINMOLE_BIN "$CommandName.ps1"

    if (-not (Test-Path $scriptPath)) {
        Write-WinMoleError "Unknown command: $CommandName"
        Write-Host ""
        Write-Host "Run 'winmole --help' for available commands"
        return
    }

    # Execute the command script with arguments using splatting
    # This properly handles switch parameters passed as strings
    $argCount = if ($null -eq $Arguments) { 0 } else { @($Arguments).Count }
    if ($argCount -gt 0) {
        # Build a hashtable for splatting
        $splatParams = @{}
        $positionalArgs = @()

        foreach ($arg in $Arguments) {
            # Remove surrounding quotes if present
            $cleanArg = $arg.Trim("'`"")

            if ($cleanArg -match '^-{1,2}([\w-]+)$') {
                # It's a switch parameter (e.g., -DryRun or --dry-run)
                $paramName = $Matches[1]
                $splatParams[$paramName] = $true
            }
            elseif ($cleanArg -match '^-{1,2}([\w-]+)[=:](.+)$') {
                # It's a named parameter with value (e.g., --name=value)
                $paramName = $Matches[1]
                $paramValue = $Matches[2].Trim("'`"")
                $splatParams[$paramName] = $paramValue
            }
            else {
                # Positional argument
                $positionalArgs += $cleanArg
            }
        }

        # Execute with splatting
        if ($positionalArgs.Count -gt 0) {
            & $scriptPath @splatParams @positionalArgs
        }
        else {
            & $scriptPath @splatParams
        }
    }
    else {
        & $scriptPath
    }
}

# ============================================================================
# System Info Display
# ============================================================================

function Show-SystemInfo {
    $cyan = $script:Colors.Cyan
    $gray = $script:Colors.Gray
    $green = $script:Colors.Green
    $nc = $script:Colors.NC

    $winInfo = Get-WindowsVersion
    $freeSpace = Get-FreeSpace
    $isAdmin = if (Test-IsAdmin) { "${green}Yes${nc}" } else { "${gray}No${nc}" }

    Write-Host ""
    Write-Host "  ${gray}System:${nc} $($winInfo.Name)"
    Write-Host "  ${gray}Free Space:${nc} $freeSpace on $($env:SystemDrive)"
    Write-Host "  ${gray}Admin:${nc} $isAdmin"
    Write-Host ""
}

# ============================================================================
# Main
# ============================================================================

function Main {
    # Initialize
    if ($Command -in @('analyze', 'status') -and @($CommandArgs) -match '^-{1,2}json$') {
        Initialize-WinMole 6>$null
    }
    else {
        Initialize-WinMole
    }

    # Handle switches passed as strings (when called via batch file with quoted args)
    # e.g., winmole '-ShowHelp' becomes $Command = "-ShowHelp" instead of $ShowHelp = $true
    $effectiveShowHelp = $ShowHelp
    $effectiveVersion = $Version
    $effectiveCommand = $Command

    if ($Command -match '^-{1,2}(.+)$') {
        $switchName = $Matches[1].ToLower()
        switch ($switchName) {
            'showhelp' { $effectiveShowHelp = $true; $effectiveCommand = $null }
            'help' { $effectiveShowHelp = $true; $effectiveCommand = $null }
            'h' { $effectiveShowHelp = $true; $effectiveCommand = $null }
            'version' { $effectiveVersion = $true; $effectiveCommand = $null }
            'v' { $effectiveVersion = $true; $effectiveCommand = $null }
        }
    }

    # Handle version flag
    if ($effectiveVersion) {
        Show-Version
        return
    }

    # Handle help flag
    if ($effectiveShowHelp -and -not $effectiveCommand) {
        Show-MainHelp
        return
    }

    # If command specified, route to it
    if ($effectiveCommand) {
        $validCommands = @("clean", "uninstall", "analyze", "status", "optimize", "purge")

        if ($effectiveCommand -in $validCommands) {
            Invoke-WinMoleCommand -CommandName $effectiveCommand -Arguments $CommandArgs
        }
        else {
            Write-Error "Unknown command: $effectiveCommand"
            Write-Host ""
            Write-Host "Available commands: $($validCommands -join ', ')"
            Write-Host "Run 'winmole --help' for more information"
        }
        return
    }

    # Interactive mode
    Clear-Host
    Show-Banner
    Show-SystemInfo

    while ($true) {
        $selectedCommand = Show-MainMenu

        if ($null -eq $selectedCommand) {
            Clear-Host
            Write-Host ""
            Write-Host "  Goodbye!"
            Write-Host ""
            break
        }

        Clear-Host
        Invoke-WinMoleCommand -CommandName $selectedCommand -Arguments @()

        Write-Host ""
        Write-Host "  Press any key to continue..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Clear-Host
        Show-Banner
        Show-SystemInfo
    }
}

# Run
try {
    Main
}
catch {
    [Console]::Error.WriteLine("An error occurred: $_")
    exit 1
}
finally {
    Clear-TempFiles
    Restore-WinMoleConsoleEncoding
}
