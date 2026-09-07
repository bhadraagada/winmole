#!/usr/bin/env pwsh
# WinMole - core library tests (base.ps1, file_ops.ps1, log.ps1)
# Run with: Invoke-Pester -Path .\tests\

#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    # Pester 5 runs each test file in its own scope, so this setup is repeated
    # per suite rather than shared. It cannot be factored into a helper function:
    # dot-sourcing the modules inside a function would scope those definitions to
    # the function and lose them on return.
    $script:ROOT = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $script:LIB_DIR = Join-Path $script:ROOT "lib"
    $script:BIN_DIR = Join-Path $script:ROOT "bin"

    . "$script:LIB_DIR\core\base.ps1"
    . "$script:LIB_DIR\core\log.ps1"
    . "$script:LIB_DIR\core\file_ops.ps1"

    $script:TEST_TEMP = Join-Path $env:TEMP "WinMole_Tests_Core_$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TEST_TEMP -Force | Out-Null
}

AfterAll {
    if ($script:TEST_TEMP -and (Test-Path $script:TEST_TEMP)) {
        Remove-Item -Path $script:TEST_TEMP -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# base.ps1
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

    Context "Test-Whitelisted" {
        It "honors the documented and legacy whitelist file names" {
            $originalWhitelistFile = $script:Config.WhitelistFile
            $script:Config.WhitelistFile = Join-Path $script:TEST_TEMP "whitelist"
            $documentedPath = Join-Path $script:TEST_TEMP "documented-cache"
            $legacyPath = Join-Path $script:TEST_TEMP "legacy-cache"

            try {
                Set-Content -LiteralPath $script:Config.WhitelistFile -Value $documentedPath
                Set-Content -LiteralPath "$($script:Config.WhitelistFile).txt" -Value $legacyPath

                Test-Whitelisted -Path $documentedPath | Should -Be $true
                Test-Whitelisted -Path $legacyPath | Should -Be $true
            }
            finally {
                $script:Config.WhitelistFile = $originalWhitelistFile
            }
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
# file_ops.ps1
# ============================================================================

Describe "File Operations - file_ops.ps1" {

    BeforeEach {
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
            # Remove-SafeItem checks internally and returns $false for protected
            # paths, so this never attempts to delete the Windows directory.
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
            $oldFile = Join-Path $script:testDir "old.txt"
            Set-Content -Path $oldFile -Value "old"
            (Get-Item $oldFile).LastWriteTime = (Get-Date).AddDays(-10)

            $newFile = Join-Path $script:testDir "new.txt"
            Set-Content -Path $newFile -Value "new"

            Remove-OldFiles -Path $script:testDir -Days 5 -Pattern "*.txt"

            Test-Path $oldFile | Should -Be $false
            Test-Path $newFile | Should -Be $true
        }
    }

    Context "Remove-EmptyDirectories" {
        It "handles directory names containing wildcard characters" {
            $emptyDir = Join-Path $script:testDir "unfinished [name"
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null

            { Remove-EmptyDirectories -Path $script:testDir } | Should -Not -Throw

            Test-Path -LiteralPath $emptyDir | Should -Be $false
        }

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
# log.ps1 - progress bar, regression tests for #18
# ============================================================================

Describe "Progress Bar - log.ps1" {

    Context "cmdlet shadowing" {
        It "does not shadow the built-in Write-Progress cmdlet" {
            # A function named Write-Progress outranks the cmdlet for every script
            # that dot-sources log.ps1, silently swallowing -Activity/-Status/
            # -PercentComplete into $args and freezing the bar at 0%.
            (Get-Command Write-Progress).CommandType | Should -Be 'Cmdlet'
        }

        It "exposes the helper under a non-colliding name" {
            (Get-Command Write-ProgressBar).CommandType | Should -Be 'Function'
        }
    }

    Context "Write-ProgressBar" {
        It "renders a percentage that tracks Current over Total" {
            $rendered = Write-ProgressBar -Current 7 -Total 10 -Message "x" 6>&1 | Out-String
            $rendered | Should -Match '70%'
        }

        It "renders 0% when Total is zero rather than dividing by zero" {
            { Write-ProgressBar -Current 0 -Total 0 6>&1 | Out-Null } | Should -Not -Throw
            $rendered = Write-ProgressBar -Current 0 -Total 0 6>&1 | Out-String
            $rendered | Should -Match '0%'
        }

        It "does not throw when Current exceeds Total" {
            # Clamping matters because '=' * -1 throws, and callers discover
            # additional items partway through a scan.
            { Write-ProgressBar -Current 15 -Total 10 6>&1 | Out-Null } | Should -Not -Throw
        }
    }

    Context "Complete-Progress" {
        It "clears the line without emitting literal plus signs" {
            # The body concatenates inside parentheses; without them PowerShell
            # parses it in argument mode and prints "+" between each part.
            $rendered = Complete-Progress 6>&1 | Out-String
            $rendered | Should -Not -Match '\+'
        }
    }
}
