# WinMole - Cleanup Module Tests
# Pester tests for lib/clean functionality

BeforeAll {
    $script:RootDir = Split-Path -Parent $PSScriptRoot
    $script:LibDir = Join-Path $script:RootDir "lib"

    . "$script:LibDir\core\base.ps1"
    . "$script:LibDir\core\log.ps1"
    . "$script:LibDir\core\ui.ps1"
    . "$script:LibDir\core\file_ops.ps1"

    . "$script:LibDir\clean\user.ps1"
    . "$script:LibDir\clean\dev.ps1"
    . "$script:LibDir\clean\system.ps1"

    $env:WINMOLE_DRY_RUN = "1"
    Set-DryRunMode -Enabled $true
}

AfterAll {
    $env:WINMOLE_DRY_RUN = $null
    Set-DryRunMode -Enabled $false
}

Describe "User Cleanup Module" {
    Context "Clear-UserCaches" {
        It "Should have Clear-UserCaches function" {
            Get-Command Clear-UserCaches -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should run without error in dry-run mode" {
            { Clear-UserCaches } | Should -Not -Throw
        }
    }

    Context "Clear-UserLogs" {
        It "Should have Clear-UserLogs function" {
            Get-Command Clear-UserLogs -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Clear-RecycleBin" {
        It "Should have Clear-RecycleBin function" {
            Get-Command Clear-RecycleBin -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Invoke-UserCleanup" {
        It "Should have main user cleanup function" {
            Get-Command Invoke-UserCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Cache Cleanup Module" {
    Context "Browser Cache Functions" {
        It "Should have Clear-BrowserCaches function" {
            Get-Command Clear-BrowserCaches -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should run browser cache cleanup without error" {
            { Clear-BrowserCaches } | Should -Not -Throw
        }
    }

    Context "Application Cache Functions" {
        It "Should have Clear-ApplicationCaches function" {
            Get-Command Clear-ApplicationCaches -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Windows Update Cache" {
        It "Should have Clear-WindowsUpdateCache function" {
            Get-Command Clear-WindowsUpdateCache -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Invoke-UserCleanup" {
        It "Should have main cache cleanup function" {
            Get-Command Invoke-UserCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Developer Tools Cleanup Module" {
    Context "Node.js Cleanup" {
        It "Should have node cache cleanup function" {
            Get-Command Clear-NodeCache -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Python Cleanup" {
        It "Should have python cache cleanup function" {
            Get-Command Clear-PythonCache -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context ".NET Cleanup" {
        It "Should have dotnet cache cleanup function" {
            Get-Command Clear-DotNetCache -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Rust Cleanup" {
        It "Should have rust cache cleanup function" {
            Get-Command Clear-RustCache -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Go Cleanup" {
        It "Should have go cache cleanup function" {
            Get-Command Clear-GoCache -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Docker Cleanup" {
        It "Should have docker cache cleanup function" {
            Get-Command Clear-DockerCache -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Invoke-DevCleanup" {
        It "Should have main dev cleanup function" {
            Get-Command Invoke-DevCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should run without error in dry-run mode" {
            { Invoke-DevCleanup -All } | Should -Not -Throw
        }
    }
}

Describe "System Cleanup Module" {
    Context "System Caches" {
        It "Should have Clear-SystemCaches function" {
            Get-Command Clear-SystemCaches -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "System Logs" {
        It "Should have Clear-SystemLogs function" {
            Get-Command Clear-SystemLogs -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Windows Update Cleanup" {
        It "Should have Clear-WindowsUpdateCache function" {
            Get-Command Clear-WindowsUpdateCache -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Memory Dumps" {
        It "Should have Clear-MemoryDumps function" {
            Get-Command Clear-MemoryDumps -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Admin Requirements" {
        It "Should check for admin when needed" {
            { Clear-SystemCaches } | Should -Not -Throw
        }
    }

    Context "Invoke-SystemCleanup" {
        It "Should have main system cleanup function" {
            Get-Command Invoke-SystemCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}
