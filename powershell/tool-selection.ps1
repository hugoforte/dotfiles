# Which manifest entries a machine gets, and the pure parts of the github-release install method.
# Dot-sourced by install-tools.ps1.
#
# An entry with Optional = '<name>' belongs to that option. A machine opts into it by listing the
# name under OptionalTools in ai/secrets/machine.local.psd1 (git-ignored), and then gets every
# entry of the option - its install and its manual steps together.

# The options a machine.local.psd1 opts into. No file, or no OptionalTools key, is none.
function Get-OptedInOptionList {
    param([Parameter(Mandatory)][string]$LocalPath)

    if (-not (Test-Path -LiteralPath $LocalPath)) { return @() }
    $local = Import-PowerShellDataFile $LocalPath
    if (-not $local.OptionalTools) { return @() }
    return @($local.OptionalTools)
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
        [Parameter(Mandatory)][object[]]$Assets,
        [Parameter(Mandatory)][string]$Pattern
    )

    $found = @($Assets | Where-Object { $_.name -like $Pattern })
    if ($found.Count -eq 0) { throw "no release asset matches '$Pattern'" }
    if ($found.Count -gt 1) {
        throw "more than one release asset matches '$Pattern': $(($found | ForEach-Object { $_.name }) -join ', ')"
    }
    return $found[0]
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
