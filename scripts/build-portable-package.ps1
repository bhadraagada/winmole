#Requires -Version 7.0
param(
    [Parameter(Mandatory)]
    [ValidateSet('amd64', 'arm64')]
    [string]$Architecture,

    [Parameter(Mandatory)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$outputPath = [IO.Path]::GetFullPath($OutputDirectory, (Get-Location).ProviderPath)
$null = New-Item -ItemType Directory -Path $outputPath -Force
$archiveName = "winmole-windows-$Architecture.zip"
if (Test-Path -LiteralPath (Join-Path $outputPath $archiveName)) {
    throw "Refusing to replace an existing archive: $archiveName"
}
$binOutput = Join-Path $outputPath 'bin'
$null = New-Item -ItemType Directory -Path $binOutput -Force
$tools = @('winmole', 'analyze', 'status')
# Use the same version as the legacy PowerShell entry point.
$versionFile = Join-Path $repo 'lib/core/common.ps1'
$versionMatch = [regex]::Match([IO.File]::ReadAllText($versionFile),
    '(?m)^\$script:WINMOLE_VERSION = "([0-9]+\.[0-9]+\.[0-9]+)"\s*$')
if (-not $versionMatch.Success) { throw 'Unable to read the WinMole version for the portable launcher.' }
$version = $versionMatch.Groups[1].Value
foreach ($tool in $tools) {
    $asset = Join-Path $binOutput "$tool-windows-$Architecture.exe"
    if (Test-Path -LiteralPath $asset) { throw "Refusing to replace an existing executable: $asset" }
}

$bundle = (New-Item -ItemType Directory -Path (
    Join-Path $outputPath ("winmole-bundle-" + [guid]::NewGuid()))).FullName
$oldGOOS, $oldGOARCH, $oldCGO = $env:GOOS, $env:GOARCH, $env:CGO_ENABLED
Push-Location -LiteralPath $repo
try {
    $null = New-Item -ItemType Directory -Path (Join-Path $bundle 'bin')
    $env:GOOS = 'windows'
    $env:GOARCH = $Architecture
    $env:CGO_ENABLED = '0'
    foreach ($tool in $tools) {
        $relativePath = if ($tool -eq 'winmole') { 'winmole.exe' } else { "bin/$tool.exe" }
        $exe = Join-Path $bundle $relativePath
        $linkerFlags = if ($tool -eq 'winmole') { "-s -w -X main.version=$version" } else { '-s -w' }
        & go build "-ldflags=$linkerFlags" -o $exe "./cmd/$tool"
        if ($LASTEXITCODE -ne 0) { throw "Go build failed for $tool ($Architecture): $LASTEXITCODE" }
    }
    foreach ($leaf in @('winmole.ps1', 'install.ps1', 'README.md', 'LICENSE', 'CONTRIBUTING.md')) {
        Copy-Item -LiteralPath $leaf -Destination $bundle
    }
    Get-ChildItem -LiteralPath 'bin' -Filter '*.ps1' -File |
        Copy-Item -Destination (Join-Path $bundle 'bin')
    Copy-Item -LiteralPath 'lib' -Destination $bundle -Recurse

    # Pass the package directory's contents, not the directory itself, to ensure
    # winget's nested portable path is always winmole.exe at the archive root.
    Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath (Join-Path $outputPath $archiveName)
    foreach ($tool in $tools) {
        $relativePath = if ($tool -eq 'winmole') { 'winmole.exe' } else { "bin/$tool.exe" }
        Copy-Item -LiteralPath (Join-Path $bundle $relativePath) -Destination (
            Join-Path $binOutput "$tool-windows-$Architecture.exe")
    }
}
finally {
    Pop-Location
    $env:GOOS, $env:GOARCH, $env:CGO_ENABLED = $oldGOOS, $oldGOARCH, $oldCGO
    # The directory was generated from a fresh GUID above; never delete the requested output directory.
    [IO.Directory]::Delete($bundle, $true)
}
