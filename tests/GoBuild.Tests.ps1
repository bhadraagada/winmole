#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:SavedEnvironment = @{}
    foreach ($name in @('PATH', 'CGO_ENABLED', 'GOOS', 'GOARCH')) {
        $script:SavedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    function Write-Info { param($Message) }
    function Write-Success { param($Message) }
    function Write-WinMoleError { param($Message) }
    function Write-Fail { param($Message) }
    function Write-Warn { param($Message) }
}

AfterAll {
    foreach ($name in $script:SavedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $script:SavedEnvironment[$name], 'Process')
    }
}

Describe 'Native Go build output' {
    BeforeEach {
        $ErrorActionPreference = 'Stop'
        Set-StrictMode -Version Latest
        $script:Fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:ROOT = $script:Fixture
        $script:WINMOLE_ROOT = $script:Fixture
        $script:CMD_DIR = Join-Path $script:Fixture 'cmd'
        $script:WINMOLE_CMD = $script:CMD_DIR
        $script:BIN_DIR = Join-Path $script:Fixture 'bin'
        $script:GO_TOOLS = @('analyze', 'status')
        $script:VERSION = 'test'
        $ShowDetails = $false
        $Release = $false
        New-Item -ItemType Directory -Path $script:BIN_DIR,
            (Join-Path $script:CMD_DIR 'analyze'), (Join-Path $script:CMD_DIR 'status') | Out-Null
        $script:GoExe = Join-Path $script:Fixture 'go.cmd'
        # A native command is required: a PowerShell mock cannot reproduce
        # Windows PowerShell 5.1 treating redirected native stderr as an error.
        Set-Content -LiteralPath $script:GoExe -Value @'
@echo off
echo go: downloading harmless fixture v1.0.0 1>&2
if "%1"=="build" echo fixture>"%~4"
exit /b 0
'@
        $env:PATH = "$script:Fixture;$($script:SavedEnvironment['PATH'])"
        $script:OriginalLocation = (Get-Location).Path
    }

    Context '<Name> wrapper' -ForEach @(@{ Name = 'analyze' }, @{ Name = 'status' }) {
        BeforeEach {
            # Load only these functions; never initialize WinMole or launch a TUI.
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $script:RepoRoot "bin\$Name.ps1"), [ref]$null, [ref]$null)
            foreach ($function in $ast.FindAll({ param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -match '^(Get-GoBinaryPath|Build-.*Tool|Invoke-.*Tool)$'
            }, $false)) {
                . ([scriptblock]::Create($function.Extent.Text))
            }
        }

        It 'accepts successful builds that write progress to stderr' {
            Set-Content -LiteralPath (Join-Path $script:Fixture 'go.sum') -Value ''
            & "Build-$($Name)Tool" | Should -BeTrue
            $LASTEXITCODE | Should -Be 0
            (Get-Location).Path | Should -Be $script:OriginalLocation
            $ErrorActionPreference | Should -Be 'Stop'
        }

        It 'accepts dependency progress when go.sum is absent' {
            & "Build-$($Name)Tool" | Should -BeTrue
        }

        It 'rejects a nonzero build and prevents the launcher from reporting success' {
            Set-Content -LiteralPath (Join-Path $script:Fixture 'go.sum') -Value ''
            Set-Content -LiteralPath $script:GoExe -Value "@echo off`r`necho fixture compilation failed 1>&2`r`nexit /b 7"
            & "Build-$($Name)Tool" | Should -BeFalse
            $LASTEXITCODE | Should -Be 7
            { & "Invoke-$($Name)Tool" } | Should -Throw '*Unable to build*'
            (Get-Location).Path | Should -Be $script:OriginalLocation
            $ErrorActionPreference | Should -Be 'Stop'
        }

        It 'stops on failed dependency setup even if a subsequent build would succeed' {
            Set-Content -LiteralPath $script:GoExe -Value @'
@echo off
if "%1"=="mod" (
    echo fixture dependency setup failed 1>&2
    exit /b 7
)
if "%1"=="build" echo fixture>"%~4"
exit /b 0
'@
            & "Build-$($Name)Tool" | Should -BeFalse
            $LASTEXITCODE | Should -Be 7
            Test-Path -LiteralPath (Get-GoBinaryPath) | Should -BeFalse
            (Get-Location).Path | Should -Be $script:OriginalLocation
        }

        It 'exits nonzero and preserves native diagnostics through the command entry point' {
            Set-Content -LiteralPath (Join-Path $script:Fixture 'go.sum') -Value ''
            Set-Content -LiteralPath $script:GoExe -Value "@echo off`r`necho fixture compilation failed 1>&2`r`nexit /b 7"
            $core = New-Item -ItemType Directory -Path (Join-Path $script:Fixture 'lib\core')
            Set-Content -LiteralPath (Join-Path $core.FullName 'common.ps1') -Value @'
function Initialize-WinMole { }
function Restore-WinMoleConsoleEncoding { }
function Write-Info { param($Message) }
function Write-WinMoleError { param($Message) Write-Host $Message }
'@
            $entryPoint = Join-Path $script:BIN_DIR "$Name.ps1"
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot "bin\$Name.ps1") -Destination $entryPoint
            $shell = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } else { 'pwsh.exe' }
            $commandArguments = @('-NoProfile', '-NonInteractive', '-File', "`"$entryPoint`"")
            if ($Name -eq 'analyze') { $commandArguments += @('-Path', "`"$script:Fixture`"") }
            $stderrPath = Join-Path $script:Fixture 'stderr.txt'
            $process = Start-Process -FilePath (Join-Path $PSHOME $shell) -ArgumentList $commandArguments `
                -WindowStyle Hidden -Wait -PassThru -RedirectStandardError $stderrPath `
                -RedirectStandardOutput (Join-Path $script:Fixture 'stdout.txt')
            $process.ExitCode | Should -Be 1
            Get-Content -LiteralPath $stderrPath -Raw | Should -Match 'fixture compilation failed'
        }
    }

    Context 'Build script' {
        BeforeEach {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $script:RepoRoot 'scripts\build.ps1'), [ref]$null, [ref]$null)
            foreach ($function in $ast.FindAll({ param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -in @('Build-GoTool', 'Build-AllGo')
            }, $false)) {
                . ([scriptblock]::Create($function.Extent.Text))
            }
            function Test-GoInstalled { return $true }
        }

        It 'accepts a successful build with stderr progress' {
            Build-GoTool -Name analyze | Should -BeTrue
        }

        It 'accepts tidy, download, and build progress for both tools' {
            Build-AllGo | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:BIN_DIR 'analyze.exe') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:BIN_DIR 'status.exe') | Should -BeTrue
            (Get-Location).Path | Should -Be $script:OriginalLocation
            $ErrorActionPreference | Should -Be 'Stop'
        }

        It 'rejects nonzero builds even when diagnostics are on stderr' {
            Set-Content -LiteralPath $script:GoExe -Value "@echo off`r`necho fixture compilation failed 1>&2`r`nexit /b 7"
            Build-AllGo | Should -BeFalse
            $LASTEXITCODE | Should -Be 7
            (Get-Location).Path | Should -Be $script:OriginalLocation
            $ErrorActionPreference | Should -Be 'Stop'
        }
    }
}
