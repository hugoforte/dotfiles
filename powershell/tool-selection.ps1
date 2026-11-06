# Which manifest entries a machine gets, and the pure parts of the github-release, download and uv
# install methods.
# Dot-sourced by install-tools.ps1.
#
# An entry with Optional = '<name>' belongs to that option. A machine opts into it by listing the
# name under OptionalTools in ai/secrets/machine.local.psd1 (git-ignored) or in an overlay's
# machines/<KEY>.psd1 (tracked), and then gets every entry of the option - its install
# and its manual steps together.

# The options the given files opt into, each named once, in the order first listed. A file that
# does not exist, or has no OptionalTools key, adds none.
function Get-OptedInOptionList {
    param([Parameter(Mandatory)][string[]]$Path)

    $options = [ordered]@{}
    foreach ($file in $Path) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        foreach ($name in @((Import-PowerShellDataFile -LiteralPath $file).OptionalTools)) {
            if ($name -and -not $options.Contains($name)) { $options[$name] = $true }
        }
    }
    return @($options.Keys)
}

# Every entry of the given tools.psd1 files, in order: dotfiles' own, then each overlay's. A file
# that does not exist contributes nothing. The same Id twice is an error naming where each was
# declared, because installing either would be a guess. An entry's Configure is written relative
# to the root of the repo that declares it (the folder holding its powershell/), and comes back
# as a full path; a script that is not there is an error naming the manifest.
function Get-MergedToolManifest {
    param([Parameter(Mandatory)][string[]]$Path)

    $seen = @{}
    foreach ($file in $Path) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        foreach ($tool in @((Import-PowerShellDataFile -LiteralPath $file).Tools | Where-Object { $_ })) {
            if (-not $tool.Id) { throw "an entry in $file has no Id" }
            if ($seen.ContainsKey($tool.Id)) {
                throw "tool '$($tool.Id)' is declared in both $($seen[$tool.Id]) and $file"
            }
            $seen[$tool.Id] = $file
            if ($tool.Configure) {
                if ($tool.Source -eq 'manual') {
                    throw "tool '$($tool.Id)': a manual entry is never installed, so its Configure would never run, declared in $file"
                }
                $root = Split-Path (Split-Path $file -Parent) -Parent
                $tool.Configure = Join-Path $root $tool.Configure
                if (-not (Test-Path -LiteralPath $tool.Configure)) {
                    throw "tool '$($tool.Id)': Configure script $($tool.Configure) not found, declared in $file"
                }
            }
            $tool
        }
    }
}

# What -IfChanged compares: every manifest read, and the options. Opting in changes what a machine
# needs without touching any manifest, so the options count too; their order does not.
function Get-ToolStateHash {
    param(
        [Parameter(Mandatory)][string[]]$ManifestPath,
        [AllowEmptyCollection()][string[]]$OptedIn = @()
    )

    $hashes = @($ManifestPath | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })
    return ($hashes -join "+") + ":" + ((@($OptedIn) | Sort-Object) -join ",")
}

# Splits the manifest for one machine:
#   Selected   every entry that is not optional, and every entry of an opted-in option
#   Available  options the manifest declares that the machine did not opt into
#   Unknown    opted-in names no entry declares - a typo would otherwise install nothing, silently
function Select-MachineTools {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][hashtable[]]$Tools,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$OptedIn
    )

    $declared = @($Tools | Where-Object { $_.Optional } | ForEach-Object { $_.Optional } | Select-Object -Unique)
    [pscustomobject]@{
        Selected  = @($Tools | Where-Object { -not $_.Optional -or $OptedIn -contains $_.Optional })
        Available = @($declared | Where-Object { $OptedIn -notcontains $_ })
        Unknown   = @($OptedIn | Where-Object { $declared -notcontains $_ })
    }
}

# The one release asset whose name matches Pattern (a -like wildcard). None, or several, is an
# error: installing a guess is worse than installing nothing.
function Select-ReleaseAsset {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Assets,
        [Parameter(Mandatory)][string]$Pattern
    )

    $found = @($Assets | Where-Object { $_.name -like $Pattern })
    if ($found.Count -eq 0) { throw "no release asset matches '$Pattern'" }
    if ($found.Count -gt 1) {
        throw "more than one release asset matches '$Pattern': $(($found | ForEach-Object { $_.name }) -join ', ')"
    }
    return $found[0]
}

# What is wrong with a github-release or download entry, or nothing when it has every field its
# install method needs. A missing field would otherwise stop the whole run partway through the
# manifest.
function Test-InstallerEntry {
    param([Parameter(Mandatory)][hashtable]$Tool)

    $needs = if ($Tool.Source -eq 'download') { 'Url', 'Sha256', 'InstallArgs', 'Present' } else { 'Asset', 'InstallArgs', 'Present' }
    $missing = @($needs | Where-Object { -not $Tool[$_] })
    if ($missing.Count -gt 0) { return "$($Tool.Id): a $($Tool.Source) entry needs $($missing -join ', ')" }

    # The installer is saved under the last segment of the Url's path, and run by its extension.
    if ($Tool.Source -eq 'download') {
        $uri = $null
        if (-not [Uri]::TryCreate($Tool.Url, 'Absolute', [ref]$uri) -or $uri.Scheme -ne 'https') {
            return "$($Tool.Id): a download Url must be an absolute https address, not '$($Tool.Url)'"
        }
        if (-not [IO.Path]::GetExtension($uri.AbsolutePath)) {
            return "$($Tool.Id): a download Url's path must end in the installer's file name, not '$($Tool.Url)'"
        }
    }
}

# The tools `uv tool list` reports installed. It prints each tool as "<name> v<version>", followed
# by a "- <executable>" line per command the tool put on PATH, or "No tools installed".
function Get-UvToolNames {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$ListOutput)

    return @($ListOutput -split "`r?`n" | Where-Object { $_ -match '^\S+ v\d' } | ForEach-Object { ($_ -split ' ')[0] })
}

# Whether a program whose display name matches DisplayName (a -like wildcard) is in Listed - the
# display names Windows lists under Installed apps.
function Test-ProgramListed {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Listed
    )

    return [bool]($Listed | Where-Object { $_ -like $DisplayName } | Select-Object -First 1)
}
