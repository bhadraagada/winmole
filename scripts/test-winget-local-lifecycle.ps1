# Temporary hosted QA only. No publication, PowerShell policy changes, external server, or cleanup apply.
#Requires -Version 7.0
param([Parameter(Mandatory)][string]$Winget, [Parameter(Mandatory)][string]$Previous, [Parameter(Mandatory)][string]$Candidate)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_ARCH -ne 'ARM64') {
    throw 'This probe only runs on the intended disposable GitHub ARM64 runner.'
}
$expected = @{
    '0.1.1' = '07f3e34d131aad82a1691824131232396b0336836908267b3e7c88045aa44910'
    '0.1.2' = 'ec4b66e00cbca86c56e2d56a43a9f8fafede3dc26b2cfee106e24bdaf4ff94ec'
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
Scope: user
Installers:
- Architecture: arm64
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
    $leaf = "winmole-$version-windows-arm64.zip"
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
$old = Stage-Archive '0.1.1' $Previous
$new = Stage-Archive '0.1.2' $Candidate
$httpScript = Join-Path $testRoot 'loopback.py'
@'
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

with ThreadingHTTPServer(("127.0.0.1", 0), SimpleHTTPRequestHandler) as server:
    Path("../port.txt").write_text(str(server.server_port), encoding="ascii")
    server.serve_forever()
'@ | Set-Content -LiteralPath $httpScript -Encoding utf8NoBOM
$python = (Get-Command python.exe -CommandType Application).Source
$server = Start-Process $python -WorkingDirectory $serve -ArgumentList ('"' + $httpScript + '"') -PassThru -NoNewWindow
$changed = $false
try {
    $portPath = Join-Path $testRoot 'port.txt'
    for ($i = 0; $i -lt 50 -and -not (Test-Path -LiteralPath $portPath); $i++) {
        if ($server.HasExited) { throw 'Loopback server exited' }
        Start-Sleep -Milliseconds 100
    }
    $port = Get-Content -LiteralPath $portPath
    if ($port -notmatch '^\d{1,5}$') { throw 'No verified loopback port' }
    $oldManifest = Export-QAManifest '0.1.1' $expected['0.1.1'] "http://127.0.0.1:$port/$($old.Leaf)"
    $newManifest = Export-QAManifest '0.1.2' $expected['0.1.2'] "http://127.0.0.1:$port/$($new.Leaf)"
    if (-not $initial.LocalManifestFiles) {
        Invoke-WinGetChecked settings --enable LocalManifestFiles | Write-Host
        $changed = $true
    }
    if ((WinGetSettings).LocalManifestFiles -ne $true) { throw 'WinGet did not enable the local manifest QA setting' }
    Write-Host 'Local-manifest QA opt-in only on this disposable host; archive scanning and PowerShell policy remain intact.'
    Push-Location -LiteralPath $fixture
    try {
        Invoke-WinGetChecked install --manifest $oldManifest --scope user --disable-interactivity | Write-Host
        $oldInstalled = Resolve-Installed '0.1.1' $old.Hash
        $config = Join-Path $env:USERPROFILE '.config\winmole'
        if (Test-Path -LiteralPath $config) { throw 'Unexpected previous WinMole config on ephemeral host' }
        $null = New-Item -ItemType Directory -Path $config
        $sentinel = Join-Path $config 'whitelist'
        [IO.File]::WriteAllText($sentinel, '# disposable QA preference')
        $sentinelHash = (Get-FileHash -LiteralPath $sentinel).Hash
        Invoke-WinGetChecked upgrade --manifest $newManifest --scope user --disable-interactivity | Write-Host
        $newInstalled = Resolve-Installed '0.1.2' $new.Hash
        if ((Get-FileHash -LiteralPath $sentinel).Hash -ne $sentinelHash) { throw 'Upgrade changed the preference' }
        Invoke-WinGetChecked uninstall --manifest $newManifest --scope user --disable-interactivity | Write-Host
        if (@(InstalledCommands).Count -or @(PortableRegistration).Count -or (Test-Path -LiteralPath $newInstalled) -or (Test-Path -LiteralPath $oldInstalled)) {
            throw 'Uninstall left an alias, installed binary or user-scope registration'
        }
        if ((Get-FileHash -LiteralPath $sentinel).Hash -ne $sentinelHash) { throw 'Uninstall changed the preference' }
        if ([Environment]::GetEnvironmentVariable('Path', 'Machine') -cne $machinePath) { throw 'User install changed machine PATH' }
        Write-Host 'Observed actual WinGet install, upgrade and uninstall of exact loopback artifacts; preferences and native reports verified.'
    } finally {
        Pop-Location
    }
} finally {
    try {
        if ($changed) { Invoke-WinGetChecked settings --disable LocalManifestFiles | Write-Host }
        if ((WinGetSettings).LocalManifestFiles -ne $initial.LocalManifestFiles) { throw 'Failed to restore WinGet local manifest setting' }
        $policyAfter = & $ps51 -NoLogo -NoProfile -NonInteractive -Command 'Get-ExecutionPolicy; Get-ExecutionPolicy -List | ConvertTo-Json -Compress'
        if (($policyAfter -join ' ') -cne ($policyBefore -join ' ')) { throw 'PowerShell execution policy changed' }
    } finally {
        if (-not $server.HasExited) { Stop-Process -Id $server.Id }
    }
}
