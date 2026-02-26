$ErrorActionPreference = 'Stop'

$packageName = 'winmole'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$version = '1.0.0'

# Download info
$url64 = "https://github.com/bhadraagada/winmole/releases/download/v$version/winmole-$version-x64.zip"
$checksum64 = 'c5671df0196ddd8aa172845c537b47159e752d7555676a04c0d95a971f4a11d3'
$checksumType = 'sha256'

# Package parameters
$packageArgs = @{
    packageName    = $packageName
    unzipLocation  = $toolsDir
    url64bit       = $url64
    checksum64     = $checksum64
    checksumType64 = $checksumType
}

# Install ZIP package
Install-ChocolateyZipPackage @packageArgs

# Add to PATH
$installDir = Get-ChildItem $toolsDir -Directory | Where-Object { $_.Name -like "winmole-*" } | Select-Object -First 1
if ($installDir) {
    $winmoleDir = $installDir.FullName
    Install-ChocolateyPath -PathToInstall $winmoleDir -PathType 'User'
    
    Write-Host ""
    Write-Host "WinMole has been installed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Available commands:" -ForegroundColor Cyan
    Write-Host "  winmole clean     - Deep system cleanup"
    Write-Host "  winmole uninstall - Remove unwanted apps"
    Write-Host "  winmole analyze   - Disk space analysis"
    Write-Host "  winmole status    - System health check"
    Write-Host "  winmole optimize  - Rebuild caches"
    Write-Host "  winmole purge     - Remove dev artifacts"
    Write-Host ""
    Write-Host "Run 'winmole --help' for more information" -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Error "Installation directory not found"
}
