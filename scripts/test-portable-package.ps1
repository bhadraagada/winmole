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

$windowsPowerShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$policy = & $windowsPowerShell -NoLogo -NoProfile -NonInteractive -Command Get-ExecutionPolicy
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the host Windows PowerShell policy.' }
Write-Host "Windows PowerShell execution policy: $policy"
if ($policy -eq 'Restricted') {
    throw 'The host policy blocks the packaged PowerShell entry point. No execution policy was changed.'
}

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

    Push-Location -LiteralPath $scan
    try {
        $helpText = & $resolved --help | Out-String
        if ($LASTEXITCODE -ne 0 -or $helpText -notmatch 'Windows System Maintenance Toolkit') {
            throw "Launcher help failed (execution policy: $policy)"
        }
        if ((Test-Path -LiteralPath (Join-Path $profileDir '.config/winmole')) -or
            (Test-Path -LiteralPath (Join-Path $profileDir '.cache/winmole'))) {
            throw 'Help unexpectedly initialized a user configuration or cache.'
        }

        $analyze = & $resolved analyze . --json | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'Launcher analyze failed.' }
        $report = ConvertFrom-Json -InputObject $analyze
        if ($report.total_bytes -ne 4 -or $report.partial -or @($report.entries).Count -ne 1 -or
            $report.entries[0].name -cne 'report [sample].txt') {
            throw 'Analyze did not resolve the caller working directory.'
        }

        $status = & $resolved status --json | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'Launcher status failed.' }
        if (-not (ConvertFrom-Json -InputObject $status).collected_at) {
            throw 'Status did not return a machine-readable snapshot.'
        }

        $stderr = Join-Path $fixture 'stderr.txt'
        $missing = & $resolved analyze 'missing [test] directory' --json 2>$stderr | Out-String
        if ($LASTEXITCODE -eq 0 -or $missing.Trim() -or
            (Get-Content -LiteralPath $stderr -Raw) -notmatch 'Not an existing directory') {
            throw 'The launcher did not preserve failure status, stdout, and stderr independently.'
        }
    }
    finally {
        Pop-Location
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
