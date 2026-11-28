# Temporary hosted QA only. No publication, PowerShell policy changes, external server, or cleanup apply.
#Requires -Version 7.0
param([Parameter(Mandatory)][string]$Winget, [Parameter(Mandatory)][string]$Candidate)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_ARCH -ne 'X64') {
    throw 'This probe only runs on the intended disposable GitHub x64 runner.'
}
$expected = @{
    '0.1.2' = '03d6de7eb59c1a59c29067abdd7036c5c164dad933de4781ce57e96c2f3bd738'
}
$packageId = 'BhadraGada.WinMole'
function Invoke-WinGetChecked {
    $output = & $Winget @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "winget $($args -join ' ') -> ${LASTEXITCODE}: $($output -join "`n")" }
    $output
}
function WinGetSettings {
    (Invoke-WinGetChecked settings export | Out-String | ConvertFrom-Json -AsHashtable).adminSettings
}
$pwsh = Join-Path $PSHOME 'pwsh.exe'
function InstalledCommands {
    # A new process inherits stale CI PATH, so reconstruct it from persisted
    # values inside the fresh no-profile process before checking resolution.
    & $pwsh -NoLogo -NoProfile -NonInteractive -Command {
        $env:Path = "$([Environment]::GetEnvironmentVariable('Path', 'Machine'));$([Environment]::GetEnvironmentVariable('Path', 'User'))"
        Get-Command winmole.exe -All -CommandType Application -ErrorAction SilentlyContinue | ForEach-Object Source
        exit 0
    }
    if ($LASTEXITCODE -ne 0) { throw 'Fresh process failed to inspect persisted PATH' }
}
function PortableRegistration {
    Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
        Where-Object PSChildName -like "$packageId*" |
        Get-ItemProperty
}
function Resolve-Installed($version, $expectedExeSha) {
    $commands = @(InstalledCommands)
    if ($commands.Count -ne 1) { throw 'Expected only one winmole.exe on persisted PATH' }
    $alias = $commands[0]
    $redirect = [IO.File]::ResolveLinkTarget($alias, $true)
    $real = if ($redirect) { $redirect.FullName } else { $alias }
    if (-not $real.StartsWith("$($env:LOCALAPPDATA)\Microsoft\WinGet\Packages\", [StringComparison]::OrdinalIgnoreCase)) {
        throw 'PATH resolves outside the intended per-user WinGet install root'
    }
    if ((Get-FileHash -LiteralPath $real).Hash -ne $expectedExeSha) { throw 'Installed user command does not match the ZIP launcher bytes' }
    $zone = Get-Content -LiteralPath $real -Stream Zone.Identifier -ErrorAction SilentlyContinue | Where-Object { $_ -match '^ZoneId=\d+$' }
    Write-Host "Loopback-installed executable ZoneIdentifier: $(if ($zone) { $zone } else { 'absent' })"
    $script = Join-Path (Split-Path -Parent $real) 'winmole.ps1'
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw 'Packaged legacy companion missing from installed files' }
    $scriptZone = Get-Content -LiteralPath $script -Stream Zone.Identifier -ErrorAction SilentlyContinue | Where-Object { $_ -match '^ZoneId=\d+$' }
    Write-Host "Loopback-installed companion script ZoneIdentifier: $(if ($scriptZone) { $scriptZone } else { 'absent' })"
    $observedVersion = & $alias --version
    if ($LASTEXITCODE -ne 0 -or $observedVersion -cne "WinMole v$version") { throw "Wrong installed version: $observedVersion" }
    $report = & $alias analyze . --json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $report.path -cne (Get-Location).ProviderPath -or
        $report.partial -ne $false -or $report.total_bytes -ne 4 -or $report.entries.Count -ne 1 -or
        $report.entries[0].name -cne 'input.bin') { throw 'Installed analyzer failed outside its package root' }
    $stats = & $alias status --json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $null -eq $stats) { throw 'Installed status native report failed' }
    $registration = @(PortableRegistration)
    if ($registration.Count -ne 1 -or $registration[0].DisplayVersion -cne $version) { throw 'Expected one exact user-scope WinGet registration' }
    Write-Host "Verified Windows PATH alias, exe digest, reports and registration for $version"
    return $real
}
function Export-QAManifest($version, $sha, $url) {
    $dest = Join-Path $testRoot "manifest-$version"
    $null = New-Item -ItemType Directory -Path $dest
    $common = @"
PackageIdentifier: $packageId
PackageVersion: $version
ManifestVersion: 1.6.0
"@
    $versionDoc = @'
DefaultLocale: en-US
ManifestType: version
'@
    $localeDoc = @'
PackageLocale: en-US
Publisher: Bhadra Gada
PackageName: WinMole
License: GPL-3.0
ShortDescription: Windows maintenance toolkit
ManifestType: defaultLocale
'@
    $installerDoc = @"
InstallerType: zip
NestedInstallerType: portable
NestedInstallerFiles:
- RelativeFilePath: winmole.exe
  PortableCommandAlias: winmole
Installers:
- Architecture: x64
  InstallerUrl: $url
  InstallerSha256: $sha
ManifestType: installer
"@
    Set-Content -LiteralPath (Join-Path $dest "$packageId.yaml") -Value "$common`n$versionDoc" -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $dest "$packageId.locale.en-US.yaml") -Value "$common`n$localeDoc" -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $dest "$packageId.installer.yaml") -Value "$common`n$installerDoc" -Encoding utf8NoBOM
    Invoke-WinGetChecked validate --manifest $dest | Write-Host
    return $dest
}
function Stage-Archive($version, $source) {
    if ((Get-FileHash -LiteralPath $source).Hash -ne $expected[$version]) { throw "Wrong exact $version installer bytes" }
    $leaf = "winmole-$version-windows-amd64.zip"
    Copy-Item -LiteralPath $source -Destination (Join-Path $serve $leaf)
    $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $serve $leaf))
    try {
        $stream = $zip.GetEntry('winmole.exe').Open()
        try {
            $binaryHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))
        } finally { $stream.Dispose() }
    } finally { $zip.Dispose() }
    @{ Leaf = $leaf; Hash = $binaryHash }
}

if (@(InstalledCommands).Count -or @(PortableRegistration).Count) {
    throw 'WinMole already present on unexpected test base'
}
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$policyBefore = & $ps51 -NoLogo -NoProfile -NonInteractive -Command 'Get-ExecutionPolicy; Get-ExecutionPolicy -List | ConvertTo-Json -Compress'
$initial = WinGetSettings
function Source-Snapshot {
    Invoke-WinGetChecked source export | Where-Object { $_ -match '^\s*\{' } | ForEach-Object {
        $_ | ConvertFrom-Json -AsHashtable
    }
}
$stock = @{
    msstore = 'https://storeedgefd.dsx.mp.microsoft.com/v9.0'
    winget = 'https://cdn.winget.microsoft.com/cache'
    'winget-font' = 'https://cdn.winget.microsoft.com/fonts'
}
$sourceBaseline = @(Source-Snapshot)
if ('msstore' -notin $sourceBaseline.Name -or 'winget' -notin $sourceBaseline.Name -or
    @($sourceBaseline | Where-Object { -not $stock.ContainsKey($_.Name) -or $stock[$_.Name] -ne $_.Arg }).Count) {
    throw 'Refusing to alter a disposable host without the stock WinGet source configuration'
}
$sourceFingerprint = $sourceBaseline | Sort-Object Name | ConvertTo-Json -Depth 5 -Compress
if ($initial.LocalManifestFiles -isnot [bool]) { throw 'Could not determine initial WinGet-only LocalManifestFiles setting' }
$testRoot = Join-Path $env:RUNNER_TEMP ("WinMole WinGet Lifecycle " + [guid]::NewGuid().ToString('N'))
$serve = Join-Path $testRoot 'serve only exact ZIPs'
$null = New-Item -ItemType Directory -Path $testRoot
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
[IO.File]::WriteAllText((Join-Path $testRoot 'before-machine-path.txt'), $machinePath)
[IO.File]::WriteAllText((Join-Path $testRoot 'before-user-path.txt'), $userPath)
$fixture = Join-Path $testRoot 'scan workdir'
$null = New-Item -ItemType Directory -Path $serve,$fixture
[IO.File]::WriteAllBytes((Join-Path $fixture 'input.bin'), [byte[]](1,2,3,4))
$new = Stage-Archive '0.1.2' $Candidate
$httpScript = Join-Path $testRoot 'loopback.py'
$portPath = Join-Path $testRoot 'port.txt'
$env:WINGET_QA_PORT_FILE = $portPath
$env:WINGET_QA_SERVE_DIR = $serve
@'
from functools import partial
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from os import environ
from pathlib import Path

handler = partial(SimpleHTTPRequestHandler, directory=environ["WINGET_QA_SERVE_DIR"])
with ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
    port = Path(environ["WINGET_QA_PORT_FILE"])
    temp = port.with_suffix(".tmp")
    temp.write_text(str(server.server_port), encoding="ascii")
    temp.replace(port)
    server.serve_forever()
'@ | Set-Content -LiteralPath $httpScript -Encoding utf8NoBOM
$pythonPaths = @(Get-Command python.exe -All -CommandType Application | Where-Object {
    $_.Source -notlike '*\WindowsApps\python.exe'
} | Select-Object -ExpandProperty Source)
$cacheCandidates = @($pythonPaths | Where-Object { $env:RUNNER_TOOL_CACHE -and $_.StartsWith($env:RUNNER_TOOL_CACHE, [StringComparison]::OrdinalIgnoreCase) })
$python = @($cacheCandidates + $pythonPaths) | Select-Object -First 1
if (-not $python) { throw 'No real Python executable available for loopback artifact server' }
$pythonVersion = & $python --version 2>&1
if ($LASTEXITCODE -ne 0 -or ($pythonVersion -join '') -notmatch '^Python 3\.\d+\.\d+$') { throw "Python not usable: $pythonVersion" }
Write-Host "Loopback interpreter: $pythonVersion ($python)"
$loopOut = Join-Path $testRoot 'server.stdout'
$loopErr = Join-Path $testRoot 'server.stderr'
$server = Start-Process $python -WorkingDirectory $serve -ArgumentList ('"' + $httpScript + '"') -PassThru -NoNewWindow -RedirectStandardOutput $loopOut -RedirectStandardError $loopErr
$changed = $false
$storeRemoved = $false
try {
    for ($i = 0; $i -lt 120 -and -not (Test-Path -LiteralPath $portPath); $i++) {
        if ($server.HasExited) { break }
        Start-Sleep -Milliseconds 250
    }
    if (-not (Test-Path -LiteralPath $portPath)) {
        Get-Content -LiteralPath $loopOut,$loopErr -ErrorAction Continue | Write-Host
        throw 'No loopback port after bounded 30-second startup'
    }
    $port = Get-Content -LiteralPath $portPath -Raw
    if ([string]::IsNullOrWhiteSpace($port) -or $port -notmatch '^\d{1,5}$' -or [int]$port -lt 1 -or [int]$port -gt 65535) { throw 'No verified loopback port' }
    $newManifest = Export-QAManifest '0.1.2' $expected['0.1.2'] "http://127.0.0.1:$port/$($new.Leaf)"
    if (-not $initial.LocalManifestFiles) {
        Invoke-WinGetChecked settings --enable LocalManifestFiles | Write-Host
        $changed = $true
    }
    if ((WinGetSettings).LocalManifestFiles -ne $true) { throw 'WinGet did not enable the local manifest QA setting' }
    Write-Host 'Local-manifest QA opt-in only on this disposable host; archive scanning and PowerShell policy remain intact.'
    Push-Location -LiteralPath $fixture
    try {
        $config = Join-Path $env:USERPROFILE '.config\winmole'
        if (Test-Path -LiteralPath $config) { throw 'Unexpected previous WinMole config on ephemeral host' }
        $null = New-Item -ItemType Directory -Path $config
        $sentinel = Join-Path $config 'whitelist'
        [IO.File]::WriteAllText($sentinel, '# disposable QA preference')
        $sentinelHash = (Get-FileHash -LiteralPath $sentinel).Hash
        Invoke-WinGetChecked install --manifest $newManifest --scope user --disable-interactivity | Write-Host
        $installed = Resolve-Installed '0.1.2' $new.Hash
        if ((Get-FileHash -LiteralPath $sentinel).Hash -ne $sentinelHash) { throw 'Install changed the preference' }
        # Exact public-manifest ID is not usable for this catalog-unpublished
        # package. Match the single freshly verified local ARP product code.
        # Leave source trust and archive protections alone; temporarily omit
        # the unrelated stock Store source to avoid accepting its agreements.
        Invoke-WinGetChecked source remove --name msstore --disable-interactivity | Write-Host
        $storeRemoved = $true
        $registered = @(PortableRegistration)
        if ($registered.Count -ne 1 -or $registered[0].DisplayVersion -cne '0.1.2' -or
            $registered[0].PSChildName -notmatch '^BhadraGada\.WinMole_[A-Za-z0-9._-]*$') {
            throw 'Refusing to uninstall without the exact verified portable product code'
        }
        $productCode = $registered[0].PSChildName
        Write-Host "Exact portable ARP product code selected for WinGet uninstall: $productCode"
        Invoke-WinGetChecked uninstall --product-code $productCode --scope user --disable-interactivity | Write-Host
        if (@(InstalledCommands).Count -or @(PortableRegistration).Count -or (Test-Path -LiteralPath $installed)) {
            throw 'Uninstall left an alias, installed binary or user-scope registration'
        }
        if ((Get-FileHash -LiteralPath $sentinel).Hash -ne $sentinelHash) { throw 'Uninstall changed the preference' }
        if ([Environment]::GetEnvironmentVariable('Path', 'Machine') -cne $machinePath) { throw 'User install changed machine PATH' }
        Write-Host 'Observed actual WinGet install and uninstall of the exact candidate; synthetic preferences and native reports verified. Catalog upgrade was not exercised.'
    } finally {
        Pop-Location
    }
} finally {
    try {
        if ($changed) { Invoke-WinGetChecked settings --disable LocalManifestFiles | Write-Host }
        if ($storeRemoved) {
            # A named reset only sees enabled sources on older WinGet.
            # The initial exact-default-only check makes this bounded.
            Invoke-WinGetChecked source reset --force --disable-interactivity | Write-Host
            $restored = Source-Snapshot | Sort-Object Name | ConvertTo-Json -Depth 5 -Compress
            if ($restored -cne $sourceFingerprint) { throw 'Failed to restore original stock sources' }
        }
        if ((WinGetSettings).LocalManifestFiles -ne $initial.LocalManifestFiles) { throw 'Failed to restore WinGet local manifest setting' }
        $policyAfter = & $ps51 -NoLogo -NoProfile -NonInteractive -Command 'Get-ExecutionPolicy; Get-ExecutionPolicy -List | ConvertTo-Json -Compress'
        if (($policyAfter -join ' ') -cne ($policyBefore -join ' ')) { throw 'PowerShell execution policy changed' }
    } finally {
        if (-not $server.HasExited) { Stop-Process -Id $server.Id }
    }
}
