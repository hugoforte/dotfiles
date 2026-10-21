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
# order of $Roots, the repo first and then the overlays as machine.local.psd1 lists them. The same
# section in two sources is an error naming both, since either answer would be a guess. With no
# source left, the file this wrote is removed, and so is a link to an aws/config that setup made
# before the file was generated.

. (Join-Path $PSScriptRoot "generated-file.ps1")

$script:AwsConfigHeaderPrefix = '# Written by dotfiles from '

# Each root's aws/config that exists, in the order of $Roots.
function Get-AwsConfigSource {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Roots)
    return @($Roots |
        ForEach-Object { Join-Path $_ "aws\config" } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

# The merged file: a header, then each source under a "# from <path>" line, with LF line endings.
# $null when no root has an aws/config.
function Get-AwsConfigContent {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Roots)

    $sources = Get-AwsConfigSource -Roots $Roots
    if (-not $sources.Count) { return $null }

    $seen = @{}
    $text = "$script:AwsConfigHeaderPrefix$($sources.Count) aws/config file(s); the next sync replaces any edit made here.`n" +
        "# Add a profile to one of them instead.`n"
    foreach ($source in $sources) {
        $body = [IO.File]::ReadAllText($source) -replace "`r`n", "`n"
        foreach ($line in ($body -split "`n")) {
            if ($line -notmatch '^\s*\[([^\]]+)\]\s*$') { continue }
            $section = ($Matches[1].Trim() -replace '\s+', ' ')
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
        return Test-GeneratedFile -Path $Path -Content $content -HeaderPrefix $script:AwsConfigHeaderPrefix
    }
    $reason = if (Test-AwsConfigLeftover -Path $Path) { 'Leftover' } else { 'NoSource' }
    return [pscustomobject]@{ Path = $Path; IsCorrect = ($reason -eq 'NoSource'); Reason = $reason }
}

# Brings ~/.aws/config in line with the sources, and says what it had to do.
# Action is one of: AlreadyCorrect, Created, Updated, BackedUpAndWritten, or with no source,
# Removed or Missing (nothing of ours there). BackupPath is set only when a file this did not
# write was displaced.
function Set-AwsConfig {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Roots
    )

    $content = Get-AwsConfigContent -Roots $Roots
    if ($null -ne $content) {
        return Set-GeneratedFile -Path $Path -Content $content -HeaderPrefix $script:AwsConfigHeaderPrefix
    }
    if (-not (Test-AwsConfigLeftover -Path $Path)) {
        return [pscustomobject]@{ Path = $Path; Action = 'Missing'; BackupPath = $null }
    }
    (Get-ManagedLinkItem $Path).Delete()
    return [pscustomobject]@{ Path = $Path; Action = 'Removed'; BackupPath = $null }
}

# Whether $Path is what this, or setup before it, put there: a file this wrote, or a link to an
# aws/config. Anything else is someone's own.
function Test-AwsConfigLeftover {
    param([Parameter(Mandatory)][string]$Path)

    $item = Get-ManagedLinkItem $Path
    if (-not $item) { return $false }
    if ($item.LinkType) { return [string](Get-LinkTarget $item) -match '[\\/]aws[\\/]config$' }
    return Test-GeneratedFileIsOurs -Path $Path -HeaderPrefix $script:AwsConfigHeaderPrefix
}
