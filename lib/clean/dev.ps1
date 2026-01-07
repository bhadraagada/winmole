# WinMole - Developer Tools Cleanup Module
# Cleans development caches, build artifacts, and package manager caches

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Import core
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$coreDir = Join-Path (Split-Path -Parent $scriptDir) "core"
. "$coreDir\common.ps1"

# ============================================================================
# Node.js / npm / yarn / pnpm
# ============================================================================

function Clear-NodeCache {
    <#
    .SYNOPSIS
        Clean Node.js related caches
    #>
    Start-Section "Node.js Caches"
    
    # npm cache
    $npmCache = "$env:APPDATA\npm-cache"
    if (Test-Path $npmCache) {
        Clear-DirectoryContents -Path $npmCache -Description "npm cache"
    }
    
    # Alternative npm cache location
    $npmCacheAlt = "$env:LOCALAPPDATA\npm-cache"
    if (Test-Path $npmCacheAlt) {
        Clear-DirectoryContents -Path $npmCacheAlt -Description "npm cache (local)"
    }
    
    # Yarn cache
    $yarnCache = "$env:LOCALAPPDATA\Yarn\Cache"
    if (Test-Path $yarnCache) {
        Clear-DirectoryContents -Path $yarnCache -Description "Yarn cache"
    }
    
    # Yarn v2+ cache
    $yarn2Cache = "$env:LOCALAPPDATA\Yarn\Berry\cache"
    if (Test-Path $yarn2Cache) {
        Clear-DirectoryContents -Path $yarn2Cache -Description "Yarn Berry cache"
    }
    
    # pnpm cache
    $pnpmCache = "$env:LOCALAPPDATA\pnpm-cache"
    if (Test-Path $pnpmCache) {
        Clear-DirectoryContents -Path $pnpmCache -Description "pnpm cache"
    }
    
    # pnpm store (be careful - this is where packages are stored)
    $pnpmStore = "$env:LOCALAPPDATA\pnpm\store"
    if (Test-Path $pnpmStore) {
        Write-Info "pnpm store found at $pnpmStore - run 'pnpm store prune' to clean"
    }
    
    Stop-Section
}

# ============================================================================
# Python
# ============================================================================

function Clear-PythonCache {
    <#
    .SYNOPSIS
        Clean Python related caches
    #>
    Start-Section "Python Caches"
    
    # pip cache
    $pipCache = "$env:LOCALAPPDATA\pip\cache"
    if (Test-Path $pipCache) {
        Clear-DirectoryContents -Path $pipCache -Description "pip cache"
    }
    
    # Alternative pip cache
    $pipCacheAlt = "$env:APPDATA\pip\cache"
    if (Test-Path $pipCacheAlt) {
        Clear-DirectoryContents -Path $pipCacheAlt -Description "pip cache (roaming)"
    }
    
    # pipx cache
    $pipxCache = "$env:LOCALAPPDATA\pipx"
    if (Test-Path "$pipxCache\.cache") {
        Clear-DirectoryContents -Path "$pipxCache\.cache" -Description "pipx cache"
    }
    
    # Poetry cache
    $poetryCache = "$env:LOCALAPPDATA\pypoetry\Cache"
    if (Test-Path $poetryCache) {
        Clear-DirectoryContents -Path $poetryCache -Description "Poetry cache"
    }
    
    # Conda pkgs (be careful - not cleaning everything)
    $condaPkgs = "$env:USERPROFILE\.conda\pkgs"
    if (Test-Path $condaPkgs) {
        # Only clean .tar.bz2 and .conda files (compressed packages)
        $compressedPkgs = Get-ChildItem -Path $condaPkgs -Filter "*.tar.bz2" -ErrorAction SilentlyContinue
        $compressedPkgs += Get-ChildItem -Path $condaPkgs -Filter "*.conda" -ErrorAction SilentlyContinue
        if ($compressedPkgs) {
            Remove-SafeItems -Paths ($compressedPkgs | ForEach-Object { $_.FullName }) -Description "Conda package archives"
        }
    }
    
    # __pycache__ in user directories (dangerous to scan everything, so just common locations)
    $pythonDirs = @(
        "$env:USERPROFILE\Documents"
        "$env:USERPROFILE\Projects"
        "$env:USERPROFILE\repos"
        "$env:USERPROFILE\code"
    )
    
    foreach ($dir in $pythonDirs) {
        if (Test-Path $dir) {
            $pycacheDirs = Get-ChildItem -Path $dir -Directory -Recurse -Filter "__pycache__" -ErrorAction SilentlyContinue | 
                           Select-Object -First 100  # Limit to prevent long scans
            if ($pycacheDirs) {
                Remove-SafeItems -Paths ($pycacheDirs | ForEach-Object { $_.FullName }) -Description "__pycache__ dirs"
            }
        }
    }
    
    Stop-Section
}

# ============================================================================
# .NET / NuGet
# ============================================================================

function Clear-DotNetCache {
    <#
    .SYNOPSIS
        Clean .NET related caches
    #>
    Start-Section ".NET Caches"
    
    # NuGet HTTP cache
    $nugetHttpCache = "$env:LOCALAPPDATA\NuGet\v3-cache"
    if (Test-Path $nugetHttpCache) {
        Clear-DirectoryContents -Path $nugetHttpCache -Description "NuGet HTTP cache"
    }
    
    # NuGet plugins cache
    $nugetPlugins = "$env:LOCALAPPDATA\NuGet\plugins-cache"
    if (Test-Path $nugetPlugins) {
        Clear-DirectoryContents -Path $nugetPlugins -Description "NuGet plugins cache"
    }
    
    # .NET SDK temp
    $dotnetTemp = "$env:TEMP\NuGetScratch"
    if (Test-Path $dotnetTemp) {
        Clear-DirectoryContents -Path $dotnetTemp -Description "NuGet scratch"
    }
    
    # MSBuild temp files
    $msbuildTemp = "$env:LOCALAPPDATA\Microsoft\MSBuild"
    if (Test-Path $msbuildTemp) {
        # Clean temp folders only
        $tempDirs = Get-ChildItem -Path $msbuildTemp -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match "^Tmp" }
        foreach ($dir in $tempDirs) {
            Clear-DirectoryContents -Path $dir.FullName -Description "MSBuild temp"
        }
    }
    
    # Note: Not cleaning ~/.nuget/packages by default as it's the package cache
    $nugetPackages = "$env:USERPROFILE\.nuget\packages"
    if (Test-Path $nugetPackages) {
        Write-Info "NuGet packages at $nugetPackages - run 'dotnet nuget locals all --clear' to clean"
    }
    
    Stop-Section
}

# ============================================================================
# Rust / Cargo
# ============================================================================

function Clear-RustCache {
    <#
    .SYNOPSIS
        Clean Rust/Cargo caches
    #>
    Start-Section "Rust Caches"
    
    # Cargo registry cache (index only, not the actual crates)
    $cargoRegistry = "$env:USERPROFILE\.cargo\registry\cache"
    if (Test-Path $cargoRegistry) {
        # Only clean old cached .crate files
        Remove-OldFiles -Path $cargoRegistry -DaysOld 60 -Filter "*.crate" -Description "Cargo crate cache"
    }
    
    # Cargo git checkouts (temporary)
    $cargoGit = "$env:USERPROFILE\.cargo\git\checkouts"
    if (Test-Path $cargoGit) {
        Write-Info "Cargo git checkouts found - run 'cargo cache --autoclean' if cargo-cache is installed"
    }
    
    # rustup downloads
    $rustupDownloads = "$env:USERPROFILE\.rustup\downloads"
    if (Test-Path $rustupDownloads) {
        Clear-DirectoryContents -Path $rustupDownloads -Description "Rustup downloads"
    }
    
    # rustup tmp
    $rustupTmp = "$env:USERPROFILE\.rustup\tmp"
    if (Test-Path $rustupTmp) {
        Clear-DirectoryContents -Path $rustupTmp -Description "Rustup temp"
    }
    
    Stop-Section
}

# ============================================================================
# Go
# ============================================================================

function Clear-GoCache {
    <#
    .SYNOPSIS
        Clean Go caches
    #>
    Start-Section "Go Caches"
    
    # Go build cache
    $goBuildCache = "$env:LOCALAPPDATA\go-build"
    if (Test-Path $goBuildCache) {
        Clear-DirectoryContents -Path $goBuildCache -Description "Go build cache"
    }
    
    # Go mod cache (be careful)
    $goModCache = "$env:GOPATH\pkg\mod\cache"
    if (-not $env:GOPATH) {
        $goModCache = "$env:USERPROFILE\go\pkg\mod\cache"
    }
    if (Test-Path $goModCache) {
        # Only clean download cache
        $downloadCache = Join-Path $goModCache "download"
        if (Test-Path $downloadCache) {
            Write-Info "Go mod cache found - run 'go clean -modcache' to clean completely"
        }
    }
    
    Stop-Section
}

# ============================================================================
# Java / Maven / Gradle
# ============================================================================

function Clear-JavaCache {
    <#
    .SYNOPSIS
        Clean Java related caches
    #>
    Start-Section "Java Caches"
    
    # Note: NOT cleaning .m2/repository as it contains all Maven dependencies
    Write-Info "Maven repo at ~/.m2/repository - clean manually if needed"
    
    # Gradle wrapper distributions (old versions)
    $gradleWrapper = "$env:USERPROFILE\.gradle\wrapper\dists"
    if (Test-Path $gradleWrapper) {
        # Keep only the 3 most recent versions
        $gradleDists = Get-ChildItem -Path $gradleWrapper -Directory -ErrorAction SilentlyContinue |
                       Sort-Object LastWriteTime -Descending |
                       Select-Object -Skip 3
        if ($gradleDists) {
            Remove-SafeItems -Paths ($gradleDists | ForEach-Object { $_.FullName }) -Description "Old Gradle distributions"
        }
    }
    
    # Gradle build cache
    $gradleBuildCache = "$env:USERPROFILE\.gradle\caches\build-cache-1"
    if (Test-Path $gradleBuildCache) {
        Clear-DirectoryContents -Path $gradleBuildCache -Description "Gradle build cache"
    }
    
    # Gradle daemon logs
    $gradleDaemon = "$env:USERPROFILE\.gradle\daemon"
    if (Test-Path $gradleDaemon) {
        Remove-OldFiles -Path $gradleDaemon -DaysOld 7 -Filter "*.log" -Description "Gradle daemon logs"
    }
    
    Stop-Section
}

# ============================================================================
# Docker
# ============================================================================

function Clear-DockerCache {
    <#
    .SYNOPSIS
        Clean Docker caches and build files
    #>
    Start-Section "Docker"
    
    # Check if Docker is installed and running
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $docker) {
        Write-Debug "Docker not installed"
        Stop-Section
        return
    }
    
    # Check if Docker daemon is running
    $dockerRunning = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Docker daemon is not running"
        Stop-Section
        return
    }
    
    if (Test-DryRunMode) {
        Write-DryRun "Docker system prune would clean unused data"
    }
    else {
        Write-Info "Run 'docker system prune -a' to clean unused images and containers"
        Write-Info "Run 'docker builder prune' to clean build cache"
    }
    
    Stop-Section
}

# ============================================================================
# IDE Caches
# ============================================================================

function Clear-IDECaches {
    <#
    .SYNOPSIS
        Clean IDE and editor caches
    #>
    Start-Section "IDE Caches"
    
    # Visual Studio
    $vsCache = "$env:LOCALAPPDATA\Microsoft\VisualStudio"
    if (Test-Path $vsCache) {
        $vsCacheDirs = Get-ChildItem -Path $vsCache -Directory -ErrorAction SilentlyContinue |
                       ForEach-Object { 
                           $componentCache = Join-Path $_.FullName "ComponentModelCache"
                           if (Test-Path $componentCache) { $componentCache }
                       }
        foreach ($dir in $vsCacheDirs) {
            Clear-DirectoryContents -Path $dir -Description "Visual Studio component cache"
        }
    }
    
    # JetBrains IDEs
    $jetbrainsConfigs = @(
        "$env:APPDATA\JetBrains"
        "$env:LOCALAPPDATA\JetBrains"
    )
    foreach ($config in $jetbrainsConfigs) {
        if (Test-Path $config) {
            $logDirs = Get-ChildItem -Path $config -Directory -Recurse -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -eq "log" }
            foreach ($dir in $logDirs) {
                Remove-OldFiles -Path $dir.FullName -DaysOld 7 -Description "JetBrains logs"
            }
        }
    }
    
    # VS Code (already handled in user.ps1 but adding workspace storage here)
    $vscodeStorage = "$env:APPDATA\Code\User\workspaceStorage"
    if (Test-Path $vscodeStorage) {
        # Clean workspace storage older than 30 days
        $oldWorkspaces = Get-ChildItem -Path $vscodeStorage -Directory -ErrorAction SilentlyContinue |
                         Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }
        if ($oldWorkspaces) {
            Remove-SafeItems -Paths ($oldWorkspaces | ForEach-Object { $_.FullName }) -Description "VS Code old workspaces"
        }
    }
    
    # Sublime Text cache
    $sublimeCache = "$env:APPDATA\Sublime Text\Cache"
    if (Test-Path $sublimeCache) {
        Clear-DirectoryContents -Path $sublimeCache -Description "Sublime Text cache"
    }
    
    Stop-Section
}

# ============================================================================
# Git
# ============================================================================

function Clear-GitCache {
    <#
    .SYNOPSIS
        Clean Git related caches
    #>
    Start-Section "Git"
    
    # Git credential cache (not touching - security sensitive)
    
    # Git pack files optimization suggestion
    Write-Info "Run 'git gc --aggressive' in repositories to optimize Git objects"
    
    # GitHub CLI cache
    $ghCache = "$env:APPDATA\GitHub CLI"
    if (Test-Path $ghCache) {
        Remove-OldFiles -Path $ghCache -DaysOld 30 -Filter "*.json" -Description "GitHub CLI cache"
    }
    
    Stop-Section
}

# ============================================================================
# Main Developer Cleanup
# ============================================================================

function Invoke-DevCleanup {
    <#
    .SYNOPSIS
        Run all developer tools cleanup
    #>
    param(
        [switch]$Node,
        [switch]$Python,
        [switch]$DotNet,
        [switch]$Rust,
        [switch]$Go,
        [switch]$Java,
        [switch]$Docker,
        [switch]$IDE,
        [switch]$Git,
        [switch]$All
    )
    
    Reset-CleanupStats
    
    if ($All -or $Node) { Clear-NodeCache }
    if ($All -or $Python) { Clear-PythonCache }
    if ($All -or $DotNet) { Clear-DotNetCache }
    if ($All -or $Rust) { Clear-RustCache }
    if ($All -or $Go) { Clear-GoCache }
    if ($All -or $Java) { Clear-JavaCache }
    if ($All -or $Docker) { Clear-DockerCache }
    if ($All -or $IDE) { Clear-IDECaches }
    if ($All -or $Git) { Clear-GitCache }
    
    $stats = Get-CleanupStats
    Show-Summary -SizeBytes ($stats.TotalSizeKB * 1024) -ItemCount $stats.TotalItems -Action "Cleaned"
}

# ============================================================================
# Exports (functions are available via dot-sourcing)
# ============================================================================
# Functions: Clear-NodeCache, Clear-PythonCache, Invoke-DevCleanup, etc.
