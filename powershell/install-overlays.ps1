# Adds an overlay repo to this machine: clones it beside the dotfiles checkout (or pulls it if it
# is already there), lists its overlays in ai/secrets/machine.local.psd1, then runs sync.ps1,
# which applies them and keeps them current from then on. See ai/secrets/README.md.
#
#   install-overlays.ps1 -Repo owner/name                 every overlay in the repo
#   install-overlays.ps1 -Repo owner/name -Only company   just the named ones
#   install-overlays.ps1 -Repo owner/name -Path D:\x      clone somewhere other than beside dotfiles
#
# Idempotent: run it again after the overlay repo gains an overlay. The new list is checked
# before it is written, so a machine is never left listing overlays that clash with this repo.

param(
    [Parameter(Mandatory)][string]$Repo,
    [string]$Path,
    [string[]]$Only
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "output.ps1")
. (Join-Path $PSScriptRoot "overlays.ps1")
. (Join-Path $PSScriptRoot "native.ps1")

$repoRoot = Split-Path $PSScriptRoot -Parent
$localPath = Join-Path $repoRoot "ai\secrets\machine.local.psd1"
$result = New-ScriptResult -Name "install-overlays.ps1"

# --- This checkout first --------------------------------------------------------------------------
# An overlay holds what this repo used to; the check below would fail against a stale checkout.

$pull = Invoke-Native git -C $repoRoot pull --ff-only
if (-not $pull.Ok) {
    Fail "git pull in $repoRoot failed: $($pull.Output)"
    Exit-WithResult $result 1
}
Ok "$repoRoot is up to date"

# --- Clone or pull the overlay repo ---------------------------------------------------------------

$url = if ($Repo -match '^(https?://|git@)') { $Repo } else { "https://github.com/$Repo.git" }
$name = ($Repo -split '[/:]')[-1] -replace '\.git$', ''
if (-not $Path) { $Path = Join-Path (Split-Path $repoRoot -Parent) $name }
$Path = [IO.Path]::GetFullPath($Path)

if (Test-Path -LiteralPath (Join-Path $Path ".git")) {
    $overlayPull = Invoke-Native git -C $Path pull --ff-only
    if (-not $overlayPull.Ok) {
        Fail "git pull in $Path failed: $($overlayPull.Output)"
        Exit-WithResult $result 1
    }
    Ok "$Path is up to date"
} elseif (Test-Path -LiteralPath $Path) {
    Fail "$Path exists and is not a git checkout; pass -Path to clone somewhere else"
    Exit-WithResult $result 1
} else {
    $clone = Invoke-Native git clone $url $Path
    if (-not $clone.Ok) {
        Fail "git clone $url failed: $($clone.Output)"
        Exit-WithResult $result 1
    }
    Change "cloned $url to $Path"
}

# --- Which overlays -------------------------------------------------------------------------------
# Every top-level directory of the repo is an overlay, unless -Only names some.

$available = @(Get-ChildItem -LiteralPath $Path -Directory | Where-Object { -not $_.Name.StartsWith('.') })
if ($Only) {
    $unknown = @($Only | Where-Object { $available.Name -notcontains $_ })
    if ($unknown.Count) {
        Fail "$Path has no overlay named $($unknown -join ', '); it has $($available.Name -join ', ')"
        Exit-WithResult $result 1
    }
    $available = @($available | Where-Object { $Only -contains $_.Name })
}
if ($available.Count -eq 0) {
    Fail "$Path has no overlay directories"
    Exit-WithResult $result 1
}
$selected = @($available | ForEach-Object { $_.FullName })

# --- Work out the new list, and check it before writing it ----------------------------------------

if (-not (Test-Path -LiteralPath $localPath)) {
    Copy-Item -LiteralPath "$localPath.example" -Destination $localPath
    Change "created $localPath from the example; check its SearchRoots"
}

try {
    $existing = @(Get-OverlayList -LocalPath $localPath)
    # Overlays from other repos stay; this repo's are replaced by the selection, in its order.
    $prefix = $Path.TrimEnd('\') + '\'
    $kept = @($existing | Where-Object { -not ([IO.Path]::GetFullPath($_) + '\').StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) })
    $overlays = @($kept) + $selected

    Get-MergedSkillRegistry -Roots (@($repoRoot) + $overlays) | Out-Null
    Find-OverlayFile -Roots (@($repoRoot) + $overlays) -RelativePath "aws\config" | Out-Null
} catch {
    Fail "$($_.Exception.Message). Nothing was written. If this checkout still carries what the overlay now holds, the change that moved it out has not reached this branch yet."
    Exit-WithResult $result 1
}

if ((@($existing) -join "`n") -eq ($overlays -join "`n")) {
    Ok "machine.local.psd1 already lists $($selected.Count) overlay(s) from $Path"
} else {
    Set-OverlayListInFile -LocalPath $localPath -Overlays $overlays
    Change "machine.local.psd1 now lists: $($overlays -join ', ')"
}

# --- Apply ----------------------------------------------------------------------------------------
# sync.ps1 is the one applier: it links their skills (through ai/install.sh), pulls the overlays,
# writes ~/.gitconfig-overlays, links ~/.aws/config, removes links left behind by files that
# moved out, and deploys the secrets.

Say ""
Say "Running sync.ps1 to apply them" Cyan
& (Join-Path $PSScriptRoot "sync.ps1")
if ($LASTEXITCODE -ne 0) {
    Fail "sync.ps1 exited $LASTEXITCODE; see %LOCALAPPDATA%\dotfiles\sync.log"
    Exit-WithResult $result 1
}

Say ""
Summary Ok "Overlays from $Path are in place."
Exit-WithResult $result 0
