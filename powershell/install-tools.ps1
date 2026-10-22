# Install the tools declared in tools.psd1, and in the powershell/tools.psd1 of each overlay.
#
#   install-tools.ps1              install everything missing; report manual steps
#   install-tools.ps1 -Check       report only; exit 1 if anything is missing
#   install-tools.ps1 -Unattended  install only entries safe to install unwatched
#   install-tools.ps1 -IfChanged   install nothing unless a manifest or the options have changed since the last run;
#                                  Configure scripts still run
#   install-tools.ps1 -PassThru    also return the result object, for a caller that reads it
#
# Idempotent: entries install only when missing. Nothing is ever upgraded or uninstalled -
# a program on the machine and not in the manifest was installed on purpose. An entry with a
# Configure script has it run once the program is present, on every run.
#
# Optional entries install only on a machine that opts into them, in machine.local.psd1 or in an
# overlay's machines/<KEY>.psd1: see tool-selection.ps1.
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
. (Join-Path $PSScriptRoot "overlays.ps1")
. (Join-Path $PSScriptRoot "native.ps1")

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

if (@((Import-PowerShellDataFile $manifestPath).Tools).Count -eq 0) {
    Fail "tools.psd1 declares no tools"
    Exit-WithResult $result 1
}

try {
    $overlaySet = Get-Overlays -RepoPath (Split-Path $PSScriptRoot -Parent)
    $manifestPaths = @(Get-OverlaySource -Set $overlaySet -Path "powershell/tools.psd1")
    $allTools = @(Get-MergedToolManifest -Path $manifestPaths)
    $machinePath = Get-OverlaySource -Set $overlaySet -Path "machines/{KEY}.psd1"
    $optedIn = @(Get-OptedInOptionList -Path (@($localPath) + @($machinePath | Where-Object { $_ })))
} catch {
    Fail "could not read the manifests or the options: $($_.Exception.Message)"
    Exit-WithResult $result 1
}
$selection = Select-MachineTools -Tools $allTools -OptedIn $optedIn
$tools = $selection.Selected

$manifestHash = Get-ToolStateHash -ManifestPath $manifestPaths -OptedIn $optedIn

# Unchanged since the last successful run: nothing to install, but a Configure script still runs,
# because what it applies lives outside the manifests and can change, or drift, on its own.
$configureOnly = $false
if ($IfChanged) {
    $applied = $null
    if (Test-Path $statePath) { $applied = (Get-Content $statePath -Raw).Trim() }
    if ($applied -eq $manifestHash) {
        $tools = @($tools | Where-Object { $_.Configure })
        if ($tools.Count -eq 0) {
            Ok "manifests and options unchanged since the last successful run; nothing to do"
            Exit-WithResult $result 0
        }
        Ok "manifests and options unchanged since the last successful run; only configuring"
        $configureOnly = $true
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

# Through Invoke-Native: uv writes its notes to stderr, which would otherwise stop this script.
$script:uvTools = $null
function Get-UvTools {
    if ($null -ne $script:uvTools) { return $script:uvTools }
    $list = Invoke-Native uv tool list
    $script:uvTools = @(if ($list.Ok) { Get-UvToolNames -ListOutput $list.Output })
    return $script:uvTools
}

function Test-UvTool {
    param([string]$Id)
    return ((Get-UvTools) -contains $Id)
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

function Test-InstalledProgram {
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

function Install-UvTool {
    param([string]$Id)
    $install = Invoke-Native uv tool install $Id
    if (-not $install.Ok) { Say "  $Id`: $($install.Output)" Yellow }
    return $install.Ok
}

# Downloads an installer and runs it with the entry's InstallArgs: for a github-release entry, the
# latest release's asset; for a download entry, its Url. The reason for a failure is printed; the
# caller records the one outcome.
function Install-Downloaded {
    param([hashtable]$Tool)
    # 5.1 redraws its progress bar per chunk, which makes a large download crawl.
    $ProgressPreference = 'SilentlyContinue'
    $installer = $null
    try {
        if ($Tool.Source -eq 'download') {
            $name = [IO.Path]::GetFileName(([Uri]$Tool.Url).AbsolutePath)
            $url = $Tool.Url
        } else {
            $release = Invoke-RestMethod "https://api.github.com/repos/$($Tool.Id)/releases/latest" -UseBasicParsing
            $asset = Select-ReleaseAsset -Assets @($release.assets) -Pattern $Tool.Asset
            $name = $asset.name
            $url = $asset.browser_download_url
        }
        $downloadDir = Join-Path $env:TEMP "dotfiles-tools"
        if (-not (Test-Path $downloadDir)) { New-Item -ItemType Directory -Path $downloadDir | Out-Null }
        $installer = Join-Path $downloadDir $name
        Invoke-WebRequest $url -OutFile $installer -UseBasicParsing
        # A fixed address can start serving something else; only the installer the entry names runs.
        if ($Tool.Sha256) {
            $actual = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
            if ($actual -ne $Tool.Sha256) {
                Say "  $($Tool.Id): $url has SHA-256 $actual, not the entry's $($Tool.Sha256); not run" Yellow
                return $false
            }
        }
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

# Runs an entry's Configure script in its own process, with -Check when this run only reports.
# The script sets the program up as the declaring repo wants it, changing only what has drifted,
# and exits non-zero when it failed or, under -Check, when something has drifted. Through
# Invoke-Native, so a script's stderr cannot end this run. Its output is printed; on failure its
# last lines go into the warning too, since -Quiet keeps printed lines out of the sync's log.
function Invoke-Configure {
    param([hashtable]$Tool)
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Tool.Configure)
    if ($Check) { $arguments += '-Check' }
    $run = Invoke-Native powershell @arguments
    foreach ($line in ($run.Output -split "`r?`n" | Where-Object { $_ })) { Say "  $line" }
    $tail = (@($run.Output -split "`r?`n" | Where-Object { $_ }) | Select-Object -Last 3) -join ' | '
    return [pscustomobject]@{ Ok = $run.Ok; Tail = $tail }
}

# --- Apply -------------------------------------------------------------------------------------

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Warn "winget not found; winget entries cannot be installed on this machine"
}
# uv arrives through winget on the same run as the tools it installs, so on the run that
# installs it this shell cannot see it yet; the next run can.
if (@($tools | Where-Object { $_.Source -eq 'uv' }).Count -and -not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Warn "uv not found; uv entries cannot be installed until it is (winget install astral-sh.uv, then open a new shell)"
}

foreach ($path in $manifestPaths) { Say "Reading $path" Cyan }
if ($machinePath) { Say "Reading $machinePath" Cyan }
# Only where an overlay has machines/ at all, so a misnamed file there is not silent and a machine
# whose overlays keep no machine files is not warned.
if (-not $machinePath) {
    foreach ($dir in (Get-OverlaySource -Set $overlaySet -Path "machines/")) {
        Warn "no $($overlaySet.MachineKey).psd1 in $dir - this machine's options come from machine.local.psd1 alone"
    }
}

# An unknown name is a missing tool in every mode: it fails -Check and holds back the hash, so a
# typo is reported on every run rather than once. A configure-only run is past that point.
if (-not $configureOnly) {
    foreach ($name in $selection.Unknown) {
        Warn "this machine opts into '$name', which no tools.psd1 entry declares as Optional"
        $missing++
        if (-not $Check) { $failed++ }
    }
    $optInPath = if ($machinePath) { $machinePath } else { $localPath }
    foreach ($name in $selection.Available) {
        Say "optional, not on this machine: $name - add it to OptionalTools in $optInPath to install it" DarkGray
    }
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

    # Before the switch: `continue` inside a switch leaves only the switch. Without Node there is
    # no npm, and calling it would end the run before the manual steps that say how to get Node.
    if ($source -eq 'npm' -and -not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Warn "$id missing (npm) - npm is not on PATH: install Node.js first, as the manual steps below say"
        $missing++
        if (-not $Check) { $failed++ }
        continue
    }
    # Here rather than as the switch's default, whose `continue` would leave only the switch and
    # count the entry as a failed install.
    if ($source -notin 'winget', 'npm', 'uv', 'github-release', 'download') {
        Warn "$id has unknown Source '$source'; skipped"
        continue
    }
    if ($source -in 'github-release', 'download') {
        $problem = Test-InstallerEntry -Tool $tool
        if ($problem) { Warn $problem; $missing++; if (-not $Check) { $failed++ }; continue }
    }

    $present = $false
    switch ($source) {
        'winget' { $present = Test-WingetPackage $id }
        'npm'    { $present = Test-NpmPackage $id }
        'uv'     { $present = Test-UvTool $id }
        { $_ -in 'github-release', 'download' } { $present = Test-InstalledProgram $tool }
    }

    if ($present) {
        Ok "$id"
    } elseif ($configureOnly) {
        # Deferred, or not installed for a reason the run that recorded the hash already reported.
        continue
    } else {
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
            'uv'     { $installed = Install-UvTool $id }
            { $_ -in 'github-release', 'download' } { $installed = Install-Downloaded $tool }
        }

        if (-not $installed) {
            $failed++
            Warn "$id failed to install ($source)"
            continue
        }
        Ok "$id installed"
    }

    if ($tool.Configure) {
        $configured = Invoke-Configure $tool
        if ($configured.Ok) {
            Ok "$id configured"
        } elseif ($Check) {
            $missing++
            Warn "$id not configured as declared ($($configured.Tail)): run $($tool.Configure)"
        } else {
            $failed++
            Warn "$id failed to configure ($($configured.Tail)): $($tool.Configure)"
        }
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

if (-not $Check -and -not $configureOnly -and $failed -eq 0) {
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
    Set-Content -Path $statePath -Value $manifestHash -Encoding utf8
}

# Each of these counts outcomes reported per tool above, so they go through Summary and are
# not recorded a second time.
Say ""
if ($Check) {
    if ($missing -gt 0) { Summary Warn "$missing tool(s) missing or not configured as declared"; Exit-WithResult $result 1 }
    Summary Ok "every declared tool is installed and configured"
    Exit-WithResult $result 0
}

if ($deferred -gt 0) { Summary Warn "$deferred tool(s) skipped as not safe to install unwatched - run powershell\install-tools.ps1 when convenient" }
if ($failed -gt 0) { Summary Warn "$failed tool(s) failed to install or configure"; Exit-WithResult $result 1 }
Summary Ok "tools up to date"
Exit-WithResult $result 0
