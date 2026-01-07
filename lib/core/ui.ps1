# WinMole - UI Module
# Provides interactive UI components (menus, confirmations, etc.)

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Prevent multiple sourcing
if ((Get-Variable -Name 'WINMOLE_UI_LOADED' -Scope Script -ErrorAction SilentlyContinue) -and $script:WINMOLE_UI_LOADED) { return }
$script:WINMOLE_UI_LOADED = $true

# Import dependencies
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\base.ps1"
. "$scriptDir\log.ps1"

# ============================================================================
# Terminal Utilities
# ============================================================================

function Get-TerminalSize {
    <#
    .SYNOPSIS
        Get terminal width and height
    #>
    try {
        return @{
            Width  = $Host.UI.RawUI.WindowSize.Width
            Height = $Host.UI.RawUI.WindowSize.Height
        }
    }
    catch {
        return @{ Width = 80; Height = 24 }
    }
}

function Clear-Line {
    <#
    .SYNOPSIS
        Clear the current line
    #>
    $width = (Get-TerminalSize).Width
    Write-Host -NoNewline ("`r" + (" " * ($width - 1)) + "`r")
}

function Move-CursorUp {
    <#
    .SYNOPSIS
        Move cursor up N lines
    #>
    param([int]$Lines = 1)
    Write-Host -NoNewline "$([char]27)[$Lines`A"
}

function Move-CursorDown {
    <#
    .SYNOPSIS
        Move cursor down N lines
    #>
    param([int]$Lines = 1)
    Write-Host -NoNewline "$([char]27)[$Lines`B"
}

# ============================================================================
# Confirmation Dialogs
# ============================================================================

function Read-Confirmation {
    <#
    .SYNOPSIS
        Ask for yes/no confirmation
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        
        [bool]$Default = $false
    )
    
    $cyan = $script:Colors.Cyan
    $nc = $script:Colors.NC
    $hint = if ($Default) { "[Y/n]" } else { "[y/N]" }
    
    Write-Host -NoNewline "  ${cyan}$($script:Icons.Confirm)${nc} $Prompt $hint "
    
    $response = Read-Host
    
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default
    }
    
    return $response -match '^[Yy]'
}

function Read-ConfirmationDestructive {
    <#
    .SYNOPSIS
        Ask for confirmation on destructive operations (requires typing 'yes')
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        
        [string]$ConfirmText = "yes"
    )
    
    $red = $script:Colors.Red
    $nc = $script:Colors.NC
    
    Write-Host ""
    Write-Host "  ${red}$($script:Icons.Warning) WARNING: $Prompt${nc}"
    Write-Host "  Type '$ConfirmText' to confirm: " -NoNewline
    
    $response = Read-Host
    return $response -eq $ConfirmText
}

# ============================================================================
# Menu Components
# ============================================================================

function Show-Menu {
    <#
    .SYNOPSIS
        Display an interactive menu and return selected option
    .PARAMETER Title
        Menu title
    .PARAMETER Options
        Array of menu options (hashtables with Name and optionally Description, Action)
    .PARAMETER AllowBack
        Show back/exit option
    #>
    param(
        [string]$Title = "Menu",
        
        [Parameter(Mandatory)]
        [array]$Options,
        
        [switch]$AllowBack
    )
    
    $selected = 0
    $maxIndex = $Options.Count - 1
    
    # Add back option if allowed
    if ($AllowBack) {
        $Options = $Options + @{ Name = "Back"; Description = "Return to previous menu" }
        $maxIndex++
    }
    
    $purple = $script:Colors.PurpleBold
    $cyan = $script:Colors.Cyan
    $gray = $script:Colors.Gray
    $nc = $script:Colors.NC
    
    # Hide cursor
    Write-Host -NoNewline "$([char]27)[?25l"
    
    try {
        while ($true) {
            # Clear screen and show menu
            Clear-Host
            
            Write-Host ""
            Write-Host "  ${purple}$($script:Icons.Arrow) $Title${nc}"
            Write-Host ""
            
            for ($i = 0; $i -le $maxIndex; $i++) {
                $option = $Options[$i]
                $name = if ($option -is [hashtable]) { $option.Name } else { $option.ToString() }
                $desc = if ($option -is [hashtable] -and $option.Description) { " - $($option.Description)" } else { "" }
                
                if ($i -eq $selected) {
                    Write-Host "  ${cyan}> $name${nc}${gray}$desc${nc}"
                }
                else {
                    Write-Host "    $name${gray}$desc${nc}"
                }
            }
            
            Write-Host ""
            Write-Host "  ${gray}Use arrows or j/k to navigate, Enter to select, q to quit${nc}"
            
            # Read key
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            
            switch ($key.VirtualKeyCode) {
                38 { # Up arrow
                    $selected = if ($selected -gt 0) { $selected - 1 } else { $maxIndex }
                }
                40 { # Down arrow
                    $selected = if ($selected -lt $maxIndex) { $selected + 1 } else { 0 }
                }
                13 { # Enter
                    # Show cursor
                    Write-Host -NoNewline "$([char]27)[?25h"
                    
                    if ($AllowBack -and $selected -eq $maxIndex) {
                        return $null  # Back selected
                    }
                    return $Options[$selected]
                }
                default {
                    switch ($key.Character) {
                        'k' { $selected = if ($selected -gt 0) { $selected - 1 } else { $maxIndex } }
                        'j' { $selected = if ($selected -lt $maxIndex) { $selected + 1 } else { 0 } }
                        'q' { 
                            Write-Host -NoNewline "$([char]27)[?25h"
                            return $null 
                        }
                    }
                }
            }
        }
    }
    finally {
        # Ensure cursor is shown
        Write-Host -NoNewline "$([char]27)[?25h"
    }
}

function Show-SelectionList {
    <#
    .SYNOPSIS
        Display a multi-select list
    #>
    param(
        [string]$Title = "Select Items",
        
        [Parameter(Mandatory)]
        [array]$Items,
        
        [switch]$MultiSelect
    )
    
    $cursor = 0
    $selected = @{}
    $maxIndex = $Items.Count - 1
    
    $purple = $script:Colors.PurpleBold
    $cyan = $script:Colors.Cyan
    $green = $script:Colors.Green
    $gray = $script:Colors.Gray
    $nc = $script:Colors.NC
    
    Write-Host -NoNewline "$([char]27)[?25l"
    
    try {
        while ($true) {
            Clear-Host
            
            Write-Host ""
            Write-Host "  ${purple}$($script:Icons.Arrow) $Title${nc}"
            if ($MultiSelect) {
                Write-Host "  ${gray}Space to toggle, Enter to confirm${nc}"
            }
            Write-Host ""
            
            for ($i = 0; $i -le $maxIndex; $i++) {
                $item = $Items[$i]
                $name = if ($item -is [hashtable]) { $item.Name } else { $item.ToString() }
                $check = if ($selected[$i]) { "$($script:Icons.Success)" } else { "$($script:Icons.Empty)" }
                
                if ($i -eq $cursor) {
                    Write-Host "  ${cyan}> ${check} $name${nc}"
                }
                else {
                    $checkColor = if ($selected[$i]) { $green } else { $gray }
                    Write-Host "    ${checkColor}${check}${nc} $name"
                }
            }
            
            Write-Host ""
            Write-Host "  ${gray}j/k or arrows to navigate, space to select, Enter to confirm, q to cancel${nc}"
            
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            
            switch ($key.VirtualKeyCode) {
                38 { $cursor = if ($cursor -gt 0) { $cursor - 1 } else { $maxIndex } }
                40 { $cursor = if ($cursor -lt $maxIndex) { $cursor + 1 } else { 0 } }
                32 { # Space
                    if ($MultiSelect) {
                        $selected[$cursor] = -not $selected[$cursor]
                    }
                    else {
                        $selected = @{ $cursor = $true }
                    }
                }
                13 { # Enter
                    Write-Host -NoNewline "$([char]27)[?25h"
                    $result = @()
                    foreach ($key in $selected.Keys) {
                        if ($selected[$key]) {
                            $result += $Items[$key]
                        }
                    }
                    return $result
                }
                default {
                    switch ($key.Character) {
                        'k' { $cursor = if ($cursor -gt 0) { $cursor - 1 } else { $maxIndex } }
                        'j' { $cursor = if ($cursor -lt $maxIndex) { $cursor + 1 } else { 0 } }
                        ' ' { 
                            if ($MultiSelect) {
                                $selected[$cursor] = -not $selected[$cursor]
                            }
                            else {
                                $selected = @{ $cursor = $true }
                            }
                        }
                        'q' {
                            Write-Host -NoNewline "$([char]27)[?25h"
                            return @()
                        }
                    }
                }
            }
        }
    }
    finally {
        Write-Host -NoNewline "$([char]27)[?25h"
    }
}

# ============================================================================
# Banner / Header
# ============================================================================

function Show-Banner {
    <#
    .SYNOPSIS
        Display the WinMole ASCII banner
    #>
    $purple = $script:Colors.Purple
    $cyan = $script:Colors.Cyan
    $nc = $script:Colors.NC
    
    $banner = @"

  ${purple}██╗    ██╗██╗███╗   ██╗${cyan}███╗   ███╗ ██████╗ ██╗     ███████╗${nc}
  ${purple}██║    ██║██║████╗  ██║${cyan}████╗ ████║██╔═══██╗██║     ██╔════╝${nc}
  ${purple}██║ █╗ ██║██║██╔██╗ ██║${cyan}██╔████╔██║██║   ██║██║     █████╗  ${nc}
  ${purple}██║███╗██║██║██║╚██╗██║${cyan}██║╚██╔╝██║██║   ██║██║     ██╔══╝  ${nc}
  ${purple}╚███╔███╔╝██║██║ ╚████║${cyan}██║ ╚═╝ ██║╚██████╔╝███████╗███████╗${nc}
  ${purple} ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝${cyan}╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚══════╝${nc}

"@
    
    Write-Host $banner
}

function Show-Header {
    <#
    .SYNOPSIS
        Display a section header
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        
        [string]$Subtitle = ""
    )
    
    $purple = $script:Colors.PurpleBold
    $gray = $script:Colors.Gray
    $nc = $script:Colors.NC
    
    Write-Host ""
    Write-Host "  ${purple}$Title${nc}"
    if ($Subtitle) {
        Write-Host "  ${gray}$Subtitle${nc}"
    }
    Write-Host ""
}

# ============================================================================
# Summary Display
# ============================================================================

function Show-Summary {
    <#
    .SYNOPSIS
        Display cleanup summary
    #>
    param(
        [long]$SizeBytes = 0,
        [int]$ItemCount = 0,
        [string]$Action = "Cleaned"
    )
    
    $green = $script:Colors.Green
    $cyan = $script:Colors.Cyan
    $nc = $script:Colors.NC
    
    $sizeHuman = Format-ByteSize -Bytes $SizeBytes
    
    Write-Host ""
    Write-Host "  $($green)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$($nc)"
    Write-Host "  $($green)$($script:Icons.Success)$($nc) $($Action): $($cyan)$($sizeHuman)$($nc) across $($cyan)$($ItemCount)$($nc) items"
    Write-Host "  $($green)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$($nc)"
    Write-Host ""
}

# ============================================================================
# Exports (functions are available via dot-sourcing)
# ============================================================================
# Functions: Show-Menu, Show-Banner, Read-Confirmation, etc.
