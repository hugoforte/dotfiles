# The managed link: one implementation of "point this path at that file in the repo".
#
#   . (Join-Path $PSScriptRoot "managed-link.ps1")
#   Set-ManagedLink    -Path $PROFILE -Source "$repo\powershell\profile.ps1"
#   Test-ManagedLink   -Path $PROFILE -Source "$repo\powershell\profile.ps1"
#   Remove-ManagedLink -Path $PROFILE
#   Remove-DanglingManagedLink -Path "$HOME\.gitconfig-old" -Under $repo
#
# Each returns a result object rather than printing one, so a caller decides what to say and
# an exit code can be derived from outcomes (powershell/output.ps1, hugoforte/dotfiles#9).
#
# --- Why cmd /c mklink, and not New-Item -ItemType SymbolicLink -------------------------------
#
# Measured on Windows 11, PowerShell 5.1, unelevated, Developer Mode on:
#
#   New-Item -ItemType SymbolicLink   FAILS  "Administrator privilege required for this operation."
#   cmd /c mklink                     WORKS
#
# Developer Mode is necessary and not sufficient: PowerShell 5.1 never passes
# SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE, so its cmdlet cannot benefit from it. cmd's
# mklink does. This is the platform fact the repo previously held in three contradictory
# versions - setup.ps1 self-elevated to work around the cmdlet, deploy-secrets.ps1 had it right,
# and tools.psd1 declared Developer Mode enough. It lives here now, once.
#
# setup.ps1 still self-elevates, but for a different reason: it runs install-tools.ps1, and
# winget installs at machine scope only when elevated. That is what the elevation earns.

$script:ManagedLinkBackupFormat = 'yyyyMMdd_HHmmss'

# The target of a link, as one string. PowerShell 5.1 hands Target back as a collection for
# some reparse points and a bare string for others; callers should not have to know which.
function Get-LinkTarget {
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)
    if ($Item.LinkType -ne 'SymbolicLink') { return $null }
    return ($Item.Target | Select-Object -First 1)
}

function Get-ManagedLinkItem {
    param([Parameter(Mandatory)][string]$Path)
    return Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

# --- Test -------------------------------------------------------------------------------------

# Reports the state of one managed link and changes nothing.
# Reason is one of: Correct, Missing, NotALink, WrongTarget.
function Test-ManagedLink {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source
    )

    $item = Get-ManagedLinkItem $Path
    $actual = if ($item) { Get-LinkTarget -Item $item } else { $null }

    $reason =
        if (-not $item) { 'Missing' }
        elseif ($item.LinkType -ne 'SymbolicLink') { 'NotALink' }
        elseif ($actual -ne $Source) { 'WrongTarget' }
        else { 'Correct' }

    return [pscustomobject]@{
        Path         = $Path
        Source       = $Source
        IsCorrect    = ($reason -eq 'Correct')
        Reason       = $reason
        ActualTarget = $actual
    }
}

# --- Set --------------------------------------------------------------------------------------

# Moves whatever real file is at $Path out of the way and returns where it went. A symlink is
# not backed up: it holds no content of its own, so there is nothing to lose.
function Move-DisplacedFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$BackupDir
    )

    $stamp = Get-Date -Format $script:ManagedLinkBackupFormat
    $name = "$(Split-Path $Path -Leaf).backup.$stamp"

    if ($BackupDir) {
        if (-not (Test-Path -LiteralPath $BackupDir)) {
            New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        }
        $backup = Join-Path $BackupDir $name
    } else {
        $backup = Join-Path (Split-Path $Path -Parent) $name
    }

    Move-Item -LiteralPath $Path -Destination $backup
    return $backup
}

function New-SymlinkViaMklink {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source
    )
    $out = cmd /c mklink "`"$Path`"" "`"$Source`"" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Path)) {
        throw "mklink failed for $Path -> $Source (enable Developer Mode or run elevated): $($out.Trim())"
    }
}

# Makes $Path a symlink to $Source, and says what it had to do to get there.
# Action is one of: AlreadyCorrect, Created, Repointed, BackedUpAndLinked.
# BackupPath is set only when a real file was displaced.
function Set-ManagedLink {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source,
        [string]$BackupDir
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Cannot link $Path : source $Source does not exist."
    }
    if (Test-Path -LiteralPath $Source -PathType Container) {
        # mklink without /D against a directory makes a file symlink that never resolves.
        # Nothing here links a directory; ai/install.sh does its own with `ln -s`.
        throw "Cannot link $Path : source $Source is a directory, and this module links files."
    }

    $state = Test-ManagedLink -Path $Path -Source $Source
    if ($state.IsCorrect) {
        return [pscustomobject]@{ Path = $Path; Source = $Source; Action = 'AlreadyCorrect'; BackupPath = $null }
    }

    $backup = $null
    $action = 'Created'

    if ($state.Reason -eq 'WrongTarget') {
        (Get-ManagedLinkItem $Path).Delete()
        $action = 'Repointed'
    } elseif ($state.Reason -eq 'NotALink') {
        $backup = Move-DisplacedFile -Path $Path -BackupDir $BackupDir
        $action = 'BackedUpAndLinked'
    }

    $parent = Split-Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    New-SymlinkViaMklink -Path $Path -Source $Source

    return [pscustomobject]@{ Path = $Path; Source = $Source; Action = $action; BackupPath = $backup }
}

# --- Remove -----------------------------------------------------------------------------------

# Removes $Path only when it is a symlink. A real file at a managed path is someone's work and
# is never deleted here - the caller is told and decides.
# Action is one of: Removed, NotALink, Missing.
function Remove-ManagedLink {
    param([Parameter(Mandatory)][string]$Path)

    $item = Get-ManagedLinkItem $Path
    if (-not $item) {
        return [pscustomobject]@{ Path = $Path; Action = 'Missing' }
    }
    if ($item.LinkType -ne 'SymbolicLink') {
        return [pscustomobject]@{ Path = $Path; Action = 'NotALink' }
    }

    # .Delete() on the item, not Remove-Item: against a directory symlink PowerShell 5.1's
    # Remove-Item can recurse through the reparse point and take the target's contents with it.
    $item.Delete()
    return [pscustomobject]@{ Path = $Path; Action = 'Removed' }
}

# --- Prune ------------------------------------------------------------------------------------

# Removes $Path when it is a symlink into $Under whose target no longer exists: a managed link
# left behind after its source was deleted from the repo. A link that still resolves, a link
# pointing anywhere else, and a real file are all kept.
# Action is one of: Removed, Kept, Missing.
function Remove-DanglingManagedLink {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Under
    )

    $item = Get-ManagedLinkItem $Path
    if (-not $item) {
        return [pscustomobject]@{ Path = $Path; Action = 'Missing' }
    }

    $target = Get-LinkTarget -Item $item
    $prefix = $Under.TrimEnd('\') + '\'
    $dangling = $target -and
        $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and
        -not (Test-Path -LiteralPath $target)
    if (-not $dangling) {
        return [pscustomobject]@{ Path = $Path; Action = 'Kept' }
    }

    return Remove-ManagedLink -Path $Path
}
