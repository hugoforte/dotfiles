# Install the tools declared in tools.psd1.
#
#   install-tools.ps1              install everything missing; report manual steps
#   install-tools.ps1 -Check       report only; exit 1 if anything is missing
#   install-tools.ps1 -Unattended  install only entries safe to install unwatched
#   install-tools.ps1 -IfChanged   do nothing unless tools.psd1 has changed since the last run
#   install-tools.ps1 -PassThru    also return the result object, for a caller that reads it
#
# Idempotent: entries install only when missing. Nothing is ever upgraded or uninstalled -
# a program on the machine and not in the manifest was installed on purpose.
#
# sync.ps1 calls this as -IfChanged -Unattended -Quiet -PassThru from a scheduled task, so nothing
# here may raise a UAC prompt: winget installs use --scope user unless the shell is already elevated.

param(
    [switch]$Check,
    [switch]$Quiet,
    [switch]$Unattended,
    [switch]$IfChanged,
    [switch]$PassThru
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "output.ps1")

$manifestPath = Join-Path $PSScriptRoot "tools.psd1"
$stateDir = Join-Path $env:LOCALAPPDATA "dotfiles"
$statePath = Join-Path $stateDir "tools.state"
$missing = 0
$failed = 0
$deferred = 0

$result = New-ScriptResult -Name "install-tools.ps1" -Quiet:$Quiet -PassThru:$PassThru

# --- Preconditions --------------------------------------------------------------------------

if (-not (Test-Path $manifestPath)) {
    Fail "$manifestPath not found"
    Exit-WithResult $result 1
}

$manifest = Import-PowerShellDataFile $manifestPath
$tools = @($manifest.Tools)
if ($tools.Count -eq 0) {
    Fail "tools.psd1 declares no tools"
    Exit-WithResult $result 1
}

$manifestHash = (Get-FileHash $manifestPath -Algorithm SHA256).Hash

if ($IfChanged) {
    $applied = $null
    if (Test-Path $statePath) { $applied = (Get-Content $statePath -Raw).Trim() }
    if ($applied -eq $manifestHash) {
        Ok "tools.psd1 unchanged since the last successful run; nothing to do"
        Exit-WithResult $result 0
    }
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# --- Presence tests --------------------------------------------------------------------------

function Test-WingetPackage {
    param([string]$Id)
    winget list --id $Id --exact --accept-source-agreements | Out-Null
    return ($LASTEXITCODE -eq 0)
}

$script:npmGlobals = $null
function Get-NpmGlobals {
    if ($null -ne $script:npmGlobals) { return $script:npmGlobals }
    $script:npmGlobals = @()
    $json = npm ls -g --depth=0 --json
    if ($LASTEXITCODE -eq 0 -and $json) {
        $parsed = $json | ConvertFrom-Json
        if ($parsed.dependencies) {
            $script:npmGlobals = @($parsed.dependencies.PSObject.Properties.Name)
        }
    }
    return $script:npmGlobals
}

function Test-NpmPackage {
    param([string]$Id)
    return ((Get-NpmGlobals) -contains $Id)
}

# --- Installers -------------------------------------------------------------------------------

function Install-WingetPackage {
    param([string]$Id)
    $arguments = @('install', '--id', $Id, '--exact', '--silent',
                   '--accept-package-agreements', '--accept-source-agreements',
                   '--disable-interactivity')
    # Machine scope needs elevation, which a scheduled task must never ask for.
    if (-not $isAdmin) { $arguments += @('--scope', 'user') }
    & winget @arguments | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Install-NpmPackage {
    param([string]$Id)
    npm install -g $Id | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# --- Apply -------------------------------------------------------------------------------------

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Warn "winget not found; winget entries cannot be installed on this machine"
}

Say "Reading $manifestPath" Cyan

$manualSteps = @()

foreach ($tool in $tools) {
    $id = $tool.Id
    $source = $tool.Source
    $unattendedOk = $true
    if ($tool.ContainsKey('Unattended')) { $unattendedOk = [bool]$tool.Unattended }

    if ($source -eq 'manual') {
        $manualSteps += $tool
        continue
    }

    $present = $false
    switch ($source) {
        'winget' { $present = Test-WingetPackage $id }
        'npm'    { $present = Test-NpmPackage $id }
        default  { Warn "$id has unknown Source '$source'"; continue }
    }

    if ($present) { Ok "$id"; continue }

    $missing++

    if ($Check) { Warn "$id missing ($source)"; continue }

    if ($Unattended -and -not $unattendedOk) {
        $deferred++
        Warn "$id missing ($source) - not installed here: run install-tools.ps1 yourself when convenient"
        continue
    }

    Change "installing $id ($source)"
    $installed = $false
    switch ($source) {
        'winget' { $installed = Install-WingetPackage $id }
        'npm'    { $installed = Install-NpmPackage $id }
    }

    if ($installed) {
        Ok "$id installed"
    } else {
        $failed++
        Warn "$id failed to install ($source)"
    }
}

# --- Manual steps: always reported, never done -------------------------------------------------

if ($manualSteps.Count -gt 0) {
    Say ""
    Say "Yours to do (nothing here is automated):" Cyan
    foreach ($step in $manualSteps) {
        $line = "$($step.Id) - $($step.Note)"
        if ($step.Url) { $line += " [$($step.Url)]" }
        Todo $line
    }
}

# --- Record the applied manifest, but only when nothing was left undone ------------------------
#
# A failed install must not be recorded as applied, or the -IfChanged gate would skip the next
# run and the tool would never arrive. An entry deferred by -Unattended is different: that is a
# standing decision, not a transient failure, so it does not hold the hash back - deferred entries
# are setup.ps1's job and a deliberate run's job, and they would otherwise re-probe on every sync
# forever, which is the cost the gate exists to avoid.

if (-not $Check -and $failed -eq 0) {
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
    Set-Content -Path $statePath -Value $manifestHash -Encoding utf8
}

# Each of these counts outcomes reported per tool above, so they go through Summary and are
# not recorded a second time.
Say ""
if ($Check) {
    if ($missing -gt 0) { Summary Warn "$missing tool(s) missing"; Exit-WithResult $result 1 }
    Summary Ok "every declared tool is installed"
    Exit-WithResult $result 0
}

if ($deferred -gt 0) { Summary Warn "$deferred tool(s) skipped as not safe to install unwatched - run powershell\install-tools.ps1 when convenient" }
if ($failed -gt 0) { Summary Warn "$failed tool(s) failed to install"; Exit-WithResult $result 1 }
Summary Ok "tools up to date"
Exit-WithResult $result 0
