# Pull the dotfiles repo and its overlays, and re-apply the AI tooling links, what the overlays
# supply, and the skill secrets.
# Safe to run unattended: fast-forward only, never commits or pushes.
# Used by the "Dotfiles Sync" scheduled task (see install-sync-task.ps1) and the dotfiles-sync function.

param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "output.ps1")
. (Join-Path $PSScriptRoot "native.ps1")

$repoRoot = Split-Path $PSScriptRoot -Parent
$logDir = Join-Path $env:LOCALAPPDATA "dotfiles"
$logFile = Join-Path $logDir "sync.log"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Add-Content -Path $logFile -Value $line
    if (-not $Quiet) { Write-Host $line }
}

# The sync.log adapter over a child script's result: what it did, then the lines worth keeping.
# The child reports through Write-Host too, but that is the information stream and does not
# survive the call - the result does.
function Write-ResultLog {
    param([psobject]$Result)
    if (-not $Result) {
        Write-Log "no result returned (the script exited before reporting one)"
        return
    }
    Write-Log (Get-ResultSummary $Result)
    foreach ($line in (Get-ResultLines $Result -Kinds Warn, Error, Todo)) { Write-Log "  $line" }
}

function Find-Sh {
    # Git Bash's sh.exe lives next to git: <Git>\cmd\git.exe -> <Git>\bin\sh.exe
    $git = (Get-Command git -ErrorAction SilentlyContinue).Source
    if ($git) {
        $gitRoot = Split-Path (Split-Path $git -Parent) -Parent
        foreach ($candidate in @("$gitRoot\bin\sh.exe", "$gitRoot\usr\bin\sh.exe")) {
            if (Test-Path $candidate) { return $candidate }
        }
    }
    foreach ($candidate in @("$env:ProgramFiles\Git\bin\sh.exe", "$env:LOCALAPPDATA\Programs\Git\bin\sh.exe")) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

Write-Log "sync start ($repoRoot)"

Push-Location $repoRoot
try {
    $status = git status --porcelain
    if ($status) {
        Write-Log "working tree dirty; pulling anyway (ff-only) but local changes are yours to commit"
    }

    $before = git rev-parse HEAD
    $pull = Invoke-Native git pull --ff-only
    if (-not $pull.Ok) {
        Write-Log "git pull failed: $($pull.Output)"
        exit 1
    }
    $after = git rev-parse HEAD
    if ($before -eq $after) {
        Write-Log "already up to date at $($after.Substring(0,7))"
    } else {
        Write-Log "updated $($before.Substring(0,7)) -> $($after.Substring(0,7))"
    }

    $sh = Find-Sh
    if (-not $sh) {
        Write-Log "sh.exe (Git Bash) not found; skipping ai/install.sh"
        exit 1
    }

    # install.sh colours its output; the escape sequences are noise in a log file.
    $install = Invoke-Native $sh "$repoRoot/ai/install.sh"
    if (-not $install.Ok) {
        Write-Log "ai/install.sh failed:`n$(Remove-AnsiEscape $install.Output)"
        exit 1
    }
    Write-Log "ai/install.sh ok"

    # bin/ on the user PATH, so a machine set up before bin/ existed picks it up without setup.ps1.
    . (Join-Path $PSScriptRoot "user-path.ps1")
    $binPath = Join-Path $repoRoot "bin"
    if ((Add-UserPathEntry -Directory $binPath) -eq 'Added') { Write-Log "added $binPath to the user PATH" }

    # Tools: only when tools.psd1 has changed since the last successful run, and only the
    # entries marked safe to install unwatched - this task must never raise a UAC prompt.
    $toolsResult = & (Join-Path $PSScriptRoot "install-tools.ps1") -IfChanged -Unattended -Quiet -PassThru
    $toolsExit = $LASTEXITCODE
    Write-ResultLog $toolsResult
    if ($toolsExit -ne 0) {
        Write-Log "install-tools.ps1 exited $toolsExit"
        exit 1
    }

    # Overlays (see overlays.ps1): pull each overlay repo, then bring what they supply in line, so
    # a change pushed to an overlay reaches this machine without anyone re-running setup.ps1.
    . (Join-Path $PSScriptRoot "managed-link.ps1")
    . (Join-Path $PSScriptRoot "overlays.ps1")
    try {
        $overlays = Get-OverlayList -LocalPath (Join-Path $repoRoot "ai\secrets\machine.local.psd1")
    } catch {
        Write-Log $_.Exception.Message
        exit 1
    }
    # A failed overlay pull leaves that overlay as it was, which the steps below can still apply;
    # stopping here would leave the links and secrets stale until someone read this log.
    $overlayPullFailed = $false
    foreach ($overlayRepo in (Get-OverlayRepoRoots -Overlays $overlays)) {
        $overlayPull = Invoke-Native git -C $overlayRepo pull --ff-only
        if (-not $overlayPull.Ok) {
            Write-Log "git pull failed in $overlayRepo`: $($overlayPull.Output)"
            $overlayPullFailed = $true
            continue
        }
        Write-Log "pulled $overlayRepo"
    }
    Write-Log "~/.gitconfig-overlays: $(Update-GitOverlayInclude -Overlays $overlays)"

    # A link into this repo whose source the repo no longer ships is left over from a file that
    # moved out, to an overlay or away entirely.
    $awsConfigPath = "$env:USERPROFILE\.aws\config"
    $leftovers = @(Get-ChildItem -LiteralPath $env:USERPROFILE -Filter ".gitconfig-*" -Force | ForEach-Object { $_.FullName }) + $awsConfigPath
    foreach ($path in $leftovers) {
        if ((Remove-DanglingManagedLink -Path $path -Under $repoRoot).Action -eq 'Removed') {
            Write-Log "removed $path`: its source is no longer in the repo"
        }
    }

    try {
        $awsSource = Find-OverlayFile -Roots (@($repoRoot) + $overlays) -RelativePath "aws\config"
    } catch {
        Write-Log $_.Exception.Message
        exit 1
    }
    if ($awsSource) {
        $awsLink = Set-ManagedLink -Path $awsConfigPath -Source $awsSource
        if ($awsLink.Action -ne 'AlreadyCorrect') { Write-Log "~/.aws/config -> $awsSource ($($awsLink.Action))" }
    } elseif (-not (Test-Path -LiteralPath $awsConfigPath)) {
        Write-Log "no aws/config in the repo or any overlay, and ~/.aws/config is absent; if this machine should have one, run install-overlays.ps1"
    }

    # Skill secrets: only on machines whose machine.local.psd1 declares SearchRoots
    if (Test-SkillSecretsOptIn -LocalPath (Join-Path $repoRoot "ai\secrets\machine.local.psd1")) {
        $secretsResult = & (Join-Path $PSScriptRoot "deploy-secrets.ps1") -Quiet -PassThru
        $secretsExit = $LASTEXITCODE
        Write-ResultLog $secretsResult
        if ($secretsExit -ne 0) {
            Write-Log "deploy-secrets.ps1 exited $secretsExit"
            exit 1
        }
    } else {
        Write-Log "deploy-secrets.ps1 skipped (no SearchRoots in ai/secrets/machine.local.psd1)"
    }

    if ($overlayPullFailed) {
        Write-Log "sync finished, but an overlay repo could not be pulled (above)"
        exit 1
    }
}
catch {
    # Anything not foreseen above would otherwise end the run with nothing in sync.log.
    Write-Log "sync failed at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    exit 1
}
finally {
    Pop-Location
}

Write-Log "sync done"
