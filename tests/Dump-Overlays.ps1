# Dump-Overlays.ps1 -RepoPath <repo>: everything powershell/overlays.ps1 reads for the repo, one
# fact per line, tab-separated, walking $OverlayTable in order. tests/overlays-dump.sh prints the
# same for ai/helpers/overlays.sh, and tests/overlays-parity.test.sh diffs the two. Test-only; the
# format is described there.

param([Parameter(Mandatory)][string]$RepoPath)

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell\overlays.ps1')

$set = Get-Overlays -RepoPath $RepoPath
"key`t$($set.MachineKey)"
foreach ($overlay in $set.Overlays) { "overlay`t$overlay" }
foreach ($root in $set.RepoRoots) { "repo`t$root" }

foreach ($rule in $OverlayTable) {
    if ($rule.Count -eq 'entries') {
        $claimant = Join-Path $RepoPath ((Split-Path $rule.Path.TrimEnd('/') -Parent) -replace '/', '\')
        foreach ($entry in (Get-OverlayEntry -Set $set -Path $rule.Path -ClaimedBy $claimant)) {
            "$($rule.Path)`t$($entry.Path)`t$($entry.ClashesWith)"
        }
        continue
    }
    try { $sources = @(Get-OverlaySource -Set $set -Path $rule.Path) } catch { "$($rule.Path)`t!error"; continue }
    foreach ($source in $sources) { "$($rule.Path)`t$source" }
}

try {
    $skills = @(Get-MergedSkillRegistry -Path (Get-OverlaySource -Set $set -Path 'ai/secrets/registry.psd1'))
    foreach ($skill in $skills) {
        "skill`t$($skill.Id)`t$($skill.Marker)`t$($skill.Remote)`t$($skill.Files -join ' ')`t$($skill.SecretsDir)"
    }
} catch {
    "skill`t!error"
}
