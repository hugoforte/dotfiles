# The generated file: a managed path that holds content dotfiles writes, rather than a link to a
# file in a checkout. For what a link cannot be: ~/.ssh/authorized_keys on Windows, which sshd
# checks the ownership and access of (authorized-keys.ps1), and ~/.aws/config, which merges several
# sources (aws-config.ps1, docs/adr/0010-aws-config-is-generated.md).
#
#   . (Join-Path $PSScriptRoot "generated-file.ps1")
#   Set-GeneratedFile    -Path $path -Content $content -HeaderPrefix '# Written by dotfiles from '
#   Test-GeneratedFile   -Path $path -Content $content -HeaderPrefix '# Written by dotfiles from '
#   Remove-GeneratedFile -Path $path -HeaderPrefix '# Written by dotfiles from ' [-Check]
#
# $Content opens with a header that starts with $HeaderPrefix. The header is how a later run tells
# its own file, replaced freely, from one someone else wrote, which is backed up first
# (docs/adr/0003-back-up-then-link.md). A link at the path holds no content of its own, so it is
# replaced without a backup. The file is written as UTF-8 without a byte-order mark.

. (Join-Path $PSScriptRoot "managed-link.ps1")

# Whether $Path is a regular file opening with $HeaderPrefix. A link is never one: this writes files.
function Test-GeneratedFileIsOurs {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$HeaderPrefix
    )
    $item = Get-ManagedLinkItem $Path
    if (-not $item -or $item.LinkType) { return $false }
    return [IO.File]::ReadAllText($Path).StartsWith($HeaderPrefix, [StringComparison]::Ordinal)
}

# Reports the state of the file and changes nothing.
# Reason is one of: Correct, Missing, Stale, NotOurs.
function Test-GeneratedFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$HeaderPrefix
    )

    # Get-Item, not Test-Path, which reads a dangling link as nothing there.
    $reason =
        if (-not (Get-ManagedLinkItem $Path)) { 'Missing' }
        elseif (-not (Test-GeneratedFileIsOurs -Path $Path -HeaderPrefix $HeaderPrefix)) { 'NotOurs' }
        elseif ([string]::Equals([IO.File]::ReadAllText($Path), $Content, [StringComparison]::Ordinal)) { 'Correct' }
        else { 'Stale' }

    return [pscustomobject]@{
        Path      = $Path
        IsCorrect = ($reason -eq 'Correct')
        Reason    = $reason
    }
}

# Makes $Path hold $Content, and says what it had to do to get there.
# Action is one of: AlreadyCorrect, Created, Updated, BackedUpAndWritten.
# BackupPath is set only when a file this did not write was displaced.
function Set-GeneratedFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$HeaderPrefix
    )

    $state = Test-GeneratedFile -Path $Path -Content $Content -HeaderPrefix $HeaderPrefix
    if ($state.IsCorrect) {
        return [pscustomobject]@{ Path = $Path; Action = 'AlreadyCorrect'; BackupPath = $null }
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
    # Written beside it and swapped in, so a reader never sees a half-written file. Through .NET:
    # PowerShell 5.1's Set-Content -Encoding UTF8 writes a byte-order mark.
    $staged = "$Path.dotfiles-new"
    [IO.File]::WriteAllText($staged, $Content, (New-Object Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $Path) {
        # No backup file: PowerShell would pass $null to a string parameter as "".
        [IO.File]::Replace($staged, $Path, [NullString]::Value)
    } else {
        [IO.File]::Move($staged, $Path)
    }

    return [pscustomobject]@{ Path = $Path; Action = $action; BackupPath = $backup }
}

# Removes $Path when it is a file this wrote: for a machine whose sources no longer ship it. A
# file anyone else wrote is left alone. -Check says what it would do.
# Action is one of: Removed, NotOurs, Missing.
function Remove-GeneratedFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$HeaderPrefix,
        [switch]$Check
    )

    if (-not (Get-ManagedLinkItem $Path)) { return [pscustomobject]@{ Path = $Path; Action = 'Missing' } }
    if (-not (Test-GeneratedFileIsOurs -Path $Path -HeaderPrefix $HeaderPrefix)) { return [pscustomobject]@{ Path = $Path; Action = 'NotOurs' } }
    if (-not $Check) { Remove-Item -LiteralPath $Path }
    return [pscustomobject]@{ Path = $Path; Action = 'Removed' }
}
