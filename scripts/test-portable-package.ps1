#Requires -Version 7.0
param(
    [Parameter(Mandatory)]
    [string]$Archive
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (-not $IsWindows) { throw 'Portable launcher smoke tests require Windows.' }
if ($env:PSExecutionPolicyPreference) {
    throw 'A process-level PowerShell policy is set. Run the smoke test without a policy override.'
}

function Invoke-PackageFixture {
    param([string]$Executable, [string]$WorkingDirectory, [string[]]$Arguments)

    $start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $process.StandardInput.Close()
        $out = $process.StandardOutput.ReadToEndAsync()
        $err = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(45000)) {
            # Kill only the process tree started by this test, never an external process.
            if (-not $process.HasExited) { $process.Kill($true) }
            throw "WinMole timed out for arguments: $Arguments"
        }
        return @{
            ExitCode = $process.ExitCode
            Stdout = $out.GetAwaiter().GetResult()
            Stderr = $err.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

$windowsPowerShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$policy = & $windowsPowerShell -NoLogo -NoProfile -NonInteractive -Command Get-ExecutionPolicy
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the host Windows PowerShell policy.' }
Write-Host "Windows PowerShell execution policy: $policy"
$archivePath = (Resolve-Path -LiteralPath $Archive).ProviderPath
$fixture = (New-Item -ItemType Directory -Path (
    Join-Path ([IO.Path]::GetTempPath()) ("WinMole package test " + [guid]::NewGuid()))).FullName
$oldPath, $oldProfile = $env:PATH, $env:USERPROFILE
try {
    $package = Join-Path $fixture 'package with spaces'
    Expand-Archive -LiteralPath $archivePath -DestinationPath $package
    $launcher = Join-Path $package 'winmole.exe'
    $scan = (New-Item -ItemType Directory -Path (Join-Path $fixture 'outside package')).FullName
    $profileDir = (New-Item -ItemType Directory -Path (Join-Path $fixture 'temporary profile')).FullName
    $links = (New-Item -ItemType Directory -Path (Join-Path $fixture 'command aliases')).FullName
    $aliasPath = Join-Path $links 'winmole.exe'
    $null = New-Item -ItemType SymbolicLink -Path $aliasPath -Target $launcher
    [IO.File]::WriteAllBytes((Join-Path $scan 'report [sample].txt'), [byte[]]@(1, 2, 3, 4))

    # Model WinGet's alias with a separate directory; do not edit persistent PATH
    # or allow source builds of missing helpers to hide packaging regressions.
    $env:PATH = "$links;$env:SystemRoot\System32;$env:SystemRoot"
    $env:USERPROFILE = $profileDir
    $resolved = (Get-Command winmole.exe -CommandType Application).Source
    if ($resolved -ne $aliasPath) { throw "Wrong executable resolved through PATH: $resolved" }

    $help = Invoke-PackageFixture -Executable $resolved -WorkingDirectory $scan -Arguments '--help'
    if ($help.ExitCode -ne 0 -or $help.Stdout -notmatch 'Windows System Maintenance Toolkit') {
        throw "Launcher help failed (execution policy: $policy): $($help.Stderr)"
    }
    $version = Invoke-PackageFixture -Executable $resolved -WorkingDirectory $scan -Arguments '--version'
    if ($version.ExitCode -ne 0 -or $version.Stdout -notmatch '^WinMole v[0-9]+\.[0-9]+\.[0-9]+\s*$') {
        throw "Launcher version failed: $($version.Stderr)"
    }
    if ((Test-Path -LiteralPath (Join-Path $profileDir '.config/winmole')) -or
        (Test-Path -LiteralPath (Join-Path $profileDir '.cache/winmole'))) {
        throw 'Help or version unexpectedly initialized a user configuration or cache.'
    }

    if ($policy -eq 'Restricted') {
        throw 'Native help and version passed, but host policy blocks the packaged PowerShell commands. No execution policy was changed.'
    }

    $analyze = Invoke-PackageFixture -Executable $resolved -WorkingDirectory $scan -Arguments 'analyze', '.', '--json'
    if ($analyze.ExitCode -ne 0) { throw "Launcher analyze failed: $($analyze.Stderr)" }
    $report = ConvertFrom-Json -InputObject $analyze.Stdout
    if ($report.total_bytes -ne 4 -or $report.partial -or @($report.entries).Count -ne 1 -or
        $report.entries[0].name -cne 'report [sample].txt') {
        throw 'Analyze did not resolve the caller working directory.'
    }

    $status = Invoke-PackageFixture -Executable $resolved -WorkingDirectory $scan -Arguments 'status', '--json'
    if ($status.ExitCode -ne 0) { throw "Launcher status failed: $($status.Stderr)" }
    if (-not (ConvertFrom-Json -InputObject $status.Stdout).collected_at) {
        throw 'Status did not return a machine-readable snapshot.'
    }

    $missing = Invoke-PackageFixture -Executable $resolved -WorkingDirectory $scan -Arguments 'analyze', 'missing [test] directory', '--json'
    if ($missing.ExitCode -eq 0 -or $missing.Stdout.Trim() -or $missing.Stderr -notmatch 'Not an existing directory') {
        throw 'The launcher did not preserve failure status, stdout, and stderr independently.'
    }
}
finally {
    $env:PATH, $env:USERPROFILE = $oldPath, $oldProfile
    # Delete only the newly created fixture. Remove its alias before cleanup.
    if ($aliasPath -and (Get-Item -LiteralPath $aliasPath -ErrorAction SilentlyContinue)) {
        [IO.File]::Delete($aliasPath)
    }
    [IO.Directory]::Delete($fixture, $true)
}
