#!/usr/bin/env pwsh
# WinMole - installer tests

#Requires -Version 5.1
#Requires -Modules Pester

Describe "Installer" {
    It "overwrites an existing installation without nesting directories" {
        $root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
        $installDir = Join-Path $TestDrive "WinMole"
        $installedFiles = @(
            "winmole.ps1"
            "winmole.cmd"
            "lib\core\base.ps1"
            "lib\core\common.ps1"
            "bin\clean.ps1"
            "cmd\analyze\main.go"
        )

        foreach ($relativePath in $installedFiles) {
            $installedFile = Join-Path $installDir $relativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $installedFile) -Force | Out-Null
            Set-Content -Path $installedFile -Value "stale"
        }

        & (Join-Path $root "install.ps1") -InstallDir $installDir -Force *> $null

        foreach ($directory in @("lib", "bin", "cmd")) {
            Test-Path (Join-Path $installDir "$directory\$directory") | Should -BeFalse
        }
        foreach ($relativePath in $installedFiles | Where-Object { $_ -ne "winmole.cmd" }) {
            Get-Content -Raw (Join-Path $installDir $relativePath) |
                Should -Be (Get-Content -Raw (Join-Path $root $relativePath))
        }
    }

    It "refuses to force-install over an ordinary non-empty directory" {
        $root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
        $installDir = Join-Path $TestDrive "ordinary-install-target"
        $sentinel = Join-Path $installDir "keep.txt"
        New-Item -ItemType Directory -Path $installDir | Out-Null
        Set-Content -LiteralPath $sentinel -Value "keep"

        & (Join-Path $root "install.ps1") -InstallDir $installDir -Force *> $null

        Test-Path -LiteralPath $sentinel | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $installDir "winmole.ps1") | Should -BeFalse
    }

    It "does not uninstall an ordinary directory" {
        $root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
        $installDir = Join-Path $TestDrive "ordinary-uninstall-target"
        $sentinel = Join-Path $installDir "keep.txt"
        New-Item -ItemType Directory -Path $installDir | Out-Null
        Set-Content -LiteralPath $sentinel -Value "keep"

        & (Join-Path $root "install.ps1") -InstallDir $installDir -Uninstall *> $null

        Test-Path -LiteralPath $sentinel | Should -BeTrue
    }

    It "does not uninstall a protected WinMole-shaped directory" {
        $root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
        $installDir = Join-Path $TestDrive "protected-install-target"
        $originalWindir = $env:WINDIR

        foreach ($relativePath in @("winmole.ps1", "winmole.cmd", "bin\clean.ps1", "lib\core\base.ps1")) {
            $marker = Join-Path $installDir $relativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $marker) -Force | Out-Null
            Set-Content -LiteralPath $marker -Value "keep"
        }

        try {
            $env:WINDIR = $installDir
            & (Join-Path $root "install.ps1") -InstallDir $installDir -Uninstall *> $null
        }
        finally {
            $env:WINDIR = $originalWindir
        }

        Test-Path -LiteralPath (Join-Path $installDir "winmole.ps1") | Should -BeTrue
    }
}
