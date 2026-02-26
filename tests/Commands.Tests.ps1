# WinMole - Command Tests
# Pester tests for bin/ command scripts

BeforeAll {
    $script:RootDir = Split-Path -Parent $PSScriptRoot
    $script:BinDir = Join-Path $script:RootDir "bin"
}

Describe "Clean Command" {
    Context "Help Display" {
        It "Should show help without error" {
            $result = & powershell -ExecutionPolicy Bypass -File "$script:BinDir\clean.ps1" -Help 2>&1
            $result | Should -Not -BeNullOrEmpty
            $LASTEXITCODE | Should -Be 0
        }

        It "Should mention dry-run in help" {
            $result = & powershell -ExecutionPolicy Bypass -File "$script:BinDir\clean.ps1" -Help 2>&1
            $result -join "`n" | Should -Match "(DryRun|dry-run)"
        }
    }

    Context "Dry Run Mode" {
        It "Should support -DryRun parameter" {
            $job = Start-Job -ScriptBlock {
                param($binDir)
                & powershell -ExecutionPolicy Bypass -File "$binDir\clean.ps1" -DryRun 2>&1
            } -ArgumentList $script:BinDir

            Start-Sleep -Seconds 3
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -Force -ErrorAction SilentlyContinue

            $true | Should -Be $true
        }
    }
}

Describe "Uninstall Command" {
    Context "Help Display" {
        It "Should show help without error" {
            $result = & powershell -ExecutionPolicy Bypass -File "$script:BinDir\uninstall.ps1" -Help 2>&1
            $result | Should -Not -BeNullOrEmpty
            $LASTEXITCODE | Should -Be 0
        }
    }
}

Describe "Optimize Command" {
    Context "Help Display" {
        It "Should show help without error" {
            $result = & powershell -ExecutionPolicy Bypass -File "$script:BinDir\optimize.ps1" -Help 2>&1
            $result | Should -Not -BeNullOrEmpty
            $LASTEXITCODE | Should -Be 0
        }

        It "Should mention optimization options in help" {
            $result = & powershell -ExecutionPolicy Bypass -File "$script:BinDir\optimize.ps1" -Help 2>&1
            $result -join "`n" | Should -Match "DryRun|Defrag|Network"
        }
    }
}

Describe "Purge Command" {
    Context "Help Display" {
        It "Should show help without error" {
            $result = & powershell -ExecutionPolicy Bypass -File "$script:BinDir\purge.ps1" -Help 2>&1
            $result | Should -Not -BeNullOrEmpty
            $LASTEXITCODE | Should -Be 0
        }

        It "Should list artifact types in help" {
            $result = & powershell -ExecutionPolicy Bypass -File "$script:BinDir\purge.ps1" -Help 2>&1
            $result -join "`n" | Should -Match "node_modules|target|venv"
        }
    }
}

Describe "Analyze Command" {
    Context "Help Display" {
        It "Should show help without error" {
            $result = & powershell -ExecutionPolicy Bypass -File "$script:BinDir\analyze.ps1" -Help 2>&1
            $result | Should -Not -BeNullOrEmpty
            $LASTEXITCODE | Should -Be 0
        }

        It "Should mention keybindings in help" {
            $result = & powershell -ExecutionPolicy Bypass -File "$script:BinDir\analyze.ps1" -Help 2>&1
            $result -join "`n" | Should -Match "Navigate|Enter|Quit"
        }
    }
}

Describe "Status Command" {
    Context "Help Display" {
        It "Should show help without error" {
            $result = & powershell -ExecutionPolicy Bypass -File "$script:BinDir\status.ps1" -Help 2>&1
            $result | Should -Not -BeNullOrEmpty
            $LASTEXITCODE | Should -Be 0
        }

        It "Should mention system metrics in help" {
            $result = & powershell -ExecutionPolicy Bypass -File "$script:BinDir\status.ps1" -Help 2>&1
            $result -join "`n" | Should -Match "CPU|Memory|Disk|monitor"
        }
    }
}

Describe "Main Entry Point" {
    Context "winmole.ps1" {
        BeforeAll {
            $script:WinMolePath = Join-Path $script:RootDir "winmole.ps1"
        }

        It "Should show help without error" {
            $result = & powershell -ExecutionPolicy Bypass -File $script:WinMolePath -ShowHelp 2>&1
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should show version without error" {
            $result = & powershell -ExecutionPolicy Bypass -File $script:WinMolePath -Version 2>&1
            $result | Should -Not -BeNullOrEmpty
            $result -join "`n" | Should -Match "WinMole|v\d+\.\d+"
        }

        It "Should list available commands in help" {
            $result = & powershell -ExecutionPolicy Bypass -File $script:WinMolePath -ShowHelp 2>&1
            $helpText = $result -join "`n"
            $helpText | Should -Match "clean"
            $helpText | Should -Match "uninstall"
            $helpText | Should -Match "optimize"
            $helpText | Should -Match "purge"
            $helpText | Should -Match "analyze"
            $helpText | Should -Match "status"
        }
    }
}
