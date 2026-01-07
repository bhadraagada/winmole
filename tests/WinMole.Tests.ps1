#!/usr/bin/env pwsh
# WinMole Pester Tests
# Run with: Invoke-Pester -Path .\tests\

#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    # Get the root directory
    $script:ROOT = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $script:LIB_DIR = Join-Path $script:ROOT "lib"
    $script:BIN_DIR = Join-Path $script:ROOT "bin"
    
    # Import core modules
    . "$script:LIB_DIR\core\base.ps1"
    . "$script:LIB_DIR\core\log.ps1"
    . "$script:LIB_DIR\core\file_ops.ps1"
    
    # Create temp directory for tests
    $script:TEST_TEMP = Join-Path $env:TEMP "WinMole_Tests_$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TEST_TEMP -Force | Out-Null
}

AfterAll {
    # Cleanup temp directory
    if (Test-Path $script:TEST_TEMP) {
        Remove-Item -Path $script:TEST_TEMP -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# Core Module Tests
# ============================================================================

Describe "Core Module - base.ps1" {
    
    Context "Format-ByteSize" {
        It "formats bytes correctly" {
            Format-ByteSize 512 | Should -Be "512 B"
        }
        
        It "formats kilobytes correctly" {
            Format-ByteSize 1024 | Should -Be "1.0 KB"
            Format-ByteSize 2048 | Should -Be "2.0 KB"
        }
        
        It "formats megabytes correctly" {
            Format-ByteSize (1024 * 1024) | Should -Be "1.0 MB"
            Format-ByteSize (1024 * 1024 * 5.5) | Should -Be "5.5 MB"
        }
        
        It "formats gigabytes correctly" {
            Format-ByteSize (1024 * 1024 * 1024) | Should -Be "1.0 GB"
        }
        
        It "handles zero" {
            Format-ByteSize 0 | Should -Be "0 B"
        }
    }
    
    Context "Test-ProtectedPath" {
        It "protects Windows directory" {
            Test-ProtectedPath "C:\Windows" | Should -Be $true
            Test-ProtectedPath "C:\Windows\System32" | Should -Be $true
        }
        
        It "protects Program Files" {
            Test-ProtectedPath "C:\Program Files" | Should -Be $true
            Test-ProtectedPath "C:\Program Files (x86)" | Should -Be $true
        }
        
        It "allows temp directories" {
            Test-ProtectedPath $env:TEMP | Should -Be $false
        }
        
        It "allows user AppData" {
            $testPath = Join-Path $env:LOCALAPPDATA "SomeApp\Cache"
            Test-ProtectedPath $testPath | Should -Be $false
        }
    }
    
    Context "Test-IsAdmin" {
        It "returns a boolean" {
            Test-IsAdmin | Should -BeOfType [bool]
        }
    }
    
    Context "Get-WindowsVersion" {
        It "returns version info" {
            $info = Get-WindowsVersion
            $info | Should -Not -BeNullOrEmpty
            $info.Name | Should -Not -BeNullOrEmpty
            $info.Build | Should -Not -BeNullOrEmpty
        }
    }
}

# ============================================================================
# File Operations Tests
# ============================================================================

Describe "File Operations - file_ops.ps1" {
    
    BeforeEach {
        # Create test files and directories
        $script:testDir = Join-Path $script:TEST_TEMP "fileops_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
    }
    
    AfterEach {
        if (Test-Path $script:testDir) {
            Remove-Item -Path $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Remove-SafeItem" {
        It "removes a regular file" {
            $testFile = Join-Path $script:testDir "test.txt"
            Set-Content -Path $testFile -Value "test"
            
            Remove-SafeItem -Path $testFile
            
            Test-Path $testFile | Should -Be $false
        }
        
        It "removes an empty directory" {
            $testSubDir = Join-Path $script:testDir "subdir"
            New-Item -ItemType Directory -Path $testSubDir -Force | Out-Null
            
            Remove-SafeItem -Path $testSubDir
            
            Test-Path $testSubDir | Should -Be $false
        }
        
        It "removes a directory with contents recursively" {
            $testSubDir = Join-Path $script:testDir "subdir"
            New-Item -ItemType Directory -Path $testSubDir -Force | Out-Null
            Set-Content -Path (Join-Path $testSubDir "file.txt") -Value "test"
            
            Remove-SafeItem -Path $testSubDir -Recurse
            
            Test-Path $testSubDir | Should -Be $false
        }
        
        It "skips protected paths" {
            # This should not actually try to delete Windows directory
            # Remove-SafeItem internally checks and returns $false for protected paths
            $result = Remove-SafeItem -Path "C:\Windows"
            $result | Should -Be $false
        }
        
        It "handles non-existent paths gracefully" {
            $nonExistent = Join-Path $script:testDir "nonexistent"
            { Remove-SafeItem -Path $nonExistent } | Should -Not -Throw
        }
    }
    
    Context "Remove-OldFiles" {
        It "removes files older than specified days" {
            # Create old file (modify timestamp)
            $oldFile = Join-Path $script:testDir "old.txt"
            Set-Content -Path $oldFile -Value "old"
            (Get-Item $oldFile).LastWriteTime = (Get-Date).AddDays(-10)
            
            # Create new file
            $newFile = Join-Path $script:testDir "new.txt"
            Set-Content -Path $newFile -Value "new"
            
            Remove-OldFiles -Path $script:testDir -Days 5 -Pattern "*.txt"
            
            Test-Path $oldFile | Should -Be $false
            Test-Path $newFile | Should -Be $true
        }
    }
    
    Context "Remove-EmptyDirectories" {
        It "removes empty directories" {
            $emptyDir = Join-Path $script:testDir "empty"
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
            
            Remove-EmptyDirectories -Path $script:testDir
            
            Test-Path $emptyDir | Should -Be $false
        }
        
        It "preserves directories with content" {
            $contentDir = Join-Path $script:testDir "withcontent"
            New-Item -ItemType Directory -Path $contentDir -Force | Out-Null
            Set-Content -Path (Join-Path $contentDir "file.txt") -Value "test"
            
            Remove-EmptyDirectories -Path $script:testDir
            
            Test-Path $contentDir | Should -Be $true
        }
    }
}

# ============================================================================
# Script Validation Tests
# ============================================================================

Describe "Script Validation" {
    
    Context "PowerShell Scripts Syntax" {
        
        BeforeDiscovery {
            $rootDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
            $script:AllScripts = Get-ChildItem -Path $rootDir -Include "*.ps1" -Recurse
        }
        
        It "validates: <_.Name>" -ForEach $AllScripts {
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $_.FullName,
                [ref]$null,
                [ref]$parseErrors
            )
            $parseErrors.Count | Should -Be 0
        }
    }
}

# ============================================================================
# Command Tests
# ============================================================================

Describe "Commands" {
    
    Context "winmole.ps1" {
        It "exists at root" {
            Test-Path (Join-Path $script:ROOT "winmole.ps1") | Should -Be $true
        }
        
        It "shows version with -Version flag" {
            $output = & (Join-Path $script:ROOT "winmole.ps1") -Version 6>&1 | Out-String
            $output | Should -Match "WinMole"
        }
        
        It "shows help with -ShowHelp flag" {
            $output = & (Join-Path $script:ROOT "winmole.ps1") -ShowHelp 6>&1 | Out-String
            $output | Should -Match "COMMANDS"
        }
    }
    
    Context "bin/clean.ps1" {
        It "exists" {
            Test-Path (Join-Path $script:BIN_DIR "clean.ps1") | Should -Be $true
        }
        
        It "shows help with -Help flag" {
            $output = & (Join-Path $script:BIN_DIR "clean.ps1") -Help 6>&1 | Out-String
            $output | Should -Match "USAGE"
        }
    }
    
    Context "bin/purge.ps1" {
        It "exists" {
            Test-Path (Join-Path $script:BIN_DIR "purge.ps1") | Should -Be $true
        }
    }
    
    Context "bin/optimize.ps1" {
        It "exists" {
            Test-Path (Join-Path $script:BIN_DIR "optimize.ps1") | Should -Be $true
        }
    }
    
    Context "bin/uninstall.ps1" {
        It "exists" {
            Test-Path (Join-Path $script:BIN_DIR "uninstall.ps1") | Should -Be $true
        }
    }
}

# ============================================================================
# Integration Tests
# ============================================================================

Describe "Integration Tests" -Tag "Integration" {
    
    Context "Dry Run Mode" {
        It "clean respects dry run" {
            $env:WINMOLE_DRY_RUN = "1"
            try {
                # This should not actually delete anything
                $output = & (Join-Path $script:BIN_DIR "clean.ps1") -User -DryRun 2>&1
                # Should complete without error
                $LASTEXITCODE | Should -BeIn @(0, $null)
            }
            finally {
                Remove-Item Env:WINMOLE_DRY_RUN -ErrorAction SilentlyContinue
            }
        }
    }
}
