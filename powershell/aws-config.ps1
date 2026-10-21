# ~/.aws/config: every aws/config among this repo and the machine's overlays, merged into one file.
#
#   . (Join-Path $PSScriptRoot "aws-config.ps1")
#   Get-AwsConfigContent -Roots $roots                       the merged file, or $null with no source
#   Set-AwsConfig        -Path "$env:USERPROFILE\.aws\config" -Roots $roots
#   Test-AwsConfig       -Path "$env:USERPROFILE\.aws\config" -Roots $roots
#
# A generated file (generated-file.ps1), where most managed files are links: the AWS CLI reads one
# config file and has no include, so several sources cannot be one link
# (docs/adr/0010-aws-config-is-generated.md). Each source goes in under a line naming it, in the
# order of $Roots, the repo first and then the overlays as machine.local.psd1 lists them; a root
# listed twice goes in once. The same section in two sources, as the AWS CLI names sections, is an
# error naming both, since either answer would be a guess. The file carries a checksum, because the
# AWS CLI edits it by appending (aws configure sso), and an edit is backed up before it is replaced.
# With no source left, the file this wrote is removed, and so is a link left dangling.

. (Join-Path $PSScriptRoot "generated-file.ps1")

$script:AwsConfigHeaderPrefix = '# Written by dotfiles from '

# Each root's aws/config that exists, in the order of $Roots, each path once.
function Get-AwsConfigSource {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Roots)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    return @($Roots |
        ForEach-Object { [IO.Path]::GetFullPath((Join-Path $_ "aws\config")) } |
        Where-Object { (Test-Path -LiteralPath $_ -PathType Leaf) -and $seen.Add($_) })
}

# The section a header line names, as the AWS CLI reads it, or $null for a line that is no header.
# The CLI's parser takes the header up to the last ] on the line and ignores what follows, and reads
# [default] and [profile default] as one profile; a name may be quoted.
function Get-AwsConfigSectionKey {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Line)
    if ($Line -notmatch '^\s*\[(.+)\]') { return $null }
    $words = @($Matches[1].Trim() -split '\s+')
    if ($words.Count -eq 1 -and $words[0] -ceq 'default') { return 'profile default' }
    if ($words.Count -eq 2) { return "$($words[0]) $($words[1].Trim('"', "'"))" }
    return $words -join ' '
}

# The merged file: a header, then each source under a "# from <path>" line, with LF line endings.
# $null when no root has an aws/config.
function Get-AwsConfigContent {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Roots)

    $sources = Get-AwsConfigSource -Roots $Roots
    if (-not $sources.Count) { return $null }

    # Ordinal: profile names are case-sensitive to the AWS CLI.
    $seen = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    $text = "$script:AwsConfigHeaderPrefix$($sources.Count) aws/config file(s); the next sync replaces any edit made here.`n" +
        "# Add a profile to one of them instead.`n"
    foreach ($source in $sources) {
        $body = [IO.File]::ReadAllText($source) -replace "`r`n", "`n"
        foreach ($line in ($body -split "`n")) {
            $section = Get-AwsConfigSectionKey $line
            if ($null -eq $section) { continue }
            if ($seen.ContainsKey($section) -and $seen[$section] -ne $source) {
                throw "aws/config section [$section] is in both $($seen[$section]) and $source"
            }
            $seen[$section] = $source
        }
        if ($body -and -not $body.EndsWith("`n")) { $body += "`n" }
        $text += "`n# from $source`n$body"
    }
    return $text
}

# Reports the state of ~/.aws/config and changes nothing.
# Reason is one of: Correct, Missing, Stale, NotOurs, or with no source, NoSource (nothing to remove)
# and Leftover (a file or link this would remove).
function Test-AwsConfig {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Roots
    )

    $content = Get-AwsConfigContent -Roots $Roots
    if ($null -ne $content) {
        return Test-GeneratedFile -Path $Path -Content $content -HeaderPrefix $script:AwsConfigHeaderPrefix -Checksum
    }
    $reason = if (Test-AwsConfigLeftover -Path $Path) { 'Leftover' } else { 'NoSource' }
    return [pscustomobject]@{ Path = $Path; IsCorrect = ($reason -eq 'NoSource'); Reason = $reason }
}

# Brings ~/.aws/config in line with the sources, and says what it had to do.
# Action is one of: AlreadyCorrect, Created, Updated, BackedUpAndWritten, or with no source,
# Removed or Missing (nothing of ours there). BackupPath is set only when a file this did not
# write, or someone edited, was displaced.
function Set-AwsConfig {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Roots
    )

    $content = Get-AwsConfigContent -Roots $Roots
    if ($null -ne $content) {
        return Set-GeneratedFile -Path $Path -Content $content -HeaderPrefix $script:AwsConfigHeaderPrefix -Checksum
    }
    if (-not (Test-AwsConfigLeftover -Path $Path)) {
        return [pscustomobject]@{ Path = $Path; Action = 'Missing'; BackupPath = $null }
    }
    (Get-ManagedLinkItem $Path).Delete()
    return [pscustomobject]@{ Path = $Path; Action = 'Removed'; BackupPath = $null }
}

# Whether $Path is what this, or setup before it, left behind: a file this wrote that nobody has
# edited, or a link that no longer resolves, as one into an overlay whose aws/config went does.
# A live link is someone's own, and stays.
function Test-AwsConfigLeftover {
    param([Parameter(Mandatory)][string]$Path)

    $item = Get-ManagedLinkItem $Path
    if (-not $item) { return $false }
    if ($item.LinkType) {
        # The target, not the link: Test-Path on a dangling link says it is there.
        $target = [string](Get-LinkTarget $item)
        if (-not [IO.Path]::IsPathRooted($target)) { $target = Join-Path (Split-Path $Path -Parent) $target }
        return -not (Test-Path -LiteralPath $target)
    }
    return Test-GeneratedFileIsOurs -Path $Path -HeaderPrefix $script:AwsConfigHeaderPrefix -Checksum
}
