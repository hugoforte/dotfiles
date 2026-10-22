# The overlay table in PowerShell: which overlays a machine lists, where each path an overlay may
# ship comes from, and the skill registries they merge. Overlays are private directories laid out
# like this repo's root; a machine lists them in ai/secrets/machine.local.psd1 (git-ignored), so no
# tracked file here ever names one. What each path is for is README's "Private configuration:
# overlays". The sh twin is ai/helpers/overlays.sh; the two agree on the rules, not the code
# (docs/adr/0007-a-parallel-macos-entry-point.md), and tests/overlays-parity.test.sh holds them to it.
#
#   Get-Overlays          read the list: the overlays, the machine key, the overlay repositories
#   Get-OverlaySource     the sources of a path in $OverlayTable
#   Get-OverlayEntry      the entries under a directory in $OverlayTable
#   Get-MergedSkillRegistry  every skill the registries list

# What an overlay may ship, one row per path: the path relative to a root, how many sources it may
# have, and the roots it is read from.
#   one      at most one source; two is an error naming both
#   all      every source, in order
#   entries  a pattern in one folder (*/ its folders, *.md its .md files) whose matches are linked by
#            name; the first to ship a name keeps it
#   overlays the listed overlays, in order; repo+overlays puts the repo first
# {KEY} in a path is the machine key, and with no key the path matches nothing. A path ending in /
# is a folder; every other is a file.
$OverlayTable = @(
    [pscustomobject]@{ Path = 'aws/config';                 Count = 'one';     Roots = 'repo+overlays' }
    [pscustomobject]@{ Path = 'ssh/authorized_keys';        Count = 'one';     Roots = 'overlays' }
    [pscustomobject]@{ Path = 'machines/{KEY}.psd1';        Count = 'one';     Roots = 'overlays' }
    [pscustomobject]@{ Path = 'machines/{KEY}.Brewfile';    Count = 'one';     Roots = 'overlays' }
    [pscustomobject]@{ Path = 'git/gitconfig';              Count = 'all';     Roots = 'overlays' }
    [pscustomobject]@{ Path = 'macos/Brewfile';             Count = 'all';     Roots = 'overlays' }
    [pscustomobject]@{ Path = 'macos/bootstrap.sh';         Count = 'all';     Roots = 'overlays' }
    [pscustomobject]@{ Path = 'ai/claude/config-dirs';      Count = 'all';     Roots = 'overlays' }
    [pscustomobject]@{ Path = 'machines/{KEY}.config-dirs'; Count = 'all';     Roots = 'overlays' }
    [pscustomobject]@{ Path = 'machines/';                  Count = 'all';     Roots = 'overlays' }
    [pscustomobject]@{ Path = 'powershell/tools.psd1';      Count = 'all';     Roots = 'repo+overlays' }
    [pscustomobject]@{ Path = 'ai/secrets/registry.psd1';   Count = 'all';     Roots = 'repo+overlays' }
    [pscustomobject]@{ Path = 'ai/skills/*/';               Count = 'entries'; Roots = 'overlays' }
    [pscustomobject]@{ Path = 'bruno/*/';                   Count = 'entries'; Roots = 'overlays' }
    [pscustomobject]@{ Path = 'ai/rules/*.md';              Count = 'entries'; Roots = 'overlays' }
    [pscustomobject]@{ Path = 'ai/agents/*.md';             Count = 'entries'; Roots = 'overlays' }
)

# Whether a machine.local.psd1 opts the machine into skill secrets: it must declare SearchRoots,
# which deploy-secrets.ps1 cannot run without. The file alone is not enough, because a machine
# also writes it just to list OptionalTools or Overlays. A declared but empty SearchRoots still
# opts in, so deploy-secrets.ps1 reports it rather than the sync skipping it in silence.
function Test-SkillSecretsOptIn {
    param([Parameter(Mandatory)][string]$LocalPath)

    if (-not (Test-Path -LiteralPath $LocalPath)) { return $false }
    return (Import-PowerShellDataFile $LocalPath).ContainsKey('SearchRoots')
}

# The overlays RepoPath's ai/secrets/machine.local.psd1 lists, or those passed as -Overlays instead,
# so a writer can check a list before writing it. No file, or no Overlays key, is no overlays.
# Returns:
#   Repo        RepoPath, the root read first by a repo+overlays path
#   Overlays    the overlays, in order
#   MachineKey  the computer's name as machines/ files are named: up to its first dot, uppercased;
#               empty for a computer with no name
#   RepoRoots   the git repositories the overlays are in, each once, in the order first listed, so
#               each is pulled once however many overlays it holds
# An overlay that does not exist is an error naming it: skipping it would drop everything it carries.
function Get-Overlays {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [string[]]$Overlays,
        [AllowEmptyString()][string]$ComputerName = $env:COMPUTERNAME
    )

    $localPath = Join-Path $RepoPath "ai\secrets\machine.local.psd1"
    $from = ""
    if (-not $PSBoundParameters.ContainsKey('Overlays')) {
        $Overlays = @()
        if (Test-Path -LiteralPath $localPath) {
            $listed = (Import-PowerShellDataFile $localPath).Overlays
            if ($listed) { $Overlays = @($listed) }
        }
        $from = " listed in $localPath"
    }
    foreach ($dir in $Overlays) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "overlay $dir$from does not exist" }
    }

    $roots = [ordered]@{}
    foreach ($overlay in $Overlays) {
        # try/catch, not just 2>$null: under $ErrorActionPreference = 'Stop', PowerShell 5.1
        # turns a native command's stderr into a terminating error.
        try { $top = git -C $overlay rev-parse --show-toplevel 2>$null } catch { $top = $null }
        if ($LASTEXITCODE -ne 0 -or -not $top) { continue }
        $top = [IO.Path]::GetFullPath($top)
        if (-not $roots.Contains($top)) { $roots[$top] = $true }
    }

    [pscustomobject]@{
        Repo       = $RepoPath
        Overlays   = @($Overlays)
        MachineKey = ($ComputerName -replace '\..*', '').ToUpperInvariant()
        RepoRoots  = @($roots.Keys)
    }
}

# The row of $OverlayTable for Path, with the roots it is read from in Set. A path not in the table,
# or with a count not among Counts, is an error.
function Get-OverlayRow {
    param(
        [Parameter(Mandatory)]$Set,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Counts
    )

    $rule = $OverlayTable | Where-Object { $_.Path -ceq $Path }
    if (-not $rule) { throw "$Path is not a path an overlay may ship (`$OverlayTable)" }
    if ($Counts -notcontains $rule.Count) { throw "$Path is a $($rule.Count) path, not $($Counts -join ' ')" }
    $roots = if ($rule.Roots -eq 'repo+overlays') { @($Set.Repo) + $Set.Overlays } else { $Set.Overlays }
    [pscustomobject]@{ Count = $rule.Count; Roots = @($roots) }
}

# The sources of a one or all path, given the set Get-Overlays returned. A one path has none or one,
# and two are an error naming both: a link has one target. An all path never fails.
function Get-OverlaySource {
    param(
        [Parameter(Mandatory)]$Set,
        [Parameter(Mandatory)][string]$Path
    )

    $rule = Get-OverlayRow -Set $Set -Path $Path -Counts 'one', 'all'
    $relative = $Path
    if ($relative.Contains('{KEY}')) {
        if (-not $Set.MachineKey) { return }
        $relative = $relative.Replace('{KEY}', $Set.MachineKey)
    }
    $kind = if ($relative.EndsWith('/')) { 'Container' } else { 'Leaf' }
    $found = @($rule.Roots |
        ForEach-Object { Join-Path $_ ($relative.TrimEnd('/') -replace '/', '\') } |
        Where-Object { Test-Path -LiteralPath $_ -PathType $kind })
    if ($rule.Count -eq 'one' -and $found.Count -gt 1) {
        throw "$relative is provided by more than one source: $($found -join ', ')"
    }
    $found
}

# One { Name; Path; ClashesWith } per match of an entries row (*/ its folders, *.md its .md files)
# in each overlay of Set, in overlay order. ClashesWith is what already ships that name, or $null
# when it is free. A ClaimedBy folder's own entry of the same name claims it before any overlay's.
# Names compare without case, as they do on NTFS. A clash is data, never a failure.
function Get-OverlayEntry {
    param(
        [Parameter(Mandatory)]$Set,
        [Parameter(Mandatory)][string]$Path,
        [string[]]$ClaimedBy = @()
    )

    $rule = Get-OverlayRow -Set $Set -Path $Path -Counts 'entries'
    $kind = if ($Path.EndsWith('/')) { 'Container' } else { 'Leaf' }
    $pattern = $Path.TrimEnd('/')
    $leaf = Split-Path $pattern -Leaf
    $seen = @{}
    foreach ($root in $rule.Roots) {
        $dir = Join-Path $root ((Split-Path $pattern -Parent) -replace '/', '\')
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        # -clike as well as -Filter: sh's glob is case-sensitive, and -Filter is not. A name starting
        # with a dot is left out, as sh's * leaves it out.
        $names = (Get-ChildItem -LiteralPath $dir -Filter $leaf -Force |
            Where-Object { $_.Name -clike $leaf -and -not $_.Name.StartsWith('.') -and (Test-Path -LiteralPath $_.FullName -PathType $kind) } |
            Sort-Object Name).Name
        foreach ($name in $names) {
            # Joined, not FullName, which expands a short (8.3) name the overlay was listed by.
            $entryPath = Join-Path $dir $name
            $clash = $ClaimedBy | ForEach-Object { Join-Path $_ $name } |
                Where-Object { Test-Path -LiteralPath $_ -PathType $kind } | Select-Object -First 1
            if (-not $clash) { $clash = $seen[$name.ToLowerInvariant()] }
            if (-not $clash) { $seen[$name.ToLowerInvariant()] = $entryPath }
            [pscustomobject]@{ Name = $name; Path = $entryPath; ClashesWith = $clash }
        }
    }
}

# Every skill in the registries at Path, in order, each with the SecretsDir beside its registry that
# its encrypted files live in. The same Id in two registries is an error naming both, because
# either answer would be a guess.
function Get-MergedSkillRegistry {
    param([AllowEmptyCollection()][string[]]$Path = @())

    $seen = @{}
    foreach ($registryPath in $Path) {
        foreach ($skill in (Import-PowerShellDataFile $registryPath).Skills) {
            if ($seen.ContainsKey($skill.Id)) {
                throw "skill '$($skill.Id)' is registered in both $($seen[$skill.Id]) and $registryPath"
            }
            $seen[$skill.Id] = $registryPath

            $entry = $skill.Clone()
            $entry.SecretsDir = Join-Path (Split-Path $registryPath -Parent) $skill.Id
            $entry
        }
    }
}

# The contents of ~/.gitconfig-overlays: one include per git/gitconfig fragment, in overlay order,
# so a later overlay overrides an earlier one.
function Get-GitOverlayIncludeContent {
    param([string[]]$Fragments = @())

    $lines = @("# Generated by powershell/setup.ps1 from the Overlays in ai/secrets/machine.local.psd1. Do not edit.")
    foreach ($fragment in $Fragments) {
        $lines += "[include]"
        $lines += "`tpath = $($fragment -replace '\\', '/')"
    }
    return ($lines -join "`n") + "`n"
}

# Creates a machine.local.psd1 from the example, searching $SearchRoot for checkouts in place of
# the example's folder, which is one machine's and not every machine's. An example whose
# SearchRoots entry this cannot recognise is an error rather than a guess.
function New-MachineLocalFile {
    param(
        [Parameter(Mandatory)][string]$ExamplePath,
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$SearchRoot
    )

    $text = [IO.File]::ReadAllText($ExamplePath)
    $pattern = "(?m)^([ \t]*SearchRoots\s*=\s*)@\(\s*'(?:[^']|'')*'\s*\)"
    if ([regex]::Matches($text, $pattern).Count -ne 1) {
        throw "$ExamplePath has no single-path SearchRoots entry to replace; create $LocalPath by hand"
    }
    $root = $SearchRoot -replace "'", "''"
    $text = [regex]::Replace($text, $pattern, { param($m) "$($m.Groups[1].Value)@('$root')" })
    [IO.File]::WriteAllText($LocalPath, $text)
}

# Writes the Overlays entry of a machine.local.psd1, replacing the one there or adding one before
# the closing brace. The rest of the file, comments included, is left as it was. An Overlays entry
# this cannot recognise is an error rather than a guess.
function Set-OverlayListInFile {
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [string[]]$Overlays = @()
    )

    $text = [IO.File]::ReadAllText($LocalPath)
    $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
    $items = @($Overlays | ForEach-Object { "        '$($_ -replace "'", "''")'" })
    $entry = if ($items.Count) { "Overlays = @($nl$($items -join $nl)$nl    )" } else { "Overlays = @()" }

    $found = [regex]::Matches($text, "(?m)^[ \t]*Overlays\s*=\s*@\((\s*'(?:[^']|'')*'\s*,?)*\s*\)")
    if ($found.Count -gt 1) { throw "$LocalPath has more than one Overlays entry; edit it by hand" }
    if ($found.Count -eq 1) {
        $m = $found[0]
        $indent = [regex]::Match($m.Value, '^[ \t]*').Value
        $text = $text.Substring(0, $m.Index) + $indent + $entry + $text.Substring($m.Index + $m.Length)
    } else {
        if ((Import-PowerShellDataFile $LocalPath).ContainsKey('Overlays')) {
            throw "$LocalPath has an Overlays entry this cannot rewrite; edit it by hand"
        }
        $close = $text.LastIndexOf('}')
        if ($close -lt 0) { throw "$LocalPath has no closing brace" }
        $text = $text.Substring(0, $close).TrimEnd() + "$nl$nl    $entry$nl}" + $text.Substring($close + 1)
    }
    [IO.File]::WriteAllText($LocalPath, $text)
}

# Brings ~/.gitconfig-overlays in line with the git/gitconfig fragments. Returns 'AlreadyCorrect',
# 'Written', or with -Check 'WouldWrite' and changes nothing.
function Update-GitOverlayInclude {
    param(
        [string[]]$Fragments = @(),
        [string]$Path = "$env:USERPROFILE\.gitconfig-overlays",
        [switch]$Check
    )

    $content = Get-GitOverlayIncludeContent -Fragments $Fragments
    if ((Test-Path -LiteralPath $Path) -and ([IO.File]::ReadAllText($Path) -eq $content)) { return 'AlreadyCorrect' }
    if ($Check) { return 'WouldWrite' }
    # WriteAllText writes UTF-8 without a BOM; Set-Content in PowerShell 5.1 cannot.
    [IO.File]::WriteAllText($Path, $content)
    return 'Written'
}
