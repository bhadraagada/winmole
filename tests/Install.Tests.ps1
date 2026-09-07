#!/usr/bin/env pwsh
# WinMole - installer tests

#Requires -Version 5.1
#Requires -Modules Pester

Describe "Installer" {
    It "overwrites an existing installation without nesting directories" {
        $root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
        $installDir = Join-Path $TestDrive "WinMole"
        $installedFiles = @(
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
        foreach ($relativePath in $installedFiles) {
            Get-Content -Raw (Join-Path $installDir $relativePath) |
                Should -Be (Get-Content -Raw (Join-Path $root $relativePath))
        }
    }
}
