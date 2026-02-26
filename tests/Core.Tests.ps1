# WinMole - Core Module Tests
# Pester tests for lib/core functionality

BeforeAll {
    $script:RootDir = Split-Path -Parent $PSScriptRoot
    $script:LibDir = Join-Path $script:RootDir "lib"

    . "$script:LibDir\core\base.ps1"
    . "$script:LibDir\core\log.ps1"
    . "$script:LibDir\core\ui.ps1"
    . "$script:LibDir\core\file_ops.ps1"
}

Describe "Base Module" {
    Context "Color Definitions" {
        It "Should define color codes" {
            $script:Colors | Should -Not -BeNullOrEmpty
            $script:Colors.Cyan | Should -Not -BeNullOrEmpty
            $script:Colors.Green | Should -Not -BeNullOrEmpty
            $script:Colors.Red | Should -Not -BeNullOrEmpty
            $script:Colors.NC | Should -Not -BeNullOrEmpty
        }

        It "Should define icon set" {
            $script:Icons | Should -Not -BeNullOrEmpty
            $script:Icons.Success | Should -Not -BeNullOrEmpty
            $script:Icons.Error | Should -Not -BeNullOrEmpty
            $script:Icons.Warning | Should -Not -BeNullOrEmpty
        }
    }

    Context "Test-IsAdmin" {
        It "Should return a boolean" {
            $result = Test-IsAdmin
            $result | Should -BeOfType [bool]
        }
    }

    Context "Get-WindowsVersion" {
        It "Should return version info" {
            $result = Get-WindowsVersion
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Not -BeNullOrEmpty
            $result.Version | Should -Not -BeNullOrEmpty
            $result.Build | Should -Not -BeNullOrEmpty
        }
    }

    Context "Get-FreeSpace" {
        It "Should return free space string" {
            $result = Get-FreeSpace
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "\d+(\.\d+)? (B|KB|MB|GB|TB)"
        }

        It "Should accept drive parameter" {
            $result = Get-FreeSpace -Drive "C:"
            $result | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "File Operations Module" {
    BeforeAll {
        $script:TestDir = Join-Path $env:TEMP "winmole_test_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:TestDir) {
            Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Format-ByteSize" {
        It "Should format bytes correctly" {
            Format-ByteSize -Bytes 0 | Should -Be "0 B"
            Format-ByteSize -Bytes 1024 | Should -Be "1.0 KB"
            Format-ByteSize -Bytes 1048576 | Should -Be "1.0 MB"
            Format-ByteSize -Bytes 1073741824 | Should -Be "1.0 GB"
        }

        It "Should handle large numbers" {
            Format-ByteSize -Bytes 1099511627776 | Should -Be "1.00 TB"
        }
    }

    Context "Get-PathSize" {
        BeforeEach {
            $testFile = Join-Path $script:TestDir "testfile.txt"
            "Hello World" | Set-Content -Path $testFile
        }

        It "Should return size for file" {
            $testFile = Join-Path $script:TestDir "testfile.txt"
            $result = Get-PathSize -Path $testFile
            $result | Should -BeGreaterThan 0
        }

        It "Should return size for directory" {
            $result = Get-PathSize -Path $script:TestDir
            $result | Should -BeGreaterThan 0
        }

        It "Should return 0 for non-existent path" {
            $result = Get-PathSize -Path "C:\NonExistent\Path\12345"
            $result | Should -Be 0
        }
    }

    Context "Test-ProtectedPath" {
        It "Should protect Windows directory" {
            Test-ProtectedPath -Path "C:\Windows" | Should -Be $true
            Test-ProtectedPath -Path "C:\Windows\System32" | Should -Be $true
        }

        It "Should protect Windows Defender paths" {
            Test-ProtectedPath -Path "C:\Program Files\Windows Defender" | Should -Be $true
            Test-ProtectedPath -Path "C:\ProgramData\Microsoft\Windows Defender" | Should -Be $true
        }

        It "Should not protect temp directories" {
            Test-ProtectedPath -Path $env:TEMP | Should -Be $false
        }
    }

    Context "Test-SafePath" {
        It "Should return false for protected paths" {
            Test-SafePath -Path "C:\Windows" | Should -Be $false
            Test-SafePath -Path "C:\Windows\System32" | Should -Be $false
        }

        It "Should return true for safe paths" {
            Test-SafePath -Path $env:TEMP | Should -Be $true
        }

        It "Should return false for empty paths" {
            Test-SafePath -Path "" | Should -Be $false
        }
    }

    Context "Remove-SafeItem" {
        BeforeEach {
            $script:TestFile = Join-Path $script:TestDir "safe_remove_test.txt"
            "Test content" | Set-Content -Path $script:TestFile
        }

        It "Should remove file successfully" {
            $result = Remove-SafeItem -Path $script:TestFile
            $result | Should -Be $true
            Test-Path $script:TestFile | Should -Be $false
        }

        It "Should respect DryRun mode" {
            $env:WINMOLE_DRY_RUN = "1"
            try {
                Set-DryRunMode -Enabled $true
                $result = Remove-SafeItem -Path $script:TestFile
                $result | Should -Be $true
                Test-Path $script:TestFile | Should -Be $true
            }
            finally {
                $env:WINMOLE_DRY_RUN = $null
                Set-DryRunMode -Enabled $false
            }
        }

        It "Should not remove protected paths" {
            $result = Remove-SafeItem -Path "C:\Windows\System32"
            $result | Should -Be $false
        }
    }
}

Describe "Logging Module" {
    Context "Write-Log Functions" {
        It "Should have Write-Info function" {
            { Write-Info "Test message" } | Should -Not -Throw
        }

        It "Should have Write-Success function" {
            { Write-Success "Test message" } | Should -Not -Throw
        }

        It "Should have Write-Warning function" {
            { Write-Warning "Test message" } | Should -Not -Throw
        }

        It "Should have Write-Error function" {
            { Write-Error "Test message" } | Should -Not -Throw
        }
    }

    Context "Section Functions" {
        It "Should start and stop sections without error" {
            { Start-Section -Title "Test Section" } | Should -Not -Throw
            { Stop-Section } | Should -Not -Throw
        }
    }
}

Describe "UI Module" {
    Context "Show-Banner" {
        It "Should display banner without error" {
            { Show-Banner } | Should -Not -Throw
        }
    }

    Context "Show-Header" {
        It "Should display header without error" {
            { Show-Header -Title "Test Header" } | Should -Not -Throw
        }

        It "Should accept subtitle parameter" {
            { Show-Header -Title "Test" -Subtitle "Subtitle" } | Should -Not -Throw
        }
    }

    Context "Show-Summary" {
        It "Should display summary without error" {
            { Show-Summary -SizeBytes 1024 -ItemCount 5 } | Should -Not -Throw
        }
    }

    Context "Read-Confirmation" {
        It "Should have Read-Confirmation function" {
            Get-Command Read-Confirmation -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}
