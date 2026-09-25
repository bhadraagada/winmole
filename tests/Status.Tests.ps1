#Requires -Version 5.1
#Requires -Modules Pester

Describe 'Status JSON command' {
    BeforeAll {
        $root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
        $package = Join-Path $TestDrive 'package'
        New-Item -ItemType Directory -Path "$package\bin" -Force | Out-Null
        Copy-Item -LiteralPath "$root\lib" -Destination $package -Recurse
        Copy-Item -LiteralPath "$root\winmole.ps1" -Destination $package
        Copy-Item -LiteralPath "$root\bin\status.ps1" -Destination "$package\bin"
        Push-Location $root
        try {
            & go build -o "$package\bin\status.exe" ./cmd/status
            if ($LASTEXITCODE -ne 0) { throw 'Status test build failed.' }
        }
        finally { Pop-Location }
        $shell = (Get-Process -Id $PID).Path
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

    It 'prints one JSON snapshot without a terminal from the standalone binary' {
        $process = Start-Process -FilePath "$package\bin\status.exe" -ArgumentList '-json' `
            -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $process.ExitCode | Should -Be 0
        $report = Get-Content -LiteralPath $stdout -Raw | ConvertFrom-Json
        @($report).Count | Should -Be 1
        $report.collected_at | Should -Not -BeNullOrEmpty
        $report.cpu.available | Should -BeOfType ([bool])
        $report.memory.available | Should -BeOfType ([bool])
        $report.swap.available | Should -BeOfType ([bool])
        $report.disks_complete | Should -BeOfType ([bool])
        if ($report.health.available) {
            $report.health.score | Should -BeGreaterOrEqual 0
        }
        else { $report.health.score | Should -BeNullOrEmpty }
        Get-Content -LiteralPath $stderr -Raw | Should -BeNullOrEmpty
    }

    It 'routes -Json through a source-free <Entry> with clean stdout' -ForEach @(
        @{ Entry = 'main command'; Script = 'winmole.ps1'; Command = @('status') },
        @{ Entry = 'status wrapper'; Script = 'bin\status.ps1'; Command = @() }
    ) {
        $commandArguments = @('-NoProfile', '-NonInteractive', '-File', "`"$package\$Script`"") + $Command + @('-Json')
        $process = Start-Process -FilePath $shell -ArgumentList $commandArguments `
            -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $process.ExitCode | Should -Be 0
        $report = Get-Content -LiteralPath $stdout -Raw | ConvertFrom-Json
        $report.collected_at | Should -Not -BeNullOrEmpty
        $report.health.message | Should -Not -BeNullOrEmpty
        Get-Content -LiteralPath $stderr -Raw | Should -BeNullOrEmpty
    }

    It 'rejects unexpected binary arguments with stderr and no report' {
        $process = Start-Process -FilePath "$package\bin\status.exe" -ArgumentList @('-json', 'unexpected') `
            -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $process.ExitCode | Should -Not -Be 0
        Get-Content -LiteralPath $stdout -Raw | Should -BeNullOrEmpty
        Get-Content -LiteralPath $stderr -Raw | Should -Match 'does not accept positional arguments'
    }

    It 'propagates a failed status executable through the main launcher' {
        $failedPackage = Join-Path $TestDrive 'failed-package'
        New-Item -ItemType Directory -Path "$failedPackage\bin" | Out-Null
        Copy-Item -LiteralPath "$root\lib" -Destination $failedPackage -Recurse
        Copy-Item -LiteralPath "$root\winmole.ps1" -Destination $failedPackage
        Copy-Item -LiteralPath "$root\bin\status.ps1" -Destination "$failedPackage\bin"
        $failedSource = Join-Path $TestDrive 'failed.go'
        Set-Content -LiteralPath $failedSource -Value 'package main; import "os"; func main() { os.Stderr.WriteString("fixture status failed\n"); os.Exit(7) }'
        & go build -o "$failedPackage\bin\status.exe" $failedSource
        if ($LASTEXITCODE -ne 0) { throw 'Failed status fixture build failed.' }
        $process = Start-Process -FilePath $shell -ArgumentList @('-NoProfile', '-NonInteractive', '-File', "`"$failedPackage\winmole.ps1`"", 'status', '-Json') `
            -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $process.ExitCode | Should -Not -Be 0
        Get-Content -LiteralPath $stdout -Raw | Should -BeNullOrEmpty
        Get-Content -LiteralPath $stderr -Raw | Should -Match 'fixture status failed'
        Get-Content -LiteralPath $stderr -Raw | Should -Match 'exit code 7'
    }

    It 'rebuilds changed report source without contaminating JSON stdout' {
        Copy-Item -LiteralPath "$root\cmd" -Destination $package -Recurse
        Copy-Item -LiteralPath "$root\go.mod", "$root\go.sum" -Destination $package
        (Get-Item -LiteralPath "$package\cmd\status\report.go").LastWriteTime = (Get-Date).AddMinutes(1)
        $process = Start-Process -FilePath $shell -ArgumentList @('-NoProfile', '-NonInteractive', '-File', "`"$package\winmole.ps1`"", 'status', '-Json') `
            -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $process.ExitCode | Should -Be 0
        $report = Get-Content -LiteralPath $stdout -Raw | ConvertFrom-Json
        $report.collected_at | Should -Not -BeNullOrEmpty
        Get-Content -LiteralPath $stderr -Raw | Should -Match 'Build complete'
    }
}
