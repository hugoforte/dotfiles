# ~/.ssh/authorized_keys on Windows: a copy of the one overlay's ssh/authorized_keys.
#
#   . (Join-Path $PSScriptRoot "authorized-keys.ps1")
#   Set-AuthorizedKeysCopy    -Path "$env:USERPROFILE\.ssh\authorized_keys" -Source $source
#   Test-AuthorizedKeysCopy   -Path "$env:USERPROFILE\.ssh\authorized_keys" -Source $source
#   Remove-AuthorizedKeysCopy -Path "$env:USERPROFILE\.ssh\authorized_keys" [-Check]
#
# A copy, where the other managed files are links (managed-link.ps1): Windows sshd checks the
# ownership and access of the file it reads, and whether it judges a link by the link or by its
# target is not something to find out from a locked-out machine. The copy is a generated file
# (generated-file.ps1): it opens with a header naming its source, so a later run replaces its own
# copy freely and backs up a file someone else wrote. With no overlay shipping the keys any more,
# its own copy is removed, so a key taken away stops working.
#
# Admin accounts read this file only once sshd_config's `Match Group administrators` block is
# gone; by default they read C:\ProgramData\ssh\administrators_authorized_keys, which only an
# elevated process can write, and the sync runs unelevated.

. (Join-Path $PSScriptRoot "generated-file.ps1")

$script:AuthorizedKeysHeaderPrefix = '# Written by dotfiles from '

# What the copy of $Source holds: the header, then the keys with LF line endings. The header is a
# comment, which sshd skips.
function Get-AuthorizedKeysContent {
    param([Parameter(Mandatory)][string]$Source)
    $keys = [IO.File]::ReadAllText($Source) -replace "`r`n", "`n"
    return "$script:AuthorizedKeysHeaderPrefix$Source; the next sync replaces any edit made here.`n$keys"
}

# Reports the state of the copy and changes nothing.
# Reason is one of: Correct, Missing, Stale, NotOurs.
function Test-AuthorizedKeysCopy {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source
    )

    $state = Test-GeneratedFile -Path $Path -Content (Get-AuthorizedKeysContent -Source $Source) -HeaderPrefix $script:AuthorizedKeysHeaderPrefix
    return [pscustomobject]@{
        Path      = $Path
        Source    = $Source
        IsCorrect = $state.IsCorrect
        Reason    = $state.Reason
    }
}

# Makes $Path a current copy of $Source, and says what it had to do to get there.
# Action is one of: AlreadyCorrect, Created, Updated, BackedUpAndWritten.
# BackupPath is set only when a file this did not write was displaced.
function Set-AuthorizedKeysCopy {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Cannot write $Path : source $Source does not exist."
    }

    $result = Set-GeneratedFile -Path $Path -Content (Get-AuthorizedKeysContent -Source $Source) -HeaderPrefix $script:AuthorizedKeysHeaderPrefix
    return [pscustomobject]@{ Path = $Path; Source = $Source; Action = $result.Action; BackupPath = $result.BackupPath }
}

# Removes $Path when it is a copy this module wrote: for a machine whose overlays no longer ship
# ssh/authorized_keys. A file anyone else wrote is left alone. -Check says what it would do.
# Action is one of: Removed, NotOurs, Missing.
function Remove-AuthorizedKeysCopy {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Check
    )

    return Remove-GeneratedFile -Path $Path -HeaderPrefix $script:AuthorizedKeysHeaderPrefix -Check:$Check
}
