#!/usr/bin/env pwsh
# WinMole - cleanup module tests (lib/clean/*) and dry-run integration tests
# Run with: Invoke-Pester -Path .\tests\

#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    # Pester 5 runs each test file in its own scope, so this setup is repeated
    # per suite. It cannot live in a helper function: dot-sourcing the modules
    # inside one would scope those definitions to the function.
    $script:ROOT = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $script:LIB_DIR = Join-Path $script:ROOT "lib"
    $script:BIN_DIR = Join-Path $script:ROOT "bin"

    . "$script:LIB_DIR\core\base.ps1"
    . "$script:LIB_DIR\core\log.ps1"
    . "$script:LIB_DIR\core\file_ops.ps1"
    . "$script:LIB_DIR\clean\apps.ps1"

    $script:TEST_TEMP = Join-Path $env:TEMP "WinMole_Tests_Clean_$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TEST_TEMP -Force | Out-Null
}

AfterAll {
    if ($script:TEST_TEMP -and (Test-Path $script:TEST_TEMP)) {
        Remove-Item -Path $script:TEST_TEMP -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# Cleanup Modules
# ============================================================================

Describe "Cleanup Modules" {

    Context "Get-InstalledPrograms" {
        It "ignores registry entries without DisplayName under strict mode" {
            Mock Get-ItemProperty {
                @(
                    [pscustomobject]@{ Publisher = "NoName Publisher" }
                    [pscustomobject]@{
                        DisplayName     = "Named App"
                        InstallLocation = "C:\Tools\NamedApp"
                        Publisher       = "Named Publisher"
                    }
                )
            }

            Mock Get-AppxPackage { @() }

            { Get-InstalledPrograms | Out-Null } | Should -Not -Throw
            $result = Get-InstalledPrograms
            # The mock is returned once per registry path scanned, and the entry
            # without a DisplayName is filtered out of each batch.
            @($result).Count | Should -Be 3
            @($result | Where-Object { $_.DisplayName -eq "Named App" }).Count | Should -Be 3
        }
    }
}

# ============================================================================
# Integration Tests
#
# These invoke bin/clean.ps1 for real, so they are tagged Integration and
# excluded from the default run. WINMOLE_DRY_RUN is set so nothing is deleted.
# ============================================================================

Describe "Integration Tests" -Tag "Integration" {

    Context "Dry Run Mode" {
        It "clean respects dry run" {
            $env:WINMOLE_DRY_RUN = "1"
            try {
                $output = & (Join-Path $script:BIN_DIR "clean.ps1") -User -DryRun 2>&1 | Out-String
                $output | Should -Not -Match "An error occurred"
                $output | Should -Not -Match "is not recognized as"
                $output | Should -Not -Match '(?m)^\s*Name\s+Value\s*$'
                $output | Should -Not -Match '(?m)^\s*(True|False)\s*$'
            }
            finally {
                Remove-Item Env:WINMOLE_DRY_RUN -ErrorAction SilentlyContinue
            }
        }

        It "clean browser dry run completes" {
            $env:WINMOLE_DRY_RUN = "1"
            try {
                $output = & (Join-Path $script:BIN_DIR "clean.ps1") -Browsers -DryRun 2>&1 | Out-String
                $output | Should -Not -Match "is not recognized as"
                $output | Should -Not -Match "An error occurred"
            }
            finally {
                Remove-Item Env:WINMOLE_DRY_RUN -ErrorAction SilentlyContinue
            }
        }

        It "clean developer dry run completes" {
            $env:WINMOLE_DRY_RUN = "1"
            try {
                $output = & (Join-Path $script:BIN_DIR "clean.ps1") -Dev -DryRun 2>&1 | Out-String
                $output | Should -Not -Match "is not recognized as"
                $output | Should -Not -Match "An error occurred"
            }
            finally {
                Remove-Item Env:WINMOLE_DRY_RUN -ErrorAction SilentlyContinue
            }
        }
    }
}
