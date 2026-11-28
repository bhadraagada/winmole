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
    param(
        [string]$Executable, [string]$WorkingDirectory, [string[]]$Arguments,
        [hashtable]$Environment = @{}
    )

    $start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    foreach ($name in $Environment.Keys) {
        if ($null -eq $Environment[$name]) { $null = $start.Environment.Remove($name) }
        else { $start.Environment[$name] = $Environment[$name] }
    }
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

function Assert-CleanPreviewPreservesFixture {
    param([string]$Package, [string]$Alias, [string]$PowerShell, [string]$Fixture)

    $cleanFixture = (New-Item -ItemType Directory -Path (Join-Path $Fixture 'isolated cleanup profile')).FullName
    $local = (New-Item -ItemType Directory -Path (Join-Path $cleanFixture 'Local')).FullName
    $roaming = (New-Item -ItemType Directory -Path (Join-Path $cleanFixture 'Roaming')).FullName
    $temp = (New-Item -ItemType Directory -Path (Join-Path $cleanFixture 'Temp')).FullName
    $cache = (New-Item -ItemType Directory -Path (Join-Path $local 'D3DSCache')).FullName
    $sentinel = Join-Path $cache 'fixture-only.bin'
    $router = Join-Path $Package 'winmole.ps1'
    $clean = Join-Path $Package 'bin/clean.ps1'
    $base = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File')
    $envOnly = @{
        USERPROFILE = $cleanFixture
        LOCALAPPDATA = $local
        APPDATA = $roaming
        TEMP = $temp
        TMP = $temp
        WINMOLE_DRY_RUN = $null
    }
    $cases = @(
        @{ Name = 'portable launcher'; Exe = (Join-Path $Package 'winmole.exe'); Args = @('clean', '-DryRun', '-GPUShaders') }
        @{ Name = 'portable alias'; Exe = $Alias; Args = @('clean', '--dry-run', '-GPUShaders') }
        @{ Name = 'PowerShell router'; Exe = $PowerShell; Args = $base + @($router, 'clean', '-DryRun', '-GPUShaders') }
        @{ Name = 'PowerShell router alias'; Exe = $PowerShell; Args = $base + @($router, 'clean', '--dry-run', '-GPUShaders') }
        @{ Name = 'PowerShell clean command'; Exe = $PowerShell; Args = $base + @($clean, '-DryRun', '-GPUShaders') }
        @{ Name = 'environment preview'; Exe = (Join-Path $Package 'winmole.exe'); Args = @('clean', '-GPUShaders'); EnvSwitch = $true }
    )
    foreach ($case in $cases) {
        [IO.File]::WriteAllBytes($sentinel, [byte[]]@(1, 2, 3, 4))
        $before = (Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash
        $childEnv = $envOnly.Clone()
        if ($case.EnvSwitch) { $childEnv.WINMOLE_DRY_RUN = '1' }
        $result = Invoke-PackageFixture -Executable $case.Exe -WorkingDirectory $cleanFixture -Arguments $case.Args -Environment $childEnv
        Write-Host "Clean preview ($($case.Name)), exit $($result.ExitCode):"
        Write-Host $result.Stdout
        if ($result.Stderr) { Write-Host $result.Stderr }
        if (-not (Test-Path -LiteralPath $sentinel -PathType Leaf) -or
            (Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash -cne $before) {
            throw "Clean preview altered the fixture sentinel ($($case.Name))."
        }
        if ($result.ExitCode -ne 0 -or $result.Stderr.Trim() -or
            $result.Stdout -notmatch 'DRY RUN MODE' -or
            $result.Stdout -notmatch '(?m)DirectX shader cache[^\r\n]*1 items, 4 B dry' -or
            $result.Stdout -notmatch 'Would clean') {
            throw "Clean preview did not report the expected disposable GPU cache item ($($case.Name))."
        }
        Write-Host "Clean preview preserved exact SHA256 and reported the cache item ($($case.Name))."
    }
}

function Assert-AnalyzerReasonParity {
    param(
        [string]$Launcher,
        [string]$Analyzer,
        [string]$ScanRoot,
        [string]$UnreadableName
    )

    $direct = Invoke-PackageFixture -Executable $Analyzer -WorkingDirectory $ScanRoot -Arguments '-json', '-path', $ScanRoot
    $packaged = Invoke-PackageFixture -Executable $Launcher -WorkingDirectory $ScanRoot -Arguments 'analyze', $ScanRoot, '--json'
    if ($direct.ExitCode -ne 0 -or $packaged.ExitCode -ne 0 -or
        $direct.Stderr.Trim() -or $packaged.Stderr.Trim() -or $direct.Stdout.Trim() -cne $packaged.Stdout.Trim()) {
        throw "Direct and portable analyzer reports differ: $($direct.Stderr) $($packaged.Stderr)"
    }

    $report = ConvertFrom-Json -InputObject $packaged.Stdout -AsHashtable
    if ($UnreadableName) {
        if ($report.partial -ne $true -or -not $report.Contains('partial_reasons') -or
            @($report.partial_reasons).Count -ne 1 -or $report.partial_reasons[0] -cne 'read_error') {
            throw 'Partial report did not emit exactly the expected stable read_error reason.'
        }
    }
    elseif ($report.partial -ne $false -or $report.Contains('partial_reasons')) {
        throw 'Complete report did not omit partial_reasons.'
    }

    $matchedUnreadable = 0
    $matchedComplete = 0
    foreach ($entry in $report.entries) {
        if ($UnreadableName -and $entry.name -ceq $UnreadableName) {
            $matchedUnreadable++
            if ($entry.partial -ne $true -or -not $entry.Contains('partial_reasons') -or
                @($entry.partial_reasons).Count -ne 1 -or $entry.partial_reasons[0] -cne 'read_error') {
                throw 'Unreadable entry did not emit exactly the expected stable read_error reason.'
            }
        }
        else {
            $matchedComplete++
            if ($entry.partial -ne $false -or $entry.Contains('partial_reasons')) {
                throw 'A complete entry incorrectly emitted partial_reasons.'
            }
        }
    }
    $expectedUnreadable = if ($UnreadableName) { 1 } else { 0 }
    if ($matchedUnreadable -ne $expectedUnreadable -or $matchedComplete -ne 1) {
        throw 'Analyzer fixture entry coverage is incomplete.'
    }
}

$windowsPowerShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
function Read-PowerShellPolicy {
    param([string]$Expression)
    $result = & $windowsPowerShell -NoLogo -NoProfile -NonInteractive -Command $Expression
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read the host Windows PowerShell policy.' }
    return ($result | Out-String).Trim()
}
$policy = Read-PowerShellPolicy 'Get-ExecutionPolicy'
$allPolicyScopes = Read-PowerShellPolicy 'Get-ExecutionPolicy -List | ConvertTo-Json -Compress'
Write-Host "Windows PowerShell execution policy: $policy"
$archivePath = (Resolve-Path -LiteralPath $Archive).ProviderPath
$fixture = (New-Item -ItemType Directory -Path (
    Join-Path ([IO.Path]::GetTempPath()) ("WinMole package test " + [guid]::NewGuid()))).FullName
$oldPath, $oldProfile, $oldAnalyzePath = $env:PATH, $env:USERPROFILE, $env:WINMOLE_ANALYZE_PATH
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
    $env:WINMOLE_ANALYZE_PATH = $profileDir
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

    # Capture matching legacy behavior, without changing host policy. The
    # legacy mode is not expected to work under Restricted policy.
    $script = Join-Path $package 'winmole.ps1'
    $legacy = $null
    $legacyMissing = $null
    if ($policy -ne 'Restricted') {
        $env:USERPROFILE = (New-Item -ItemType Directory -Path (
            Join-Path $fixture 'legacy temporary profile')).FullName
        try {
            Assert-CleanPreviewPreservesFixture -Package $package -Alias $resolved -PowerShell $windowsPowerShell -Fixture $fixture
            $legacy = Invoke-PackageFixture -Executable $windowsPowerShell -WorkingDirectory $scan -Arguments (
                '-NoLogo', '-NoProfile', '-File', $script, 'AnAlYzE', '.', '-JsOn')
            if ($legacy.ExitCode -ne 0) { throw "Legacy analyzer baseline failed: $($legacy.Stderr)" }
            $legacyMissing = Invoke-PackageFixture -Executable $windowsPowerShell -WorkingDirectory $scan -Arguments (
                '-NoLogo', '-NoProfile', '-File', $script, 'analyze', 'missing [test] directory', '--json')
            $legacyHelp = Invoke-PackageFixture -Executable $resolved -WorkingDirectory $scan -Arguments 'status', '-Help', '--json'
            if ($legacyHelp.ExitCode -ne 0 -or $legacyHelp.Stdout -notmatch 'Real-time System Monitor') {
                throw "Subcommand help stopped using the legacy help route: $($legacyHelp.Stderr)"
            }
        }
        finally {
            $env:USERPROFILE = $profileDir
        }
    }

    # Make the scripts physically unavailable. This proves the native report
    # route does not rely on a permissive policy, without altering any policy.
    foreach ($path in @('winmole.ps1', 'bin/analyze.ps1', 'bin/status.ps1')) {
        $source = Join-Path $package $path
        Move-Item -LiteralPath $source -Destination ($source + '.held-for-test')
    }

    $analyze = Invoke-PackageFixture -Executable $resolved -WorkingDirectory $scan -Arguments 'AnAlYzE', '-JsOn'
    if ($analyze.ExitCode -ne 0) { throw "Native default-directory analyze failed: $($analyze.Stderr)" }
    $report = ConvertFrom-Json -InputObject $analyze.Stdout
    if ($report.path -ne $scan -or $report.total_bytes -ne 4 -or $report.partial -or
        @($report.entries).Count -ne 1 -or $report.entries[0].name -cne 'report [sample].txt') {
        throw 'Native analyze did not resolve the caller working directory.'
    }
    if ($legacy -and $legacy.Stdout.Trim() -cne $analyze.Stdout.Trim()) {
        throw 'Native default-directory JSON does not match legacy explicit-dot JSON.'
    }

    $directAnalyzer = Join-Path $package 'bin/analyze.exe'
    Assert-AnalyzerReasonParity -Launcher $resolved -Analyzer $directAnalyzer -ScanRoot $scan

    # The deliberately dangling junction provides read_error deterministically,
    # without demoting ACLs or waiting on timeouts. Its target never exists.
    $partialRoot = (New-Item -ItemType Directory -Path (Join-Path $fixture 'partial fixture')).FullName
    $danglingName = 'missing-target'
    $junction = Join-Path $partialRoot $danglingName
    $doesNotExist = Join-Path $fixture 'uncreated junction target'
    $commandPrompt = Join-Path ([Environment]::SystemDirectory) 'cmd.exe'
    [IO.File]::WriteAllBytes((Join-Path $partialRoot 'complete.txt'), [byte[]]@(1))
    $created = Invoke-PackageFixture -Executable $commandPrompt -WorkingDirectory $partialRoot -Arguments (
        '/d', '/c', 'mklink', '/J', $junction, $doesNotExist)
    if ($created.ExitCode -ne 0) {
        throw "Could not create the dangling-junction fixture: $($created.Stdout) $($created.Stderr)"
    }
    try {
        Assert-AnalyzerReasonParity -Launcher $resolved -Analyzer $directAnalyzer -ScanRoot $partialRoot -UnreadableName $danglingName
    }
    finally {
        # Remove the fixture junction itself, never the target or a tree below it.
        [IO.Directory]::Delete($junction, $false)
    }
    Write-Host 'Direct and portable analyzer JSON preserve partial reasons and complete-scan omissions.'

    $relativePath = '..\Sibling [Ω] & space'
    $sibling = (New-Item -ItemType Directory -Path (Join-Path $fixture 'Sibling [Ω] & space')).FullName
    [IO.File]::WriteAllBytes((Join-Path $sibling 'another [test].txt'), [byte[]]@(1, 2, 3))
    foreach ($analyzeArgs in @(
        @{ Arguments = @('analyze', $relativePath, '--json') },
        @{ Arguments = @('analyze', '--Json', ('-PaTh:' + $relativePath)) }
    )) {
        $relative = Invoke-PackageFixture -Executable $resolved -WorkingDirectory $scan -Arguments $analyzeArgs.Arguments
        if ($relative.ExitCode -ne 0) { throw "Native relative-path analyze failed: $($relative.Stderr)" }
        $relativeReport = ConvertFrom-Json -InputObject $relative.Stdout
        if ($relativeReport.path -ne $sibling -or $relativeReport.total_bytes -ne 3) {
            throw 'Native analyze changed path argument boundaries or resolution.'
        }
    }

    $status = Invoke-PackageFixture -Executable $resolved -WorkingDirectory $scan -Arguments 'StAtUs', '--JSON'
    if ($status.ExitCode -ne 0) { throw "Native status failed: $($status.Stderr)" }
    if (-not (ConvertFrom-Json -InputObject $status.Stdout).collected_at) {
        throw 'Native status did not return a machine-readable snapshot.'
    }

    $missing = Invoke-PackageFixture -Executable $resolved -WorkingDirectory $scan -Arguments 'analyze', 'missing [test] directory', '--json'
    if ($missing.ExitCode -ne 1 -or $missing.Stdout.Trim() -or $missing.Stderr -notmatch 'Not an existing directory') {
        throw 'Native analyze changed the failure status, stdout, or stderr contract.'
    }
    if ($legacyMissing -and ($legacyMissing.ExitCode -ne $missing.ExitCode -or
        $legacyMissing.Stdout.Trim() -cne $missing.Stdout.Trim() -or
        $legacyMissing.Stderr.Trim() -cne $missing.Stderr.Trim())) {
        throw 'Native invalid-path failure differs from the legacy result.'
    }

    # With the legacy entry unavailable, ambiguous or interactive calls must
    # fail there, not silently become read-only reports.
    foreach ($case in @(
        @{ Arguments = @('analyze', '.') },
        @{ Arguments = @('analyze', '.', '--json', '--delete') },
        @{ Arguments = @('status', '--json', '--help') },
        @{ Arguments = @('status', '--json=false') },
        @{ Arguments = @('clean', '--json') }
    )) {
        $refused = Invoke-PackageFixture -Executable $resolved -WorkingDirectory $scan -Arguments $case.Arguments
        if ($refused.ExitCode -ne 1 -or $refused.Stdout.Trim() -or
            $refused.Stderr -notmatch 'the WinMole script is missing or invalid') {
            throw "A non-native command did not reach the legacy launcher: $($case.Arguments)"
        }
    }

    $helper = Join-Path $package 'bin/status.exe'
    # A usable copy on PATH must not mask a broken portable package.
    Copy-Item -LiteralPath $helper -Destination (Join-Path $links 'status.exe')
    Move-Item -LiteralPath $helper -Destination ($helper + '.held-for-test')
    $missingHelper = Invoke-PackageFixture -Executable $resolved -WorkingDirectory $scan -Arguments 'status', '--json'
    if ($missingHelper.ExitCode -ne 1 -or $missingHelper.Stdout.Trim() -or
        $missingHelper.Stderr -notmatch 'the bundled status.exe is missing or invalid') {
        throw 'The native report did not fail closed when its bundled helper was missing.'
    }
    if ((Test-Path -LiteralPath (Join-Path $profileDir '.config/winmole')) -or
        (Test-Path -LiteralPath (Join-Path $profileDir '.cache/winmole'))) {
        throw 'A read-only command unexpectedly initialized a user configuration or cache.'
    }
    Write-Host 'Native reports work with all report scripts unavailable.'

    if ($policy -eq 'Restricted') {
        throw 'Native reports passed, but host policy blocks the remaining legacy commands. No execution policy was changed.'
    }
}
finally {
    $env:PATH, $env:USERPROFILE, $env:WINMOLE_ANALYZE_PATH = $oldPath, $oldProfile, $oldAnalyzePath
    # Delete only the newly created fixture. Remove its alias before cleanup.
    if ($aliasPath -and (Get-Item -LiteralPath $aliasPath -ErrorAction SilentlyContinue)) {
        [IO.File]::Delete($aliasPath)
    }
    [IO.Directory]::Delete($fixture, $true)
    if ((Read-PowerShellPolicy 'Get-ExecutionPolicy -List | ConvertTo-Json -Compress') -cne $allPolicyScopes) {
        throw 'Windows PowerShell execution policy scopes changed during the package fixture.'
    }
    Write-Host 'All Windows PowerShell execution policy scopes unchanged.'
}
