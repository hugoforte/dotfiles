# ~/.ssh/authorized_keys on Windows: a copy of the one overlay's ssh/authorized_keys.
#
#   . (Join-Path $PSScriptRoot "authorized-keys.ps1")
#   Set-AuthorizedKeysCopy    -Path "$env:USERPROFILE\.ssh\authorized_keys" -Source $source
#   Test-AuthorizedKeysCopy   -Path "$env:USERPROFILE\.ssh\authorized_keys" -Source $source
#   Remove-AuthorizedKeysCopy -Path "$env:USERPROFILE\.ssh\authorized_keys" [-Check]
#
# A copy, where every other managed file is a link (managed-link.ps1): Windows sshd checks the
# ownership and access of the file it reads, and whether it judges a link by the link or by its
# target is not something to find out from a locked-out machine. The copy opens with a header
# naming its source, which is how a later run tells its own copy, replaced freely, from a file
# someone else wrote, which is backed up first (docs/adr/0003-back-up-then-link.md). With no
# overlay shipping the keys any more, its own copy is removed, so a key taken away stops working.
#
# Admin accounts read this file only once sshd_config's `Match Group administrators` block is
# gone; by default they read C:\ProgramData\ssh\administrators_authorized_keys, which only an
# elevated process can write, and the sync runs unelevated.

. (Join-Path $PSScriptRoot "managed-link.ps1")

$script:AuthorizedKeysHeaderPrefix = '# Written by dotfiles from '

# What the copy of $Source holds: the header, then the keys with LF line endings.
function Get-AuthorizedKeysContent {
    param([Parameter(Mandatory)][string]$Source)
    $keys = [IO.File]::ReadAllText($Source) -replace "`r`n", "`n"
    return "$script:AuthorizedKeysHeaderPrefix$Source; the next sync replaces any edit made here.`n$keys"
}

# Whether $Path is a regular file this module wrote. A link is never its own: it writes a copy.
function Test-AuthorizedKeysCopyIsOurs {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-ManagedLinkItem $Path
    if (-not $item -or $item.LinkType) { return $false }
    return [IO.File]::ReadAllText($Path).StartsWith($script:AuthorizedKeysHeaderPrefix, [StringComparison]::Ordinal)
}

# Reports the state of the copy and changes nothing.
# Reason is one of: Correct, Missing, Stale, NotOurs.
function Test-AuthorizedKeysCopy {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source
    )

    # Get-Item, not Test-Path, which reads a dangling link as nothing there.
    $reason =
        if (-not (Get-ManagedLinkItem $Path)) { 'Missing' }
        elseif (-not (Test-AuthorizedKeysCopyIsOurs -Path $Path)) { 'NotOurs' }
        elseif ([string]::Equals([IO.File]::ReadAllText($Path), (Get-AuthorizedKeysContent -Source $Source), [StringComparison]::Ordinal)) { 'Correct' }
        else { 'Stale' }

    return [pscustomobject]@{
        Path      = $Path
        Source    = $Source
        IsCorrect = ($reason -eq 'Correct')
        Reason    = $reason
    }
}

# Makes $Path a current copy of $Source, and says what it had to do to get there.
# Action is one of: AlreadyCorrect, Created, Updated, BackedUpAndWritten.
# BackupPath is set only when a file this did not write was displaced; a link holds no content of
# its own, so it is removed without one.
function Set-AuthorizedKeysCopy {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Cannot write $Path : source $Source does not exist."
    }

    $state = Test-AuthorizedKeysCopy -Path $Path -Source $Source
    if ($state.IsCorrect) {
        return [pscustomobject]@{ Path = $Path; Source = $Source; Action = 'AlreadyCorrect'; BackupPath = $null }
    }

    $backup = $null
    $action = switch ($state.Reason) {
        'Missing' { 'Created' }
        'Stale'   { 'Updated' }
        'NotOurs' { 'BackedUpAndWritten' }
    }
    $item = Get-ManagedLinkItem $Path
    if ($item -and $item.LinkType) {
        $item.Delete()
        $action = 'Created'
    } elseif ($state.Reason -eq 'NotOurs') {
        $backup = Move-DisplacedFile -Path $Path
    }

    $parent = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    # Written beside it and swapped in, so sshd never reads a half-written file. Without a
    # byte-order mark: sshd reads one as part of the first line, and PowerShell 5.1's
    # Set-Content -Encoding UTF8 writes one, so this goes through .NET.
    $staged = "$Path.dotfiles-new"
    [IO.File]::WriteAllText($staged, (Get-AuthorizedKeysContent -Source $Source), (New-Object Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $Path) {
        # No backup file: PowerShell would pass $null to a string parameter as "".
        [IO.File]::Replace($staged, $Path, [NullString]::Value)
    } else {
        [IO.File]::Move($staged, $Path)
    }

    return [pscustomobject]@{ Path = $Path; Source = $Source; Action = $action; BackupPath = $backup }
}

# Removes $Path when it is a copy this module wrote: for a machine whose overlays no longer ship
# ssh/authorized_keys. A file anyone else wrote is left alone. -Check says what it would do.
# Action is one of: Removed, NotOurs, Missing.
function Remove-AuthorizedKeysCopy {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Check
    )

    if (-not (Get-ManagedLinkItem $Path)) { return [pscustomobject]@{ Path = $Path; Action = 'Missing' } }
    if (-not (Test-AuthorizedKeysCopyIsOurs -Path $Path)) { return [pscustomobject]@{ Path = $Path; Action = 'NotOurs' } }
    if (-not $Check) { Remove-Item -LiteralPath $Path }
    return [pscustomobject]@{ Path = $Path; Action = 'Removed' }
}
