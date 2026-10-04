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
# Optional entries install only on a machine that opts into them: see tool-selection.ps1.
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
. (Join-Path $PSScriptRoot "tool-selection.ps1")

$manifestPath = Join-Path $PSScriptRoot "tools.psd1"
$localPath = Join-Path (Split-Path $PSScriptRoot -Parent) "ai\secrets\machine.local.psd1"
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
if (@($manifest.Tools).Count -eq 0) {
    Fail "tools.psd1 declares no tools"
    Exit-WithResult $result 1
}

try {
    $optedIn = @(Get-OptedInOptionList -LocalPath $localPath)
} catch {
    Fail "could not read $localPath`: $($_.Exception.Message)"
    Exit-WithResult $result 1
}
$selection = Select-MachineTools -Tools @($manifest.Tools) -OptedIn $optedIn
$tools = $selection.Selected

# Opting in changes what this machine needs without touching tools.psd1, so the options are
# part of what -IfChanged compares.
$manifestHash = (Get-FileHash $manifestPath -Algorithm SHA256).Hash + ":" + (($optedIn | Sort-Object) -join ",")

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

$script:installedPrograms = $null
function Get-InstalledProgramNames {
    if ($null -ne $script:installedPrograms) { return $script:installedPrograms }
    $keys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $script:installedPrograms = @(Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } | ForEach-Object { $_.DisplayName })
    return $script:installedPrograms
}

function Test-GitHubRelease {
    param([hashtable]$Tool)
    return (Test-ProgramListed -DisplayName $Tool.Present -Listed @(Get-InstalledProgramNames))
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

# Downloads the latest release's installer asset and runs it with the entry's InstallArgs. The
# reason for a failure is printed; the caller records the one outcome.
function Install-GitHubRelease {
    param([hashtable]$Tool)
    # 5.1 redraws its progress bar per chunk, which makes a large download crawl.
    $ProgressPreference = 'SilentlyContinue'
    $installer = $null
    try {
        $release = Invoke-RestMethod "https://api.github.com/repos/$($Tool.Id)/releases/latest" -UseBasicParsing
        $asset = Select-ReleaseAsset -Assets @($release.assets) -Pattern $Tool.Asset
        $downloadDir = Join-Path $env:TEMP "dotfiles-tools"
        if (-not (Test-Path $downloadDir)) { New-Item -ItemType Directory -Path $downloadDir | Out-Null }
        $installer = Join-Path $downloadDir $asset.name
        Invoke-WebRequest $asset.browser_download_url -OutFile $installer -UseBasicParsing
        # Not -Wait: in 5.1 that also waits for every process the installer starts, such as the app.
        $process = Start-Process -FilePath $installer -ArgumentList @($Tool.InstallArgs) -PassThru
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { Say "  $($Tool.Id): installer exited $($process.ExitCode)" Yellow }
        return ($process.ExitCode -eq 0)
    } catch {
        Say "  $($Tool.Id): $($_.Exception.Message)" Yellow
        return $false
    } finally {
        if ($installer -and (Test-Path -LiteralPath $installer)) {
            Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- Apply -------------------------------------------------------------------------------------

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Warn "winget not found; winget entries cannot be installed on this machine"
}

Say "Reading $manifestPath" Cyan

# An unknown name is a missing tool in every mode: it fails -Check and holds back the hash, so a
# typo is reported on every run rather than once.
foreach ($name in $selection.Unknown) {
    Warn "machine.local.psd1 opts into '$name', which no tools.psd1 entry declares as Optional"
    $missing++
    if (-not $Check) { $failed++ }
}
foreach ($name in $selection.Available) {
    Say "optional, not on this machine: $name - add it to OptionalTools in $localPath to install it" DarkGray
}

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

    # Before the switch: `continue` inside a switch leaves only the switch.
    if ($source -eq 'github-release') {
        $problem = Test-GitHubReleaseEntry -Tool $tool
        if ($problem) { Warn $problem; $missing++; if (-not $Check) { $failed++ }; continue }
    }

    $present = $false
    switch ($source) {
        'winget' { $present = Test-WingetPackage $id }
        'npm'    { $present = Test-NpmPackage $id }
        'github-release' { $present = Test-GitHubRelease $tool }
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
        'github-release' { $installed = Install-GitHubRelease $tool }
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
