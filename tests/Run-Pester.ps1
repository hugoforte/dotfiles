<#
.SYNOPSIS
    Runs the Pester suite in tests/, locally and in CI.

.DESCRIPTION
    Windows PowerShell 5.1 ships Pester 3, which cannot run a Pester 5 suite. This runner finds
    Pester 5 and refuses with instructions if it is absent: installing a module behind someone's
    back changes their machine, and that is the user's call, not this script's.

    It deliberately does not dot-source powershell/output.ps1. output.ps1 is the code under test,
    and a runner that broke whenever it did could not report that it had.

.PARAMETER CI
    Non-interactive: full per-test output, no progress bars, exit code reflects the failures.

.EXAMPLE
    .\tests\Run-Pester.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Pester.ps1 -CI
#>
[CmdletBinding()]
param(
    [switch]$CI
)

$ErrorActionPreference = 'Stop'

$installed = @(Get-Module -ListAvailable -Name Pester)
$pester5 = $installed |
    Where-Object { $_.Version.Major -ge 5 } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $pester5) {
    $versions = ($installed | ForEach-Object { $_.Version.ToString() }) -join ', '
    if (-not $versions) { $versions = 'none' }
    Write-Host "Pester 5 is required to run this suite and was not found." -ForegroundColor Red
    Write-Host "  Pester versions on this machine: $versions"
    Write-Host "  Install it with:"
    Write-Host "      Install-PackageProvider NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force"
    Write-Host "      Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck"
    Write-Host "  The first line installs the NuGet provider without the prompt a non-interactive shell cannot answer."
    Write-Host "  This runner will not install it for you: that would change your module path."
    exit 1
}

# Pester 3 ships in C:\Program Files\WindowsPowerShell\Modules and wins a bare Import-Module,
# so import the version that was found, by path.
$loaded = Get-Module -Name Pester
if ($loaded -and $loaded.Version.Major -lt 5) { Remove-Module -Name Pester -Force }
Import-Module -Name $pester5.Path -Force

if ($CI) { $ProgressPreference = 'SilentlyContinue' }

$config = New-PesterConfiguration
$config.Run.Path = $PSScriptRoot
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
if (-not $CI) { $config.Output.Verbosity = 'Normal' }

$result = Invoke-Pester -Configuration $config

if ($result.FailedCount -gt 0) {
    Write-Host "$($result.FailedCount) test(s) failed." -ForegroundColor Red
    exit 1
}

Write-Host "$($result.PassedCount) test(s) passed." -ForegroundColor Green
exit 0
