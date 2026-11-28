#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    $script:root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $script:windowsPowerShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'

    function Invoke-IsolatedPreview {
        param([string[]]$ArgumentList, [string]$PreviewEnvironment)
        $names = @('USERPROFILE', 'LOCALAPPDATA', 'APPDATA', 'TEMP', 'TMP', 'WINMOLE_DRY_RUN')
        $saved = @{}
        foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
        try {
            foreach ($name in $names) {
                if ($name -eq 'WINMOLE_DRY_RUN') {
                    [Environment]::SetEnvironmentVariable($name, $PreviewEnvironment, 'Process')
                }
                else {
                    [Environment]::SetEnvironmentVariable($name, $script:fixturePaths[$name], 'Process')
                }
            }

            $output = & $script:windowsPowerShell -NoLogo -NoProfile -NonInteractive -File @ArgumentList 2>&1
            @{ Text = ($output | Out-String -Width 200); ExitCode = $LASTEXITCODE }
        }
        finally {
            foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
        }
    }
}

Describe 'Dry-run command safety in Windows PowerShell' {
    BeforeEach {
        $profilePath = (New-Item -ItemType Directory -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString()))).FullName
        $local = (New-Item -ItemType Directory -Path (Join-Path $profilePath 'Local')).FullName
        $roaming = (New-Item -ItemType Directory -Path (Join-Path $profilePath 'Roaming')).FullName
        $temp = (New-Item -ItemType Directory -Path (Join-Path $profilePath 'Temp')).FullName
        $script:fixturePaths = @{ USERPROFILE = $profilePath; LOCALAPPDATA = $local; APPDATA = $roaming; TEMP = $temp; TMP = $temp }
    }

    It 'Clean <Name> reports and preserves the sentinel' -TestCases @(
        @{ Name = 'direct switch'; Route = 'direct'; Flag = '-DryRun' }
        @{ Name = 'direct alias'; Route = 'direct'; Flag = '-dry-run' }
        @{ Name = 'routed switch'; Route = 'router'; Flag = '-DryRun' }
        @{ Name = 'routed alias'; Route = 'router'; Flag = '--dry-run' }
        @{ Name = 'environment mode'; Route = 'router'; Flag = ''; PreviewEnvironment = '1' }
    ) {
        param($Name, $Route, $Flag, $PreviewEnvironment)

        $cache = (New-Item -ItemType Directory -Path (Join-Path $script:fixturePaths.LOCALAPPDATA 'D3DSCache')).FullName
        $sentinel = Join-Path $cache 'fixture-only.bin'
        [IO.File]::WriteAllBytes($sentinel, [byte[]]@(1, 2, 3, 4))
        $digest = (Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash

        $command = if ($Route -eq 'direct') {
            @((Join-Path $script:root 'bin/clean.ps1'))
        }
        else { @((Join-Path $script:root 'winmole.ps1'), 'clean') }
        $command = @($command)
        if ($Flag) { $command += $Flag }
        $result = Invoke-IsolatedPreview -ArgumentList ($command + '-GPUShaders') -PreviewEnvironment $PreviewEnvironment
        $result.ExitCode | Should -Be 0 -Because $result.Text
        $result.Text | Should -Match 'DRY RUN MODE'
        $result.Text | Should -Match '(?m)DirectX shader cache[^\r\n]*1 items, 4 B dry'
        $result.Text | Should -Match 'Would clean'
        (Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash | Should -BeExactly $digest
    }

    It 'Optimize <Name> passes preview state to every mutation-capable call without executing one' -TestCases @(
        @{ Name = 'direct switch'; Flag = '-DryRun' }
        @{ Name = 'direct alias'; Flag = '-dry-run' }
        @{ Name = 'environment mode'; Flag = ''; PreviewEnvironment = '1' }
    ) {
        param($Name, $Flag, $PreviewEnvironment)

        $tokens = $null
        $errors = $null
        $source = Join-Path $script:root 'bin/optimize.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
        $functions = @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })
        $optimizeMain = @($functions | Where-Object Name -eq 'Main')
        $optimizeMain.Count | Should -Be 1
        # Use the real parameter block, module imports and Main. Do not include
        # any real OS-mutating functions from Optimize in the fixture at all.
        $prefix = $ast.Extent.Text.Substring(0, $functions[0].Extent.StartOffset - $ast.Extent.StartOffset)
        $bin = (New-Item -ItemType Directory -Path (Join-Path $script:fixturePaths.USERPROFILE 'bin')).FullName
        $lib = (New-Item -ItemType Directory -Path (Join-Path $script:fixturePaths.USERPROFILE 'lib')).FullName
        Copy-Item -LiteralPath (Join-Path $script:root 'lib/core') -Destination $lib -Recurse
        $fixtureScript = Join-Path $bin 'optimize-binding.ps1'
        $mocks = @'
function Clear-Host {}
function Get-SystemHealth { return @{} }
function Show-SystemHealth { param($Health) }
function Get-StartupPrograms {}
function Test-DiskHealth {}
function Test-WindowsUpdate {}
function Show-OptimizeSummary {}
function Test-IsAdmin { return $true }
function Read-Host { throw 'A preview must not prompt to run SFC.' }
function Assert-PreviewMode([string]$Name) {
    if (-not $script:DryRun) { throw "Reached $Name without preview mode." }
    Write-Host "PreviewOnly:$Name"
}
function Optimize-DiskDrive { Assert-PreviewMode 'Disk' }
function Clear-DnsCache { Assert-PreviewMode 'DNS' }
function Optimize-Network { Assert-PreviewMode 'Network' }
function Repair-FontCache { Assert-PreviewMode 'Font' }
function Repair-StoreCache { Assert-PreviewMode 'Store' }
function Repair-SearchIndex { Assert-PreviewMode 'Search' }
function Repair-IconCache { Assert-PreviewMode 'Icon' }
'@
        [IO.File]::WriteAllText($fixtureScript, ($prefix + $mocks + "`r`n" + $optimizeMain[0].Extent.Text + "`r`nMain"), [Text.UTF8Encoding]::new($true))
        $command = @($fixtureScript)
        if ($Flag) { $command += $Flag }
        $result = Invoke-IsolatedPreview -ArgumentList $command -PreviewEnvironment $PreviewEnvironment
        $result.ExitCode | Should -Be 0 -Because $result.Text
        $result.Text | Should -Match 'DRY RUN MODE'
        foreach ($operation in @('Disk', 'DNS', 'Network', 'Font', 'Store', 'Search', 'Icon')) {
            $result.Text | Should -Match "PreviewOnly:$operation"
        }
    }
}
