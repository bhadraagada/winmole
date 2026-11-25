#Requires -Version 5.1
#Requires -Modules Pester

Describe 'Clean entry point' {
    It 'finishes user dry-run without invoking the broad empty-directory sweep' {
        # Keep the real command router and clean orchestrator but replace every
        # imported module before launch. No profile or system cleanup can run.
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
        $fixture = Join-Path $TestDrive 'isolated command'
        foreach ($dir in @('bin', 'lib/core', 'lib/clean', 'appdata/unrelated/empty')) {
            $null = New-Item -ItemType Directory -Path (Join-Path $fixture $dir) -Force
        }
        $router = Join-Path $fixture 'winmole.ps1'
        Copy-Item -LiteralPath (Join-Path $repoRoot 'winmole.ps1') -Destination $router
        Copy-Item -LiteralPath (Join-Path $repoRoot 'bin/clean.ps1') -Destination (Join-Path $fixture 'bin/clean.ps1')
        Set-Content -LiteralPath (Join-Path $fixture 'lib/core/common.ps1') -Value @'
function Initialize-WinMole {}
function Clear-TempFiles {}
function Restore-WinMoleConsoleEncoding {}
function Write-WinMoleWarning { param([string]$Text) Write-Host $Text }
function Set-DryRunMode { param([bool]$Enabled) $script:FixtureDryRun = $Enabled }
function Test-DryRunMode { return $script:FixtureDryRun }
function Start-Section { param([string]$Title) }
function Stop-Section {}
function Reset-CleanupStats {}
function Get-CleanupStats { @{ TotalItems = 0; TotalSizeKB = 0 } }
function Show-Summary { param($SizeBytes, $ItemCount, $Action) Write-Host "SUMMARY: $Action" }
function Get-FreeSpace { 'fixture free space' }
function Remove-EmptyDirectories { throw 'Whole-tree empty-directory sweep was called' }
'@
        Set-Content -LiteralPath (Join-Path $fixture 'lib/clean/user.ps1') -Value @'
function Clear-UserCaches { Write-Host 'Fixture user cache phase' }
function Clear-UserLogs { Write-Host 'Fixture user log phase' }
'@
        foreach ($module in @('caches', 'apps', 'dev', 'system')) {
            Set-Content -LiteralPath (Join-Path $fixture "lib/clean/$module.ps1") -Value '# Test stub'
        }

        $originalLocalAppData = $env:LOCALAPPDATA
        $originalDryRun = $env:WINMOLE_DRY_RUN
        try {
            $env:LOCALAPPDATA = Join-Path $fixture 'appdata'
            $env:WINMOLE_DRY_RUN = '0'
            $shell = (Get-Process -Id $PID).Path
            $output = & $shell -NoLogo -NoProfile -NonInteractive -File $router clean -User -DryRun 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 0 -Because $output
        }
        finally {
            $env:LOCALAPPDATA = $originalLocalAppData
            $env:WINMOLE_DRY_RUN = $originalDryRun
        }
        $output | Should -Match 'DRY RUN MODE'
        $output | Should -Match 'Fixture user cache phase'
        $output | Should -Match 'Fixture user log phase'
        $output | Should -Match 'SUMMARY: Would clean'
        $output | Should -Not -Match 'Whole-tree empty-directory sweep'
        Test-Path -LiteralPath (Join-Path $fixture 'appdata/unrelated/empty') | Should -BeTrue
    }
}
