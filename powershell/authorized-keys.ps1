# ~/.ssh/authorized_keys on Windows: a copy of the one overlay's ssh/authorized_keys.
#
#   . (Join-Path $PSScriptRoot "authorized-keys.ps1")
#   Set-AuthorizedKeysCopy  -Path "$env:USERPROFILE\.ssh\authorized_keys" -Source $source
#   Test-AuthorizedKeysCopy -Path "$env:USERPROFILE\.ssh\authorized_keys" -Source $source
#
# A copy, where every other managed file is a link (managed-link.ps1): Windows sshd checks the
# ownership and access of the file it reads, and whether it judges a link by the link or by its
# target is not something to find out from a locked-out machine. The copy opens with a header
# naming its source, which is how a later run tells its own copy, replaced freely, from a file
# someone else wrote, which is backed up first (docs/adr/0003-back-up-then-link.md).
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

# Reports the state of the copy and changes nothing.
# Reason is one of: Correct, Missing, Stale, NotOurs.
function Test-AuthorizedKeysCopy {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source
    )

    $reason =
        if (-not (Test-Path -LiteralPath $Path)) { 'Missing' }
        else {
            $actual = [IO.File]::ReadAllText($Path)
            if ($actual -eq (Get-AuthorizedKeysContent -Source $Source)) { 'Correct' }
            elseif ($actual.StartsWith($script:AuthorizedKeysHeaderPrefix)) { 'Stale' }
            else { 'NotOurs' }
        }

    return [pscustomobject]@{
        Path      = $Path
        Source    = $Source
        IsCorrect = ($reason -eq 'Correct')
        Reason    = $reason
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

    $state = Test-AuthorizedKeysCopy -Path $Path -Source $Source
    $backup = $null
    $action = switch ($state.Reason) {
        'Correct' { return [pscustomobject]@{ Path = $Path; Source = $Source; Action = 'AlreadyCorrect'; BackupPath = $null } }
        'Missing' { 'Created' }
        'Stale'   { 'Updated' }
        'NotOurs' { $backup = Move-DisplacedFile -Path $Path; 'BackedUpAndWritten' }
    }

    $parent = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    # Without a byte-order mark: sshd reads one as part of the first line. PowerShell 5.1's
    # Set-Content -Encoding UTF8 writes one, so this goes through .NET.
    [IO.File]::WriteAllText($Path, (Get-AuthorizedKeysContent -Source $Source), (New-Object Text.UTF8Encoding $false))

    return [pscustomobject]@{ Path = $Path; Source = $Source; Action = $action; BackupPath = $backup }
}
