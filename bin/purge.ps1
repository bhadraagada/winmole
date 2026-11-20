# WinMole - Purge Command
# Aggressive cleanup of project build artifacts

#Requires -Version 5.1
[CmdletBinding()]
param(
    [Alias('d')]
    [switch]$DebugMode,
    
    [Alias('p')]
    [switch]$Paths,
    
    [Alias('h')]
    [switch]$ShowHelp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Script location
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libDir = Join-Path (Split-Path -Parent $scriptDir) "lib"

# Import core modules
. "$libDir\core\base.ps1"
. "$libDir\core\log.ps1"
. "$libDir\core\ui.ps1"
. "$libDir\core\file_ops.ps1"

# ============================================================================
# Configuration
# ============================================================================

$script:DefaultSearchPaths = @(
    "$env:USERPROFILE\Documents"
    "$env:USERPROFILE\Projects"
    "$env:USERPROFILE\Code"
    "$env:USERPROFILE\Development"
    "$env:USERPROFILE\workspace"
    "$env:USERPROFILE\github"
    "$env:USERPROFILE\repos"
    "$env:USERPROFILE\src"
    "D:\Projects"
    "D:\Code"
    "D:\Development"
)

$script:ConfigFile = "$env:USERPROFILE\.config\winmole\purge_paths.txt"

# Artifact patterns to clean
$script:ArtifactPatterns = @(
    @{ Name = "node_modules"; Type = "Directory"; Language = "JavaScript/Node.js" }
    @{ Name = "vendor"; Type = "Directory"; Language = "PHP/Go" }
    @{ Name = ".venv"; Type = "Directory"; Language = "Python" }
    @{ Name = "venv"; Type = "Directory"; Language = "Python" }
    @{ Name = "__pycache__"; Type = "Directory"; Language = "Python" }
    @{ Name = ".pytest_cache"; Type = "Directory"; Language = "Python" }
    @{ Name = "target"; Type = "Directory"; Language = "Rust/Java" }
    @{ Name = "build"; Type = "Directory"; Language = "General" }
    @{ Name = "dist"; Type = "Directory"; Language = "General" }
    @{ Name = ".next"; Type = "Directory"; Language = "Next.js" }
    @{ Name = ".nuxt"; Type = "Directory"; Language = "Nuxt.js" }
    @{ Name = ".turbo"; Type = "Directory"; Language = "Turborepo" }
    @{ Name = ".parcel-cache"; Type = "Directory"; Language = "Parcel" }
    @{ Name = "bin"; Type = "Directory"; Language = ".NET" }
    @{ Name = "obj"; Type = "Directory"; Language = ".NET" }
    @{ Name = ".gradle"; Type = "Directory"; Language = "Java/Gradle" }
    @{ Name = ".idea"; Type = "Directory"; Language = "JetBrains IDE" }
    @{ Name = "*.log"; Type = "File"; Language = "Logs" }
)

$script:TotalSizeCleaned = 0
$script:ItemsCleaned = 0

# ============================================================================
# Help
# ============================================================================

function Show-PurgeHelp {
    $esc = [char]27
    Write-Host ""
    Write-Host "$esc[1;35mwinmole purge$esc[0m - Clean project build artifacts"
    Write-Host ""
    Write-Host "$esc[33mUsage:$esc[0m winmole purge [options]"
    Write-Host ""
    Write-Host "$esc[33mOptions:$esc[0m"
    Write-Host "  --paths      Edit custom scan directories"
    Write-Host "  --debug      Enable debug logging"
    Write-Host "  --help       Show this help message"
    Write-Host ""
    Write-Host "$esc[33mDefault Search Paths:$esc[0m"
    foreach ($path in $script:DefaultSearchPaths) {
        if (Test-Path $path) {
            Write-Host "  $esc[32m+$esc[0m $path"
        }
        else {
            Write-Host "  $esc[90m-$esc[0m $path (not found)"
        }
    }
    Write-Host ""
    Write-Host "$esc[33mArtifacts Cleaned:$esc[0m"
    Write-Host "  node_modules, vendor, venv, target, build, dist, __pycache__, etc."
    Write-Host ""
}

# ============================================================================
# Path Management
# ============================================================================

function Get-SearchPaths {
    <#
    .SYNOPSIS
        Get list of paths to scan for projects
    #>

    $paths = @()

    # An unreadable configuration must not broaden the scan to default paths.
    try {
        if (Test-Path -LiteralPath $script:ConfigFile -ErrorAction Stop) {
            $customPaths = Get-Content -LiteralPath $script:ConfigFile -ErrorAction Stop |
                           Where-Object { $_ -and -not $_.StartsWith('#') } |
                           ForEach-Object { $_.Trim() }
            foreach ($path in $customPaths) {
                if (Test-Path -LiteralPath $path -ErrorAction Stop) {
                    $paths += $path
                }
            }
        }
    }
    catch {
        throw "Cannot load purge search paths from '$($script:ConfigFile)'. Purge stopped without scanning. $($_.Exception.Message)"
    }

    # Add default paths if no custom paths or custom paths don't exist
    if ($null -eq $paths -or @($paths).Count -eq 0) {
        foreach ($path in $script:DefaultSearchPaths) {
            if (Test-Path $path) {
                $paths += $path
            }
        }
    }

    return $paths
}

function Edit-SearchPaths {
    <#
    .SYNOPSIS
        Open search paths configuration for editing
    #>

    $configDir = Split-Path -Parent $script:ConfigFile

    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    if (-not (Test-Path $script:ConfigFile)) {
        $defaultContent = @"
# WinMole Purge - Custom Search Paths
# Add directories to scan for project artifacts (one per line)
# Lines starting with # are ignored
#
# Examples:
# D:\MyProjects
# E:\Work\Code
#
# Default paths (used if this file is empty):
# $env:USERPROFILE\Documents
# $env:USERPROFILE\Projects
# $env:USERPROFILE\Code

"@
        Set-Content -Path $script:ConfigFile -Value $defaultContent
    }

    Write-Info "Opening paths configuration: $($script:ConfigFile)"
    Start-Process notepad.exe -ArgumentList $script:ConfigFile -Wait

    Write-Success "Configuration saved"
}

# ============================================================================
# Project Discovery
# ============================================================================

function Find-Projects {
    <#
    .SYNOPSIS
        Find all development projects in search paths
    #>
    param([string[]]$SearchPaths)

    $projects = @()

    # Project markers
    $projectMarkers = @(
        "package.json"      # Node.js
        "composer.json"     # PHP
        "Cargo.toml"        # Rust
        "go.mod"            # Go
        "pom.xml"           # Java/Maven
        "build.gradle"      # Java/Gradle
        "requirements.txt"  # Python
        "pyproject.toml"    # Python
        "*.csproj"          # .NET
        "*.sln"             # .NET Solution
    )

    $esc = [char]27
    $pathCount = 0
    $totalPaths = if ($null -eq $SearchPaths) { 0 } else { @($SearchPaths).Count }
    if ($totalPaths -eq 0) {
        return $projects
    }

    foreach ($searchPath in $SearchPaths) {
        $pathCount++
        Write-ProgressBar -Current $pathCount -Total $totalPaths `
            -Message "Searching: $searchPath"

        foreach ($marker in $projectMarkers) {
            try {
                $found = Get-ChildItem -Path $searchPath -Filter $marker -Recurse -Depth 4 -ErrorAction SilentlyContinue

                foreach ($item in $found) {
                    $projectPath = Split-Path -Parent $item.FullName

                    # Skip if already found or if it's inside node_modules, etc.
                    $existingPaths = @($projects | ForEach-Object { $_.Path })
                    if ($existingPaths -contains $projectPath) { continue }
                    if ($projectPath -like "*\node_modules\*") { continue }
                    if ($projectPath -like "*\vendor\*") { continue }
                    if ($projectPath -like "*\.git\*") { continue }

                    # Find artifacts in this project
                    $artifacts = @(Find-ProjectArtifacts -ProjectPath $projectPath)
                    $artifactCount = if ($null -eq $artifacts) { 0 } else { $artifacts.Count }

                    if ($artifactCount -gt 0) {
                        $totalSize = ($artifacts | Measure-Object -Property SizeKB -Sum).Sum
                        if ($null -eq $totalSize) { $totalSize = 0 }

                        $projects += [PSCustomObject]@{
                            Path = $projectPath
                            Name = Split-Path -Leaf $projectPath
                            Marker = $marker
                            Artifacts = $artifacts
                            TotalSizeKB = $totalSize
                            TotalSizeHuman = Format-ByteSize -Bytes ($totalSize * 1024)
                        }
                    }
                }
            }
            catch {
                Write-Debug "Error scanning $searchPath for $marker : $_"
            }
        }
    }

    Complete-Progress

    # Sort by size (largest first)
    return $projects | Sort-Object -Property TotalSizeKB -Descending
}

function Find-ProjectArtifacts {
    <#
    .SYNOPSIS
        Find cleanable artifacts in a project directory
    #>
    param([string]$ProjectPath)

    $artifacts = @()

    foreach ($pattern in $script:ArtifactPatterns) {
        $items = Get-ChildItem -Path $ProjectPath -Filter $pattern.Name -Force -ErrorAction SilentlyContinue

        foreach ($item in $items) {
            if ($pattern.Type -eq "Directory" -and $item.PSIsContainer) {
                $sizeKB = Get-PathSizeKB -Path $item.FullName

                $artifacts += [PSCustomObject]@{
                    Path = $item.FullName
                    Name = $item.Name
                    Type = "Directory"
                    Language = $pattern.Language
                    SizeKB = $sizeKB
                    SizeHuman = Format-ByteSize -Bytes ($sizeKB * 1024)
                }
            }
            elseif ($pattern.Type -eq "File" -and -not $item.PSIsContainer) {
                $sizeKB = [Math]::Ceiling($item.Length / 1024)

                $artifacts += [PSCustomObject]@{
                    Path = $item.FullName
                    Name = $item.Name
                    Type = "File"
                    Language = $pattern.Language
                    SizeKB = $sizeKB
                    SizeHuman = Format-ByteSize -Bytes ($sizeKB * 1024)
                }
            }
        }
    }

    return $artifacts
}

# ============================================================================
# Project Selection UI
# ============================================================================

function Show-ProjectSelectionMenu {
    <#
    .SYNOPSIS
        Interactive menu for selecting projects to clean
    #>
    param([array]$Projects)

    $projectCount = if ($null -eq $Projects) { 0 } else { @($Projects).Count }
    if ($projectCount -eq 0) {
        Write-Warning "No projects with cleanable artifacts found"
        return @()
    }

    $esc = [char]27
    $selectedIndices = @{}
    $currentIndex = 0
    $pageSize = 12
    $pageStart = 0

    try { [Console]::CursorVisible = $false } catch { }

    $frameLines = 0

    try {
        while ($true) {
            # Header
            $lines = @(
                ""
                "$esc[1;35mSelect Projects to Clean$esc[0m"
                ""
                "$esc[90mUse: $($script:Icons.NavUp)$($script:Icons.NavDown) navigate | Space select | A select all | Enter confirm | Q quit$esc[0m"
                ""
            )

            # Display projects
            $pageEnd = [Math]::Min($pageStart + $pageSize, $projectCount)

            for ($i = $pageStart; $i -lt $pageEnd; $i++) {
                $project = $Projects[$i]
                $isSelected = $selectedIndices.ContainsKey($i)
                $isCurrent = ($i -eq $currentIndex)

                $checkbox = if ($isSelected) { "$esc[32m[$($script:Icons.Success)]$esc[0m" } else { "[ ]" }

                $name = $project.Name
                if ($name.Length -gt 30) {
                    $name = $name.Substring(0, 27) + "..."
                }

                $artifactCount = if ($null -eq $project.Artifacts) { 0 } else { @($project.Artifacts).Count }

                $row = "  {0} {1,-32} {2,10} ({3} items)" -f $checkbox, $name, $project.TotalSizeHuman, $artifactCount

                if ($isCurrent) {
                    $lines += "$esc[7m$row$esc[0m"
                }
                else {
                    $lines += $row
                }
            }

            # Footer
            $lines += ""
            $selectedCount = $selectedIndices.Count
            if ($selectedCount -gt 0) {
                $totalSize = 0
                foreach ($idx in $selectedIndices.Keys) {
                    $totalSize += $Projects[$idx].TotalSizeKB
                }
                $totalSizeHuman = Format-ByteSize -Bytes ($totalSize * 1024)
                $lines += "$esc[33mSelected:$esc[0m $selectedCount projects ($totalSizeHuman)"
            }

            # Page indicator
            $totalPages = [Math]::Ceiling($projectCount / $pageSize)
            $currentPage = [Math]::Floor($pageStart / $pageSize) + 1
            $lines += "$esc[90mPage $currentPage of $totalPages | Total: $projectCount projects$esc[0m"

            # Render in place over the previous frame
            $frameLines = Write-MenuFrame -Lines $lines -PreviousLineCount $frameLines

            # Handle input
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                'UpArrow' {
                    if ($currentIndex -gt 0) {
                        $currentIndex--
                        if ($currentIndex -lt $pageStart) {
                            $pageStart = [Math]::Max(0, $pageStart - $pageSize)
                        }
                    }
                }
                'DownArrow' {
                    if ($currentIndex -lt $projectCount - 1) {
                        $currentIndex++
                        if ($currentIndex -ge $pageStart + $pageSize) {
                            $pageStart += $pageSize
                        }
                    }
                }
                'PageUp' {
                    $pageStart = [Math]::Max(0, $pageStart - $pageSize)
                    $currentIndex = $pageStart
                }
                'PageDown' {
                    $pageStart = [Math]::Min($projectCount - $pageSize, $pageStart + $pageSize)
                    if ($pageStart -lt 0) { $pageStart = 0 }
                    $currentIndex = $pageStart
                }
                'Spacebar' {
                    if ($selectedIndices.ContainsKey($currentIndex)) {
                        $selectedIndices.Remove($currentIndex)
                    }
                    else {
                        $selectedIndices[$currentIndex] = $true
                    }
                }
                'A' {
                    # Select/deselect all
                    if ($selectedIndices.Count -eq $projectCount) {
                        $selectedIndices.Clear()
                    }
                    else {
                        for ($i = 0; $i -lt $projectCount; $i++) {
                            $selectedIndices[$i] = $true
                        }
                    }
                }
                'Enter' {
                    if ($selectedIndices.Count -gt 0) {
                        $selected = @()
                        foreach ($idx in $selectedIndices.Keys) {
                            $selected += $Projects[$idx]
                        }
                        return $selected
                    }
                }
                'Escape' { return @() }
                'Q' { return @() }
            }
        }
    }
    finally {
        try { [Console]::CursorVisible = $true } catch { }
    }
}

# ============================================================================
# Cleanup
# ============================================================================

function Remove-ProjectArtifacts {
    <#
    .SYNOPSIS
        Remove artifacts from selected projects
    #>
    param([array]$Projects)

    $esc = [char]27

    Write-Host ""
    Write-Host "$esc[1;35mCleaning Project Artifacts$esc[0m"
    Write-Host ""

    foreach ($project in $Projects) {
        Write-Host "$esc[34m$($script:Icons.Arrow)$esc[0m $($project.Name)"

        foreach ($artifact in $project.Artifacts) {
            if (Test-Path $artifact.Path) {
                # Use safe removal with protection checks (returns boolean)
                $success = Remove-SafeItem -Path $artifact.Path -Description $artifact.Name -Recurse

                if ($success) {
                    Write-Host "  $esc[32m$($script:Icons.Success)$esc[0m $($artifact.Name) ($($artifact.SizeHuman))"
                    $script:TotalSizeCleaned += $artifact.SizeKB
                    $script:ItemsCleaned++
                }
                else {
                    Write-Host "  $esc[31m$($script:Icons.Error)$esc[0m $($artifact.Name) - removal failed"
                }
            }
        }
    }
}

# ============================================================================
# Summary
# ============================================================================

function Show-PurgeSummary {
    $esc = [char]27

    Write-Host ""
    Write-Host "$esc[1;35mPurge Complete$esc[0m"
    Write-Host ""

    if ($script:TotalSizeCleaned -gt 0) {
        $sizeGB = [Math]::Round($script:TotalSizeCleaned / 1024 / 1024, 2)
        Write-Host "  Space freed: $esc[32m${sizeGB}GB$esc[0m"
        Write-Host "  Items cleaned: $($script:ItemsCleaned)"
        Write-Host "  Free space now: $(Get-FreeSpace)"
    }
    else {
        Write-Host "  No artifacts to clean."
        Write-Host "  Free space now: $(Get-FreeSpace)"
    }

    Write-Host ""
}

# ============================================================================
# Main Entry Point
# ============================================================================

function Main {
    # Enable debug if requested
    if ($DebugMode) {
        $env:WINMOLE_DEBUG = "1"
        $DebugPreference = "Continue"
    }

    # Show help
    if ($ShowHelp) {
        Show-PurgeHelp
        return
    }

    # Edit paths
    if ($Paths) {
        Edit-SearchPaths
        return
    }

    # Clear screen
    Clear-Host

    $esc = [char]27
    Write-Host ""
    Write-Host "$esc[1;35mPurge Project Artifacts$esc[0m"
    Write-Host ""

    # Get search paths
    $searchPaths = @(Get-SearchPaths)

    if ($null -eq $searchPaths -or $searchPaths.Count -eq 0) {
        Write-Warning "No valid search paths found"
        Write-Host "Run 'winmole purge --paths' to configure search directories"
        return
    }

    Write-Info "Searching in $($searchPaths.Count) directories..."

    # Find projects
    $projects = @(Find-Projects -SearchPaths $searchPaths)

    if ($null -eq $projects -or $projects.Count -eq 0) {
        Write-Host ""
        Write-Host "$esc[32m$($script:Icons.Success)$esc[0m No cleanable artifacts found"
        Write-Host ""
        return
    }

    $totalSize = ($projects | Measure-Object -Property TotalSizeKB -Sum).Sum
    if ($null -eq $totalSize) { $totalSize = 0 }
    $totalSizeHuman = Format-ByteSize -Bytes ($totalSize * 1024)

    Write-Host ""
    Write-Host "Found $esc[33m$($projects.Count)$esc[0m projects with $esc[33m$totalSizeHuman$esc[0m of artifacts"
    Write-Host ""

    # Project selection
    $selected = @(Show-ProjectSelectionMenu -Projects $projects)

    if ($null -eq $selected -or $selected.Count -eq 0) {
        Write-Info "No projects selected"
        return
    }

    # Confirm
    Clear-Host
    Write-Host ""
    $selectedSize = ($selected | Measure-Object -Property TotalSizeKB -Sum).Sum
    if ($null -eq $selectedSize) { $selectedSize = 0 }
    $selectedSizeHuman = Format-ByteSize -Bytes ($selectedSize * 1024)

    Write-Host "$esc[33mThe following will be cleaned ($selectedSizeHuman):$esc[0m"
    Write-Host ""

    foreach ($project in $selected) {
        Write-Host "  $($script:Icons.List) $($project.Name) ($($project.TotalSizeHuman))"
        foreach ($artifact in $project.Artifacts) {
            Write-Host "      $esc[90m$($artifact.Name) - $($artifact.SizeHuman)$esc[0m"
        }
    }

    Write-Host ""
    $confirm = Read-Host "Continue? (y/N)"

    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
        Remove-ProjectArtifacts -Projects $selected
        Show-PurgeSummary
    }
    else {
        Write-Info "Cancelled"
    }
}

# Run main
try {
    Main
}
finally {
    Restore-WinMoleConsoleEncoding
}
