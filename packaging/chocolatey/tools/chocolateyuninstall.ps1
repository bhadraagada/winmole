$ErrorActionPreference = 'Stop'

$packageName = 'winmole'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Find installation directory
$installDir = Get-ChildItem $toolsDir -Directory | Where-Object { $_.Name -like "winmole-*" } | Select-Object -First 1

if ($installDir) {
    $winmoleDir = $installDir.FullName
    
    # Remove from PATH
    Uninstall-ChocolateyPath -PathToUninstall $winmoleDir -PathType 'User'
    
    Write-Host ""
    Write-Host "WinMole has been uninstalled successfully" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Warning "Installation directory not found, but PATH will be cleaned up"
}
