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

Describe 'Native tool exit status' {
    BeforeAll {
        $package = Join-Path $TestDrive 'native-package'
        New-Item -ItemType Directory -Path "$package\bin", "$package\lib\core" | Out-Null
        Copy-Item -LiteralPath "$script:RepoRoot\winmole.ps1" -Destination $package
        Copy-Item -LiteralPath "$script:RepoRoot\bin\analyze.ps1", "$script:RepoRoot\bin\status.ps1" -Destination "$package\bin"
        # Keep initialization and cleanup inside the fixture.
        Set-Content -LiteralPath "$package\lib\core\common.ps1" -Value @'
function Initialize-WinMole { }
function Restore-WinMoleConsoleEncoding { }
function Clear-TempFiles { }
function Write-WinMoleError { param($Message) Write-Host $Message }
$script:Colors = @{ Cyan = ''; Gray = ''; Green = ''; NC = '' }
'@
        New-Item -ItemType Directory -Path (Join-Path $package '[sample] folder') | Out-Null
        Set-Content -LiteralPath (Join-Path $package 'sample.txt') -Value 'fixture'
        $source = Join-Path $TestDrive 'native.go'
        Set-Content -LiteralPath $source -Value @'
package main
import ("fmt"; "os")
func main() {
    if os.Getenv("WINMOLE_TEST_NATIVE_FAILURE") == "1" {
        fmt.Fprintln(os.Stderr, "fixture native failure")
        os.Exit(7)
    }
    fmt.Println(`{"ok":true}`)
}
'@
        & go build -o "$package\bin\analyze.exe" $source
        if ($LASTEXITCODE -ne 0) { throw 'Native fixture build failed.' }
        Copy-Item -LiteralPath "$package\bin\analyze.exe" -Destination "$package\bin\status.exe"
        $shell = (Get-Process -Id $PID).Path
        $stdout = Join-Path $TestDrive 'native-stdout.txt'
        $stderr = Join-Path $TestDrive 'native-stderr.txt'
        $savedNativeFailure = $env:WINMOLE_TEST_NATIVE_FAILURE
    }

    AfterAll {
        $env:WINMOLE_TEST_NATIVE_FAILURE = $savedNativeFailure
    }

    Context '<Name> via <Entry>' -ForEach @(
        @{ Name = 'analyze'; Entry = 'wrapper' },
        @{ Name = 'analyze'; Entry = 'main' },
        @{ Name = 'status'; Entry = 'wrapper' },
        @{ Name = 'status'; Entry = 'main' }
    ) {
        It 'returns <ExpectedExit> for native failure=<Failure> and JSON=<Json>' -ForEach @(
            @{ Failure = '1'; Json = $false; ExpectedExit = 1 },
            @{ Failure = '1'; Json = $true; ExpectedExit = 1 },
            @{ Failure = '0'; Json = $false; ExpectedExit = 0 },
            @{ Failure = '0'; Json = $true; ExpectedExit = 0 }
        ) {
            $env:WINMOLE_TEST_NATIVE_FAILURE = $Failure
            $entryPoint = if ($Entry -eq 'main') { "$package\winmole.ps1" } else { "$package\bin\$Name.ps1" }
            $commandArguments = @('-NoProfile', '-NonInteractive', '-File', "`"$entryPoint`"")
            if ($Entry -eq 'main') { $commandArguments += $Name }
            if ($Name -eq 'analyze') { $commandArguments += "`"$package`"" }
            if ($Json) { $commandArguments += '-Json' }
            $process = Start-Process -FilePath $shell -ArgumentList $commandArguments `
                -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
            $process.ExitCode | Should -Be $ExpectedExit
            if ($Failure -eq '1') {
                Get-Content -LiteralPath $stderr -Raw | Should -Match 'fixture native failure'
                Get-Content -LiteralPath $stderr -Raw | Should -Match 'exit code 7'
                Get-Content -LiteralPath $stdout -Raw | Should -BeNullOrEmpty
            }
            else {
                (Get-Content -LiteralPath $stdout -Raw | ConvertFrom-Json).ok | Should -BeTrue
                Get-Content -LiteralPath $stderr -Raw | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Analyze paths via <Entry> with JSON=<Json>' -ForEach @(
        @{ Entry = 'wrapper'; Json = $false },
        @{ Entry = 'main'; Json = $false },
        @{ Entry = 'wrapper'; Json = $true },
        @{ Entry = 'main'; Json = $true }
    ) {
        BeforeEach {
            $env:WINMOLE_TEST_NATIVE_FAILURE = '0'
            $entryPoint = if ($Entry -eq 'main') { "$package\winmole.ps1" } else { "$package\bin\analyze.ps1" }
            $commandArguments = @('-NoProfile', '-NonInteractive', '-File', "`"$entryPoint`"")
            if ($Entry -eq 'main') { $commandArguments += 'analyze' }
            if ($Json) { $commandArguments += '-Json' }
        }

        It 'rejects <Target> with stderr and a nonzero exit' -ForEach @(
            @{ Target = 'missing' }, @{ Target = 'sample.txt' }
        ) {
            $targetPath = Join-Path $package $Target
            $commandArguments += "`"$targetPath`""
            $process = Start-Process -FilePath $shell -ArgumentList $commandArguments `
                -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr

            $process.ExitCode | Should -Be 1
            Get-Content -LiteralPath $stdout -Raw | Should -BeNullOrEmpty
            $errorText = Get-Content -LiteralPath $stderr -Raw
            $errorText | Should -Match 'Not an existing directory:'
            $errorText | Should -Match ([regex]::Escape($Target))
        }

        It 'accepts the <Kind> directory' -ForEach @(
            @{ Kind = 'default'; Target = $null },
            @{ Kind = 'relative'; Target = '.' },
            @{ Kind = 'literal brackets and spaces'; Target = '[sample] folder' }
        ) {
            if ($Target) { $commandArguments += "`"$Target`"" }
            $process = Start-Process -FilePath $shell -ArgumentList $commandArguments `
                -WorkingDirectory $package -WindowStyle Hidden -Wait -PassThru `
                -RedirectStandardOutput $stdout -RedirectStandardError $stderr

            $process.ExitCode | Should -Be 0
            (Get-Content -LiteralPath $stdout -Raw | ConvertFrom-Json).ok | Should -BeTrue
            Get-Content -LiteralPath $stderr -Raw | Should -BeNullOrEmpty
        }

        It 'shows help before validating the directory' {
            $commandArguments += @("`"$(Join-Path $package 'missing')`"", '-Help')
            $process = Start-Process -FilePath $shell -ArgumentList $commandArguments `
                -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr

            $process.ExitCode | Should -Be 0
            Get-Content -LiteralPath $stdout -Raw | Should -Match 'Directory to analyze'
            Get-Content -LiteralPath $stderr -Raw | Should -BeNullOrEmpty
        }
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

        It 'rebuilds only for newer metadata when <ModuleFile> is <Age>' -ForEach @(
            @{ ModuleFile = 'go.mod'; Age = 'newer'; Days = 1 },
            @{ ModuleFile = 'go.sum'; Age = 'newer'; Days = 1 },
            @{ ModuleFile = 'go.mod'; Age = 'older'; Days = -1 },
            @{ ModuleFile = 'go.sum'; Age = 'older'; Days = -1 },
            @{ ModuleFile = 'go.mod'; Age = 'equal'; Days = 0 },
            @{ ModuleFile = 'go.sum'; Age = 'equal'; Days = 0 },
            @{ ModuleFile = 'go.mod'; Age = 'missing'; Days = $null },
            @{ ModuleFile = 'go.sum'; Age = 'missing'; Days = $null }
        ) {
            $script:Json = $false
            Mock Get-GoBinaryPath { Join-Path $script:BIN_DIR 'launch.cmd' }
            Mock "Build-$($Name)Tool" { $true }
            $binaryPath = Get-GoBinaryPath
            Set-Content -LiteralPath $binaryPath -Value "@echo off`r`nexit /b 0"
            $binaryTime = [datetime]'2020-01-02'
            (Get-Item -LiteralPath $binaryPath).LastWriteTime = $binaryTime
            $sourcePath = Join-Path $script:CMD_DIR "$Name\main.go"
            foreach ($filePath in @($sourcePath, (Join-Path $script:Fixture 'go.mod'), (Join-Path $script:Fixture 'go.sum'))) {
                if ($Age -eq 'missing' -and (Split-Path -Leaf $filePath) -eq $ModuleFile) { continue }
                Set-Content -LiteralPath $filePath -Value 'fixture'
                (Get-Item -LiteralPath $filePath).LastWriteTime = $binaryTime.AddDays(-1)
            }
            if ($Age -ne 'missing') {
                (Get-Item -LiteralPath (Join-Path $script:Fixture $ModuleFile)).LastWriteTime = $binaryTime.AddDays($Days)
            }

            & "Invoke-$($Name)Tool"

            Should -Invoke "Build-$($Name)Tool" -Exactly -Times ([int]($Age -eq 'newer'))
            $LASTEXITCODE | Should -Be 0
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

        It 'exits nonzero and preserves native build diagnostics through <Entry>' -ForEach @(
            @{ Entry = 'wrapper' }, @{ Entry = 'main' }
        ) {
            Set-Content -LiteralPath (Join-Path $script:Fixture 'go.sum') -Value ''
            Set-Content -LiteralPath $script:GoExe -Value "@echo off`r`necho fixture compilation failed 1>&2`r`nexit /b 7"
            $core = New-Item -ItemType Directory -Path (Join-Path $script:Fixture 'lib\core')
            Set-Content -LiteralPath (Join-Path $core.FullName 'common.ps1') -Value @'
function Initialize-WinMole { }
function Restore-WinMoleConsoleEncoding { }
function Clear-TempFiles { }
function Write-Info { param($Message) }
function Write-WinMoleError { param($Message) Write-Host $Message }
'@
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot "bin\$Name.ps1") -Destination $script:BIN_DIR
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'winmole.ps1') -Destination $script:Fixture
            $entryPoint = if ($Entry -eq 'main') { Join-Path $script:Fixture 'winmole.ps1' } else { Join-Path $script:BIN_DIR "$Name.ps1" }
            $shell = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } else { 'pwsh.exe' }
            $commandArguments = @('-NoProfile', '-NonInteractive', '-File', "`"$entryPoint`"")
            if ($Entry -eq 'main') { $commandArguments += $Name }
            if ($Name -eq 'analyze') { $commandArguments += "`"$script:Fixture`"" }
            $stderrPath = Join-Path $script:Fixture 'stderr.txt'
            $process = Start-Process -FilePath (Join-Path $PSHOME $shell) -ArgumentList $commandArguments `
                -WindowStyle Hidden -Wait -PassThru -RedirectStandardError $stderrPath `
                -RedirectStandardOutput (Join-Path $script:Fixture 'stdout.txt')
            $process.ExitCode | Should -Be 1
            Get-Content -LiteralPath $stderrPath -Raw | Should -Match 'fixture compilation failed'
        }
    }

    It 'keeps JSON stdout empty when <Name> dependency setup fails' -ForEach @(
        @{ Name = 'analyze' }, @{ Name = 'status' }
    ) {
        Set-Content -LiteralPath $script:GoExe -Value "@echo off`r`necho fixture dependency setup failed 1>&2`r`nexit /b 7"
        $core = New-Item -ItemType Directory -Path (Join-Path $script:Fixture 'lib\core')
        Set-Content -LiteralPath (Join-Path $core.FullName 'common.ps1') -Value 'function Restore-WinMoleConsoleEncoding { }'
        $entryPoint = Join-Path $script:BIN_DIR "$Name.ps1"
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot "bin\$Name.ps1") -Destination $entryPoint
        $shell = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } else { 'pwsh.exe' }
        $commandArguments = @('-NoProfile', '-NonInteractive', '-File', "`"$entryPoint`"", '-Json')
        if ($Name -eq 'analyze') { $commandArguments += @('-Path', "`"$script:Fixture`"") }
        $stderrPath = Join-Path $script:Fixture 'stderr.txt'
        $stdoutPath = Join-Path $script:Fixture 'stdout.txt'
        $process = Start-Process -FilePath (Join-Path $PSHOME $shell) -ArgumentList $commandArguments `
            -WindowStyle Hidden -Wait -PassThru -RedirectStandardError $stderrPath -RedirectStandardOutput $stdoutPath
        $process.ExitCode | Should -Be 1
        Get-Content -LiteralPath $stdoutPath -Raw | Should -BeNullOrEmpty
        Get-Content -LiteralPath $stderrPath -Raw | Should -Match 'fixture dependency setup failed'
        Get-Content -LiteralPath $stderrPath -Raw | Should -Match 'Dependency setup failed\.'
        Test-Path -LiteralPath (Join-Path $script:BIN_DIR "$Name.exe") | Should -BeFalse
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
            Set-Content -LiteralPath $script:GoExe -Value @'
@echo off
if "%1"=="build" (
    echo fixture compilation failed 1>&2
    exit /b 7
)
exit /b 0
'@
            Build-AllGo | Should -BeFalse
            $LASTEXITCODE | Should -Be 7
            (Get-Location).Path | Should -Be $script:OriginalLocation
            $ErrorActionPreference | Should -Be 'Stop'
        }

        It 'stops after failed mod <Stage> even if builds would succeed' -ForEach @(
            @{ Stage = 'tidy' }, @{ Stage = 'download' }
        ) {
            $nativeFixture = @'
@echo off
if "%1 %2"=="mod FAILSTAGE" (
    echo fixture dependency setup failed 1>&2
    exit /b 7
)
if "%1"=="build" echo fixture>"%~4"
exit /b 0
'@
            Set-Content -LiteralPath $script:GoExe -Value $nativeFixture.Replace('FAILSTAGE', $Stage)
            Build-AllGo | Should -BeFalse
            $LASTEXITCODE | Should -Be 7
            Test-Path -LiteralPath (Join-Path $script:BIN_DIR 'analyze.exe') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $script:BIN_DIR 'status.exe') | Should -BeFalse
            (Get-Location).Path | Should -Be $script:OriginalLocation
            $ErrorActionPreference | Should -Be 'Stop'
        }
    }
}
