#Requires -Version 5.1
#Requires -Modules Pester

Describe 'Analyzer JSON command' {
    BeforeAll {
        $root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
        $package = Join-Path $TestDrive 'package'
        New-Item -ItemType Directory -Path "$package\bin" -Force | Out-Null
        Copy-Item -LiteralPath "$root\lib" -Destination $package -Recurse
        Copy-Item -LiteralPath "$root\winmole.ps1" -Destination $package
        Copy-Item -LiteralPath "$root\bin\analyze.ps1" -Destination "$package\bin"
        Push-Location $root
        try {
            & go build -o "$package\bin\analyze.exe" ./cmd/analyze
            if ($LASTEXITCODE -ne 0) { throw 'Analyzer test build failed.' }
        }
        finally { Pop-Location }
        $shell = (Get-Process -Id $PID).Path
        $fixture = Join-Path $TestDrive 'data [1]'
        New-Item -ItemType Directory -Path $fixture | Out-Null
        [IO.File]::WriteAllText("$fixture\hello.txt", 'hello')
        $stdout = Join-Path $TestDrive 'stdout.txt'
        $stderr = Join-Path $TestDrive 'stderr.txt'
        $savedDebug = $env:WINMOLE_DEBUG
        $savedDryRun = $env:WINMOLE_DRY_RUN
        $env:WINMOLE_DEBUG = '1'
        $env:WINMOLE_DRY_RUN = '1'
    }

    AfterAll {
        $env:WINMOLE_DEBUG = $savedDebug
        $env:WINMOLE_DRY_RUN = $savedDryRun
    }

    It 'routes -Json through a source-free package with clean stdout' {
        $process = Start-Process -FilePath $shell -ArgumentList @('-NoProfile', '-File', "`"$package\winmole.ps1`"", 'analyze', "`"$fixture`"", '-Json') `
            -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $process.ExitCode | Should -Be 0
        $report = Get-Content -LiteralPath $stdout -Raw | ConvertFrom-Json
        $report.path | Should -Be $fixture
        $report.total_bytes | Should -Be 5
        $report.partial | Should -BeFalse
        @($report.entries).Count | Should -Be 1
        $report.entries[0].name | Should -Be 'hello.txt'
        [IO.File]::ReadAllText("$fixture\hello.txt") | Should -Be 'hello'
        Get-Content -LiteralPath $stderr -Raw | Should -BeNullOrEmpty
    }

    It 'returns nonzero and stderr for an invalid directory' {
        $process = Start-Process -FilePath $shell -ArgumentList @('-NoProfile', '-File', "`"$package\winmole.ps1`"", 'analyze', "`"$fixture\hello.txt`"", '-Json') `
            -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $process.ExitCode | Should -Not -Be 0
        Get-Content -LiteralPath $stdout -Raw | Should -BeNullOrEmpty
        Get-Content -LiteralPath $stderr -Raw | Should -Match 'Not an existing directory'
    }

    It 'rebuilds changed report source without contaminating JSON stdout' {
        Copy-Item -LiteralPath "$root\cmd" -Destination $package -Recurse
        Copy-Item -LiteralPath "$root\go.mod", "$root\go.sum" -Destination $package
        (Get-Item -LiteralPath "$package\cmd\analyze\report.go").LastWriteTime = (Get-Date).AddMinutes(1)
        $process = Start-Process -FilePath $shell -ArgumentList @('-NoProfile', '-File', "`"$package\winmole.ps1`"", 'analyze', "`"$fixture`"", '-Json') `
            -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $process.ExitCode | Should -Be 0
        $report = Get-Content -LiteralPath $stdout -Raw | ConvertFrom-Json
        $report.total_bytes | Should -Be 5
        Get-Content -LiteralPath $stderr -Raw | Should -Match 'Build complete'
    }
}
