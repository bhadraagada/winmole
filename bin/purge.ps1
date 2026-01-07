# WinMole - Purge Command
# Clean development project artifacts (node_modules, target, build, etc.)

#Requires -Version 5.1
param(
    [string]$Path,
    [switch]$DryRun,
    [switch]$Aggressive,
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
# Project Artifact Definitions
# ============================================================================

$script:ProjectArtifacts = @{
    # Node.js
    "node_modules" = @{
        Description = "Node.js dependencies"
        Indicator   = @("package.json")
        Size        = "large"
    }
    ".npm" = @{
        Description = "npm cache"
        Indicator   = @()
        Size        = "medium"
    }
    
    # Python
    "__pycache__" = @{
        Description = "Python bytecode cache"
        Indicator   = @("*.py")
        Size        = "small"
    }
    ".venv" = @{
        Description = "Python virtual environment"
        Indicator   = @("requirements.txt", "pyproject.toml")
        Size        = "large"
    }
    "venv" = @{
        Description = "Python virtual environment"
        Indicator   = @("requirements.txt", "pyproject.toml")
        Size        = "large"
    }
    ".tox" = @{
        Description = "Tox test environments"
        Indicator   = @("tox.ini")
        Size        = "large"
    }
    "*.egg-info" = @{
        Description = "Python egg info"
        Indicator   = @("setup.py")
        Size        = "small"
    }
    ".pytest_cache" = @{
        Description = "Pytest cache"
        Indicator   = @()
        Size        = "small"
    }
    ".mypy_cache" = @{
        Description = "MyPy cache"
        Indicator   = @()
        Size        = "small"
    }
    
    # Rust
    "target" = @{
        Description = "Rust/Cargo build output"
        Indicator   = @("Cargo.toml")
        Size        = "large"
    }
    
    # Go
    "vendor" = @{
        Description = "Go vendor directory"
        Indicator   = @("go.mod")
        Size        = "large"
    }
    
    # .NET
    "bin" = @{
        Description = ".NET build output"
        Indicator   = @("*.csproj", "*.fsproj", "*.vbproj")
        Size        = "medium"
    }
    "obj" = @{
        Description = ".NET intermediate output"
        Indicator   = @("*.csproj", "*.fsproj", "*.vbproj")
        Size        = "medium"
    }
    "packages" = @{
        Description = "NuGet packages (solution level)"
        Indicator   = @("*.sln")
        Size        = "large"
    }
    
    # Java
    "build" = @{
        Description = "Build output"
        Indicator   = @("build.gradle", "pom.xml", "package.json")
        Size        = "large"
    }
    ".gradle" = @{
        Description = "Gradle cache"
        Indicator   = @("build.gradle")
        Size        = "large"
    }
    
    # General
    "dist" = @{
        Description = "Distribution output"
        Indicator   = @("package.json", "setup.py", "webpack.config.js")
        Size        = "medium"
    }
    ".cache" = @{
        Description = "Generic cache"
        Indicator   = @()
        Size        = "medium"
    }
    "coverage" = @{
        Description = "Code coverage reports"
        Indicator   = @()
        Size        = "medium"
    }
    ".nyc_output" = @{
        Description = "NYC coverage output"
        Indicator   = @()
        Size        = "small"
    }
    
    # IDE/Editor
    ".idea" = @{
        Description = "JetBrains IDE settings"
        Indicator   = @()
        Size        = "small"
        Aggressive  = $true
    }
    ".vs" = @{
        Description = "Visual Studio settings"
        Indicator   = @()
        Size        = "medium"
        Aggressive  = $true
    }
}

# ============================================================================
# Help
# ============================================================================

function Show-PurgeHelp {
    $cyan = $script:Colors.Cyan
    $gray = $script:Colors.Gray
    $nc = $script:Colors.NC
    
    Write-Host ""
    Write-Host "  ${cyan}WinMole Purge${nc} - Clean project build artifacts"
    Write-Host ""
    Write-Host "  ${gray}USAGE:${nc}"
    Write-Host "    winmole purge [path] [options]"
    Write-Host ""
    Write-Host "  ${gray}OPTIONS:${nc}"
    Write-Host "    -Path           Directory to scan (default: current directory)"
    Write-Host "    -DryRun         Preview changes without deleting"
    Write-Host "    -Aggressive     Also clean IDE settings (.idea, .vs)"
    Write-Host "    -Help           Show this help"
    Write-Host ""
    Write-Host "  ${gray}ARTIFACTS CLEANED:${nc}"
    Write-Host "    node_modules    Node.js dependencies"
    Write-Host "    target          Rust/Cargo build output"
    Write-Host "    bin/obj         .NET build output"
    Write-Host "    build/dist      Build distributions"
    Write-Host "    __pycache__     Python bytecode"
    Write-Host "    .venv/venv      Python virtual environments"
    Write-Host "    .gradle         Gradle cache"
    Write-Host "    coverage        Code coverage reports"
    Write-Host ""
    Write-Host "  ${gray}EXAMPLES:${nc}"
    Write-Host "    winmole purge                    # Scan current directory"
    Write-Host "    winmole purge C:\Projects        # Scan specific directory"
    Write-Host "    winmole purge -DryRun            # Preview only"
    Write-Host "    winmole purge -Aggressive        # Include IDE settings"
    Write-Host ""
}

# ============================================================================
# Scanning
# ============================================================================

function Find-ProjectArtifacts {
    <#
    .SYNOPSIS
        Find cleanable project artifacts in a directory
    #>
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,
        
        [switch]$IncludeAggressive
    )
    
    $artifacts = [System.Collections.ArrayList]::new()
    $scanned = 0
    
    Write-Host ""
    Start-Spinner "Scanning for project artifacts..."
    
    # Get all directories (limited depth to avoid too long scans)
    $allDirs = Get-ChildItem -Path $BasePath -Directory -Recurse -Depth 10 -ErrorAction SilentlyContinue
    $total = $allDirs.Count
    
    foreach ($dir in $allDirs) {
        $scanned++
        
        if ($scanned % 100 -eq 0) {
            Update-Spinner "Scanning... ($scanned/$total directories)"
        }
        
        $dirName = $dir.Name
        
        # Check if this is a known artifact directory
        foreach ($artifactName in $script:ProjectArtifacts.Keys) {
            $artifact = $script:ProjectArtifacts[$artifactName]
            
            # Skip aggressive items unless requested
            $isAggressive = $artifact.ContainsKey('Aggressive') -and $artifact.Aggressive
            if ($isAggressive -and -not $IncludeAggressive) {
                continue
            }
            
            # Check for exact match or pattern match
            $isMatch = $false
            if ($artifactName -like '*`**') {
                # Pattern match (e.g., *.egg-info)
                if ($dirName -like $artifactName) {
                    $isMatch = $true
                }
            }
            else {
                # Exact match
                if ($dirName -eq $artifactName) {
                    $isMatch = $true
                }
            }
            
            if ($isMatch) {
                # Check for indicator files in parent directory
                $parentDir = $dir.Parent.FullName
                $hasIndicator = $artifact.Indicator.Count -eq 0  # No indicator = always match
                
                foreach ($indicator in $artifact.Indicator) {
                    if (Test-Path (Join-Path $parentDir $indicator)) {
                        $hasIndicator = $true
                        break
                    }
                }
                
                if ($hasIndicator) {
                    $size = Get-PathSize -Path $dir.FullName
                    [void]$artifacts.Add(@{
                        Path        = $dir.FullName
                        Name        = $artifactName
                        Description = $artifact.Description
                        Size        = $size
                        Parent      = $parentDir
                    })
                }
            }
        }
    }
    
    Stop-Spinner
    
    return $artifacts | Sort-Object Size -Descending
}

# ============================================================================
# Interactive Selection
# ============================================================================

function Show-ArtifactSummary {
    param(
        [array]$Artifacts
    )
    
    $cyan = $script:Colors.Cyan
    $gray = $script:Colors.Gray
    $green = $script:Colors.Green
    $nc = $script:Colors.NC
    
    # Group by type
    $grouped = $Artifacts | Group-Object Name
    
    Write-Host ""
    Write-Host "  ${cyan}Found Artifacts:${nc}"
    Write-Host ""
    
    foreach ($group in $grouped | Sort-Object { ($_.Group | Measure-Object Size -Sum).Sum } -Descending) {
        $totalSize = ($group.Group | Measure-Object Size -Sum).Sum
        $count = $group.Count
        $name = $group.Name
        $desc = $script:ProjectArtifacts[$name].Description
        
        Write-Host "  ${green}$(Format-ByteSize $totalSize)${nc}  $name ${gray}($count locations) - $desc${nc}"
    }
    
    $totalAll = ($Artifacts | Measure-Object Size -Sum).Sum
    Write-Host ""
    Write-Host "  ${cyan}Total: $(Format-ByteSize $totalAll) in $($Artifacts.Count) directories${nc}"
    Write-Host ""
}

function Select-ArtifactsToClean {
    param(
        [array]$Artifacts
    )
    
    # Group by artifact type
    $grouped = $Artifacts | Group-Object Name | Sort-Object { ($_.Group | Measure-Object Size -Sum).Sum } -Descending
    
    $options = $grouped | ForEach-Object {
        $totalSize = ($_.Group | Measure-Object Size -Sum).Sum
        @{
            Name        = "$($_.Name) ($(Format-ByteSize $totalSize), $($_.Count) dirs)"
            Description = $script:ProjectArtifacts[$_.Name].Description
            ArtifactName = $_.Name
            Artifacts   = $_.Group
        }
    }
    
    $selected = Show-SelectionList -Title "Select artifacts to clean" -Items $options -MultiSelect
    
    # Flatten selection
    $toClean = [System.Collections.ArrayList]::new()
    foreach ($item in $selected) {
        foreach ($artifact in $item.Artifacts) {
            [void]$toClean.Add($artifact)
        }
    }
    
    return $toClean
}

# ============================================================================
# Main
# ============================================================================

function Main {
    Initialize-WinMole
    
    if ($Help) {
        Show-PurgeHelp
        return
    }
    
    if ($DryRun -or $env:WINMOLE_DRY_RUN -eq "1") {
        Set-DryRunMode -Enabled $true
        Write-Host ""
        Write-Warning "DRY RUN MODE - No files will be deleted"
    }
    
    # Determine search path
    $searchPath = if ($Path) { $Path } else { Get-Location }
    
    if (-not (Test-Path $searchPath)) {
        Write-Error "Path not found: $searchPath"
        return
    }
    
    $searchPath = Resolve-Path $searchPath
    
    Write-Host ""
    Write-Host "  Scanning: $searchPath"
    
    # Find artifacts
    $artifacts = @(Find-ProjectArtifacts -BasePath $searchPath -IncludeAggressive:$Aggressive)
    
    if ($artifacts.Count -eq 0) {
        Write-Host ""
        Write-Success "No cleanable artifacts found"
        Write-Host ""
        return
    }
    
    # Show summary
    Show-ArtifactSummary -Artifacts $artifacts
    
    # Ask what to clean
    $toClean = Select-ArtifactsToClean -Artifacts $artifacts
    
    if ($toClean.Count -eq 0) {
        Write-Host ""
        return
    }
    
    # Confirm
    $totalSize = ($toClean | Measure-Object Size -Sum).Sum
    Write-Host ""
    if (-not (Read-Confirmation -Prompt "Clean $($toClean.Count) directories ($(Format-ByteSize $totalSize))?" -Default $true)) {
        Write-Host ""
        return
    }
    
    # Clean
    Reset-CleanupStats
    Write-Host ""
    
    $cleaned = 0
    foreach ($artifact in $toClean) {
        $cleaned++
        Write-Progress -Current $cleaned -Total $toClean.Count -Message "Cleaning $($artifact.Name)..."
        
        Remove-SafeItem -Path $artifact.Path -Description "$($artifact.Name) ($($artifact.Parent | Split-Path -Leaf))"
    }
    
    Complete-Progress
    
    # Summary
    $stats = Get-CleanupStats
    Show-Summary -SizeBytes ($stats.TotalSizeKB * 1024) -ItemCount $stats.TotalItems -Action $(if (Test-DryRunMode) { "Would clean" } else { "Cleaned" })
}

# Run
try {
    Main
}
finally {
    Clear-TempFiles
}
