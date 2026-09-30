<#
.SYNOPSIS
    Runs the Pester 5 test suite and PSScriptAnalyzer for ServiceDeskToolkit (locally and in CI).

.DESCRIPTION
    1. Pester 5 on ./tests with NUnit XML output in ./TestResults.
    2. PSScriptAnalyzer on the module and this script with PSScriptAnalyzerSettings.psd1 - any finding fails.
    No tenant and no sign-in are needed: all Graph and Exchange Online cmdlets are mocked.

.PARAMETER InstallDependencies
    Installs Pester 5 and PSScriptAnalyzer for the current user if they are missing.

.PARAMETER SkipAnalyzer
    Runs the tests only.

.EXAMPLE
    ./scripts/Invoke-QualityGate.ps1 -InstallDependencies

.NOTES
    Author:  Artur Warkentin
    Version: 0.1.0
    Date:    2026-09-30
#>
[CmdletBinding()]
param(
    [switch]$InstallDependencies,
    [switch]$SkipAnalyzer
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent

if ($InstallDependencies) {
    if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -eq 5 })) {
        Install-Module -Name Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99 -Scope CurrentUser -Force -SkipPublisherCheck
    }
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
    }
}

$failed = $false

$pester = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -eq 5 } | Sort-Object -Property Version -Descending | Select-Object -First 1
if (-not $pester) { throw 'Pester 5 is not installed. Run with -InstallDependencies.' }
if (-not (Get-Module -Name Pester | Where-Object Version -EQ $pester.Version)) {
    Get-Module -Name Pester | Remove-Module -Force
    Import-Module $pester.Path
}

$config = New-PesterConfiguration
$config.Run.Path = Join-Path $root 'tests'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = Join-Path $root 'TestResults/testResults.xml'

$result = Invoke-Pester -Configuration $config
Write-Output ('Pester {0}: {1} passed, {2} failed, {3} skipped.' -f $pester.Version, $result.PassedCount, $result.FailedCount, $result.SkippedCount)
if ($result.FailedCount -gt 0) { $failed = $true }

# The analyzer runs after Pester: resolving commands in this script can load another Pester
# version's assembly (e.g. Pester 6), which would block importing Pester 5 afterwards.
if (-not $SkipAnalyzer) {
    Import-Module PSScriptAnalyzer
    $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
    $findings = @(
        Invoke-ScriptAnalyzer -Path (Join-Path $root 'ServiceDeskToolkit') -Recurse -Settings $settings
        Invoke-ScriptAnalyzer -Path (Join-Path $root 'scripts') -Recurse -Settings $settings
    )
    if ($findings.Count -gt 0) {
        $findings | Format-Table -Property Severity, RuleName, ScriptName, Line, Message -AutoSize -Wrap | Out-String | Write-Output
        Write-Output ('PSScriptAnalyzer: {0} finding(s).' -f $findings.Count)
        $failed = $true
    }
    else {
        Write-Output 'PSScriptAnalyzer: no findings.'
    }
}

if ($failed) { exit 1 }
