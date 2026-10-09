# WinMole - Static command resolution check
#
# PowerShell resolves command names at call time, so a call to a function that
# does not exist, or a call passing a parameter that was never declared, is
# perfectly valid syntax and parses cleanly. It only fails when that specific
# branch executes. Issue #14 reached master and survived for months exactly this
# way: six calls in bin/clean.ps1 were broken and every syntax check passed.
#
# This script parses every script under bin/ and lib/ and fails the build when:
#   1. A Verb-Noun invocation resolves to neither a repo function nor a real
#      cmdlet, alias or application.
#   2. A call to a repo function passes a named parameter that function does not
#      declare. This is the subtler case: `Invoke-SystemCleanup -All` names a
#      real function, so a name-only search finds nothing wrong.
#
# Usage:  pwsh -File scripts/check-commands.ps1
# Exits 0 when clean, 1 when any problem is found.

[CmdletBinding()]
param(
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$commonParameters = @(
    'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
    'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable',
    'OutBuffer', 'PipelineVariable', 'ProgressAction', 'WhatIf', 'Confirm'
)

# Calls to names this repo does not define are tolerated only when an enclosing
# if-condition tests for them with Get-Command, which is how the compatibility
# shims in bin/clean.ps1 (#11) are written. That is detected structurally below,
# so no name list is needed and a genuinely broken call cannot hide behind one.
#
# Parameter exceptions must name the enclosing function, not just the command.
# Keying on the command name alone would excuse `Invoke-SystemCleanup -All`
# anywhere in the repo, including a real mistake; scoping it to the one shim that
# probes for the parameter at runtime keeps the exception narrow. Tracked in #16
# for removal once the shims call the real names directly.
$allowedParameters = @{
    'Invoke-SystemCleanupCompat:Invoke-SystemCleanup:All' = 'this shim tests for -All via Get-Command before calling'
}

$files = Get-ChildItem -Path (Join-Path $RepoRoot 'bin'), (Join-Path $RepoRoot 'lib') `
    -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue

if (-not $files) {
    Write-Host "No PowerShell files found under bin/ or lib/ - nothing to check." -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------------------
# Index every function defined in the repo, with its declared parameters
# ---------------------------------------------------------------------------
$defined = @{}
foreach ($file in $files) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($function in $functions) {
        $names = @()
        if ($function.Parameters) {
            $names += $function.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
        }
        if ($function.Body.ParamBlock -and $function.Body.ParamBlock.Parameters) {
            $names += $function.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
        }
        $defined[$function.Name] = @{
            Parameters = @($names | Sort-Object -Unique)
            File       = $file.FullName.Substring($RepoRoot.Length + 1)
            Line       = $function.Extent.StartLineNumber
        }
    }
}

# ---------------------------------------------------------------------------
# A call is "guarded" when an enclosing if-condition tests for the command's
# existence with Get-Command, which is how the #11 shims are written.
# ---------------------------------------------------------------------------
function Test-CallIsGuarded {
    param($CallAst, [string]$Name)

    $node = $CallAst.Parent
    while ($null -ne $node) {
        if ($node -is [System.Management.Automation.Language.IfStatementAst]) {
            foreach ($clause in $node.Clauses) {
                $condition = $clause.Item1.Extent.Text
                if ($condition -match 'Get-Command' -and $condition -match [regex]::Escape($Name)) {
                    return $true
                }
            }
        }
        $node = $node.Parent
    }
    return $false
}

# Name of the function a call sits inside, or '' at file scope. Used to scope
# parameter exceptions so they cannot excuse the same mistake elsewhere.
function Get-EnclosingFunctionName {
    param($CallAst)

    $node = $CallAst.Parent
    while ($null -ne $node) {
        if ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            return $node.Name
        }
        $node = $node.Parent
    }
    return ''
}

$missing = [System.Collections.Generic.List[string]]::new()
$badParameters = [System.Collections.Generic.List[string]]::new()
$allowedHits = [System.Collections.Generic.List[string]]::new()

foreach ($file in $files) {
    $relative = $file.FullName.Substring($RepoRoot.Length + 1)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
    $calls = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)

    foreach ($call in $calls) {
        $name = $call.GetCommandName()
        if (-not $name) { continue }
        if ($name -notmatch '^[A-Z][a-z]+-[A-Za-z]') { continue }

        $line = $call.Extent.StartLineNumber
        $isRepoFunction = $defined.ContainsKey($name)

        # --- check 1: does the command resolve at all? ---
        if (-not $isRepoFunction) {
            $resolves = $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
            if (-not $resolves) {
                if (Test-CallIsGuarded -CallAst $call -Name $name) {
                    $enclosing = Get-EnclosingFunctionName -CallAst $call
                    $allowedHits.Add("${relative}:${line}  $name  (Get-Command guarded, in $enclosing)")
                }
                else {
                    $missing.Add("${relative}:${line}  $name is not defined in this repo and is not a known command")
                }
            }
            continue
        }

        # --- check 2: do the named parameters exist on the target function? ---
        $target = $defined[$name]
        foreach ($element in $call.CommandElements) {
            if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
            $parameter = $element.ParameterName
            if ($commonParameters -contains $parameter) { continue }

            # PowerShell accepts unambiguous prefixes, so treat those as valid.
            $matched = @($target.Parameters | Where-Object { $_ -like "$parameter*" })
            if ($matched.Count -gt 0) { continue }

            $enclosing = Get-EnclosingFunctionName -CallAst $call
            $key = "${enclosing}:${name}:${parameter}"
            if ($allowedParameters.ContainsKey($key)) {
                $allowedHits.Add("${relative}:${line}  $name -$parameter  in $enclosing ($($allowedParameters[$key]))")
                continue
            }

            $declared = if ($target.Parameters) { $target.Parameters -join ', ' } else { '(none)' }
            $badParameters.Add("${relative}:${line}  $name -$parameter is not a parameter of $name (declared: $declared; defined at $($target.File):$($target.Line))")
        }
    }
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
Write-Host "Command resolution check" -ForegroundColor Cyan
Write-Host "  scanned $($files.Count) files, indexed $($defined.Count) functions"
Write-Host ""

if ($allowedHits.Count -gt 0) {
    Write-Host "Allowed exceptions ($($allowedHits.Count)):" -ForegroundColor Yellow
    foreach ($hit in $allowedHits) { Write-Host "  $hit" }
    Write-Host ""
}

$failed = $false

if ($missing.Count -gt 0) {
    $failed = $true
    Write-Host "Unresolved commands ($($missing.Count)):" -ForegroundColor Red
    foreach ($item in $missing) { Write-Host "  $item" }
    Write-Host ""
}

if ($badParameters.Count -gt 0) {
    $failed = $true
    Write-Host "Parameter binding mismatches ($($badParameters.Count)):" -ForegroundColor Red
    foreach ($item in $badParameters) { Write-Host "  $item" }
    Write-Host ""
}

if ($failed) {
    Write-Host "FAILED - see above. These would surface only when the affected branch runs." -ForegroundColor Red
    exit 1
}

Write-Host "PASSED - every command resolves and every named parameter exists." -ForegroundColor Green
exit 0
