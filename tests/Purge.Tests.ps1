#Requires -Version 5.1
#Requires -Modules Pester

Describe 'Purge search path configuration' {
    BeforeAll {
        # Load only path selection; never launch the purge entry point.
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $repoRoot 'bin/purge.ps1'), [ref]$null, [ref]$null)
        $function = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Get-SearchPaths'
        }, $false)
        . ([scriptblock]::Create($function.Extent.Text))

        $script:DefaultSearchPaths = @((New-Item -Path (Join-Path $TestDrive 'default') -ItemType Directory).FullName)
    }

    BeforeEach {
        $script:ConfigFile = Join-Path $TestDrive 'purge_paths.txt'
    }

    It 'uses defaults when the configuration is absent' {
        @(Get-SearchPaths) | Should -Be $script:DefaultSearchPaths[0]
    }

    It 'uses the configured path literally instead of the default' {
        $script:ConfigFile = Join-Path $TestDrive 'purge_[paths].txt'
        $customPath = (New-Item -Path (Join-Path $TestDrive 'projects[local]') -ItemType Directory).FullName
        Set-Content -LiteralPath $script:ConfigFile -Value $customPath

        @(Get-SearchPaths) | Should -Be $customPath
    }

    It 'stops when the configuration probe reports an error' {
        Mock Test-Path {
            Write-Error 'Fixture probe failed' -ErrorAction $ErrorAction
        } -ParameterFilter { $LiteralPath -eq $script:ConfigFile -or $Path -eq $script:ConfigFile }

        { Get-SearchPaths } | Should -Throw '*Purge stopped without scanning*'
    }

    It 'stops when an existing configuration cannot be read' {
        Set-Content -LiteralPath $script:ConfigFile -Value '# fixture'
        Mock Get-Content {
            Write-Error 'Fixture read failed' -ErrorAction $ErrorAction
        } -ParameterFilter { $LiteralPath -eq $script:ConfigFile -or $Path -eq $script:ConfigFile }

        { Get-SearchPaths } | Should -Throw '*Purge stopped without scanning*'
    }

    It 'stops when a configured directory cannot be checked' {
        $customPath = Join-Path $TestDrive 'projects'
        Set-Content -LiteralPath $script:ConfigFile -Value $customPath
        Mock Test-Path {
            Write-Error 'Fixture directory probe failed' -ErrorAction $ErrorAction
        } -ParameterFilter { $LiteralPath -eq $customPath -or $Path -eq $customPath }

        { Get-SearchPaths } | Should -Throw '*Purge stopped without scanning*'
    }
}
