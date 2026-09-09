#Requires -Version 5.1
#Requires -Modules Pester

Describe 'Bundled <Tool> launcher' -ForEach @(
    @{ Tool = 'Analyze' }
    @{ Tool = 'Status' }
) {
    BeforeAll {
        $root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
        $wrapper = Join-Path $root "bin\$Tool.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($wrapper, [ref]$null, [ref]$null)
        # Load only launcher functions so the tests never start an interactive TUI.
        $functions = $ast.FindAll({ param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -in @('Get-GoBinaryPath', "Build-$Tool`Tool", "Invoke-$Tool`Tool")
        }, $false)
        foreach ($function in $functions) {
            . ([scriptblock]::Create($function.Extent.Text))
        }
    }

    BeforeEach {
        $script:WINMOLE_CMD = Join-Path $TestDrive 'cmd'
        $script:launcherStub = Join-Path $TestDrive 'bundled-tool.ps1'
        Set-Content -LiteralPath $script:launcherStub -Value "'bundled tool started'"
        Mock Get-GoBinaryPath { $script:launcherStub }
        Mock "Build-$Tool`Tool" { $false }
    }

    It 'runs the bundled binary when release source is absent' {
        & "Invoke-$Tool`Tool" | Should -Be 'bundled tool started'
        Should -Invoke "Build-$Tool`Tool" -Times 0 -Exactly
    }

    It 'still builds when the binary is missing' {
        Mock Get-GoBinaryPath { Join-Path $TestDrive 'missing.exe' }
        & "Invoke-$Tool`Tool"
        Should -Invoke "Build-$Tool`Tool" -Times 1 -Exactly
    }

    It 'still rebuilds when checkout source is newer' {
        $source = Join-Path $script:WINMOLE_CMD "$Tool\main.go"
        New-Item -ItemType Directory -Path (Split-Path -Parent $source) -Force | Out-Null
        Set-Content -LiteralPath $source -Value '// test source'
        (Get-Item -LiteralPath $script:launcherStub).LastWriteTime = (Get-Date).AddMinutes(-1)
        & "Invoke-$Tool`Tool"
        Should -Invoke "Build-$Tool`Tool" -Times 1 -Exactly
    }
}
