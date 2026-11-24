#!/usr/bin/env pwsh
# WinMole - installer tests

#Requires -Version 5.1
#Requires -Modules Pester

Describe "Installer" {
    It "creates a fresh destination without force" {
        $root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
        $installDir = Join-Path $TestDrive 'new-parent/WinMole [local]'
        $decoy = Join-Path $TestDrive 'new-parent/WinMole l/winmole.cmd'
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $decoy) -Force
        [IO.File]::WriteAllText($decoy, 'untouched')
        & (Join-Path $root 'install.ps1') -InstallDir $installDir *> $null
        [IO.File]::ReadAllText($decoy) | Should -Be 'untouched'
        Test-Path -LiteralPath (Join-Path $installDir 'winmole.cmd') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $installDir 'bin/clean.ps1') -PathType Leaf | Should -BeTrue
    }

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

        foreach ($marker in @("winmole.ps1", "winmole.cmd", "lib\core\base.ps1")) {
            Set-Content -LiteralPath (Join-Path $installDir $marker) -Value "stale"
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


Describe 'Installer destination guard' {
    BeforeAll {
        $repo = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $repo 'install.ps1'), [ref]$null, [ref]$null)
        foreach ($function in $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -in @('Install-WinMole', 'Test-WinMoleInstallDestination', 'Assert-WinMoleOrdinaryInstallPath', 'Get-WinMoleInstallPathItem')
        }, $false)) {
            . ([scriptblock]::Create($function.Extent.Text))
        }

        function Write-Info { param($Message) }
        $script:VERSION = 'test'
    }

    BeforeEach {
        $InstallDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Path $InstallDir
        $Force = $true
        Mock Copy-Item { throw 'Copy must not be called' }
        Mock Set-Content { throw 'Launcher must not be written' }
    }

    It 'refuses before copying if an unrelated file is present' {
        [IO.File]::WriteAllText((Join-Path $InstallDir 'sentinel.txt'), 'untouched')
        { Install-WinMole } | Should -Throw '*not a recognizable WinMole installation*'
        Should -Invoke Copy-Item -Times 0 -Exactly
        Should -Invoke Set-Content -Times 0 -Exactly
        [IO.File]::ReadAllText((Join-Path $InstallDir 'sentinel.txt')) | Should -Be 'untouched'
    }

    It 'refuses before copying if the directory cannot be enumerated' {
        Mock Get-ChildItem {
            throw 'Fixture directory enumeration denied'
        } -ParameterFilter { $LiteralPath -eq $InstallDir }

        { Install-WinMole } | Should -Throw '*Fixture directory enumeration denied*'
        Should -Invoke Copy-Item -Times 0 -Exactly
        Should -Invoke Set-Content -Times 0 -Exactly
    }

    It 'refuses rather than creating a target when its metadata cannot be read' {
        # Return ordinary directory metadata for unrelated ancestor probes.
        Mock Get-Item { [IO.DirectoryInfo]::new($LiteralPath) }
        Mock Get-Item {
            throw [System.UnauthorizedAccessException]::new('Fixture metadata denied')
        } -ParameterFilter { $LiteralPath -eq $InstallDir }

        { Install-WinMole } | Should -Throw '*Fixture metadata denied*'
        Should -Invoke Copy-Item -Times 0 -Exactly
        Should -Invoke Set-Content -Times 0 -Exactly
    }

    It 'refuses a destination under a linked ancestor' {
        $outside = Join-Path $TestDrive 'linked-ancestor-target'
        $null = New-Item -ItemType Directory -Path $outside
        $link = Join-Path $TestDrive 'linked-ancestor'
        $linkType = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $linkType -Path $link -Value $outside
        $InstallDir = Join-Path $link 'missing-child'

        { Install-WinMole } | Should -Throw '*Not an ordinary install write path*'
        Test-Path -LiteralPath (Join-Path $outside 'missing-child') | Should -BeFalse
        Should -Invoke Copy-Item -Times 0 -Exactly
    }

    It 'refuses nested linked write paths under an existing install' {
        foreach ($marker in @('winmole.ps1', 'winmole.cmd', 'bin/clean.ps1', 'lib/core/base.ps1')) {
            $path = Join-Path $InstallDir $marker
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force
            [IO.File]::WriteAllText($path, 'fixture')
        }
        $outside = Join-Path $TestDrive 'nested-junction-target'
        $null = New-Item -ItemType Directory -Path $outside
        $sentinel = Join-Path $outside 'sentinel.txt'
        [IO.File]::WriteAllText($sentinel, 'untouched')
        $linkType = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $linkType -Path (Join-Path $InstallDir 'bin/linked') -Value $outside

        { Install-WinMole } | Should -Throw '*Not an ordinary install write path*'
        Should -Invoke Copy-Item -Times 0 -Exactly
        Should -Invoke Set-Content -Times 0 -Exactly
        [IO.File]::ReadAllText($sentinel) | Should -Be 'untouched'
    }

    It 'allows a verified empty directory only with force' {
        Test-WinMoleInstallDestination -Path $InstallDir -AllowOverwrite | Should -BeTrue
        { Test-WinMoleInstallDestination -Path $InstallDir } | Should -Throw '*already exists*'
    }

    It 'distinguishes missing paths from existing paths when the provider returns no object' {
        $missing = Join-Path $TestDrive 'missing [folder]'
        Mock Get-Item { [IO.DirectoryInfo]::new($LiteralPath) }
        Mock Get-Item { return $null } -ParameterFilter {
            $LiteralPath -eq $missing -or $LiteralPath -eq $InstallDir
        }

        Test-WinMoleInstallDestination -Path $missing | Should -BeFalse
        { Install-WinMole } | Should -Throw '*Cannot inspect existing install write path*'
        Should -Invoke Copy-Item -Times 0 -Exactly
    }

    It 'allows a new literal target without force' {
        Test-WinMoleInstallDestination -Path (Join-Path $TestDrive 'new [folder]') | Should -BeFalse
    }
}
