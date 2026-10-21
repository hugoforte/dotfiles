# The generated file: a managed path that holds content dotfiles writes, rather than a link to a
# file in a checkout. For what a link cannot be: ~/.ssh/authorized_keys on Windows, which sshd
# checks the ownership and access of (authorized-keys.ps1), and ~/.aws/config, which merges several
# sources (aws-config.ps1, docs/adr/0010-aws-config-is-generated.md).
#
#   . (Join-Path $PSScriptRoot "generated-file.ps1")
#   Set-GeneratedFile    -Path $path -Content $content -HeaderPrefix '# Written by dotfiles from ' [-Checksum]
#   Test-GeneratedFile   -Path $path -Content $content -HeaderPrefix '# Written by dotfiles from ' [-Checksum]
#   Remove-GeneratedFile -Path $path -HeaderPrefix '# Written by dotfiles from ' [-Checksum] [-Check]
#
# $Content opens with a header line that starts with $HeaderPrefix. The header is how a later run
# tells its own file, replaced freely, from one someone else wrote, which is backed up first
# (docs/adr/0003-back-up-then-link.md). With -Checksum, a second line records a SHA-256 of what
# follows it, and the file is its own only while that still matches: for a file another program
# edits by appending, as the AWS CLI does, the header alone would call an edited file its own and
# replace the edit without a backup. A link at the path holds no content of its own, so it is
# replaced without a backup. The file is written as UTF-8 without a byte-order mark.

. (Join-Path $PSScriptRoot "managed-link.ps1")

$script:GeneratedFileChecksumPrefix = '# dotfiles-sha256: '

function Get-GeneratedFileSha256 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') })
    } finally {
        $sha.Dispose()
    }
}

# What is written for $Content: as given, or with -Checksum, with the checksum line after the header.
function Get-GeneratedFileText {
    param(
        [Parameter(Mandatory)][string]$Content,
        [switch]$Checksum
    )
    if (-not $Checksum) { return $Content }
    $newline = $Content.IndexOf("`n")
    if ($newline -lt 0) { throw "generated content has no header line: $Content" }
    $header = $Content.Substring(0, $newline + 1)
    $body = $Content.Substring($newline + 1)
    return "$header$script:GeneratedFileChecksumPrefix$(Get-GeneratedFileSha256 $body)`n$body"
}

# Whether $Path is a regular file this wrote and nobody has edited since: it opens with
# $HeaderPrefix and, with -Checksum, its checksum line matches what follows it. A link is never one.
function Test-GeneratedFileIsOurs {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$HeaderPrefix,
        [switch]$Checksum
    )
    $item = Get-ManagedLinkItem $Path
    if (-not $item -or $item.LinkType) { return $false }
    $text = [IO.File]::ReadAllText($Path)
    if (-not $text.StartsWith($HeaderPrefix, [StringComparison]::Ordinal)) { return $false }
    if (-not $Checksum) { return $true }

    # -split, not .Split([char], 3): PowerShell 5.1 binds that to Split(params char[]) and splits on
    # [char]3 as well.
    $lines = $text -split "`n", 3
    if ($lines.Count -lt 3 -or -not $lines[1].StartsWith($script:GeneratedFileChecksumPrefix, [StringComparison]::Ordinal)) { return $false }
    return $lines[1].Substring($script:GeneratedFileChecksumPrefix.Length) -ceq (Get-GeneratedFileSha256 $lines[2])
}

# Reports the state of the file and changes nothing.
# Reason is one of: Correct, Missing, Stale, NotOurs.
function Test-GeneratedFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$HeaderPrefix,
        [switch]$Checksum
    )

    $text = Get-GeneratedFileText -Content $Content -Checksum:$Checksum
    # Get-Item, not Test-Path, which reads a dangling link as nothing there.
    $reason =
        if (-not (Get-ManagedLinkItem $Path)) { 'Missing' }
        elseif (-not (Test-GeneratedFileIsOurs -Path $Path -HeaderPrefix $HeaderPrefix -Checksum:$Checksum)) { 'NotOurs' }
        elseif ([string]::Equals([IO.File]::ReadAllText($Path), $text, [StringComparison]::Ordinal)) { 'Correct' }
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
        [Parameter(Mandatory)][string]$HeaderPrefix,
        [switch]$Checksum
    )

    $state = Test-GeneratedFile -Path $Path -Content $Content -HeaderPrefix $HeaderPrefix -Checksum:$Checksum
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
    # PowerShell 5.1's Set-Content -Encoding UTF8 writes a byte-order mark. A swap that fails, such
    # as on a file another process holds open, leaves no staged file behind.
    $staged = "$Path.dotfiles-new"
    try {
        [IO.File]::WriteAllText($staged, (Get-GeneratedFileText -Content $Content -Checksum:$Checksum), (New-Object Text.UTF8Encoding $false))
        if (Test-Path -LiteralPath $Path) {
            # No backup file: PowerShell would pass $null to a string parameter as "".
            [IO.File]::Replace($staged, $Path, [NullString]::Value)
        } else {
            [IO.File]::Move($staged, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Force }
    }

    return [pscustomobject]@{ Path = $Path; Action = $action; BackupPath = $backup }
}

# Removes $Path when it is a file this wrote: for a machine whose sources no longer ship it. A
# file anyone else wrote, or edited, is left alone. -Check says what it would do.
# Action is one of: Removed, NotOurs, Missing.
function Remove-GeneratedFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$HeaderPrefix,
        [switch]$Checksum,
        [switch]$Check
    )

    if (-not (Get-ManagedLinkItem $Path)) { return [pscustomobject]@{ Path = $Path; Action = 'Missing' } }
    if (-not (Test-GeneratedFileIsOurs -Path $Path -HeaderPrefix $HeaderPrefix -Checksum:$Checksum)) { return [pscustomobject]@{ Path = $Path; Action = 'NotOurs' } }
    if (-not $Check) { Remove-Item -LiteralPath $Path }
    return [pscustomobject]@{ Path = $Path; Action = 'Removed' }
}
