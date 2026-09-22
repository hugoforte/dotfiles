# `git branch --merged` answers one question: is the branch tip an ancestor of the target. That
# holds for a merge commit and for a fast-forward, and it is false for every squash merge, which
# replaces the branch with a single new commit that shares no sha with it. GitHub squashes by
# default, so on a repo that merges that way `--merged` reports nothing and the merged branches
# pile up. These functions ask the content question underneath instead.

# A bare name is ambiguous: git resolves refs/tags ahead of refs/heads, so a tag sharing a
# branch's name answers in its place. Every comparison here can end in a branch being deleted,
# so nothing is left to that guess.
function Resolve-BranchRef {
    param([Parameter(Mandatory)][string]$Ref)

    foreach ($candidate in @("refs/heads/$Ref", "refs/remotes/$Ref")) {
        git show-ref --verify --quiet $candidate 2>$null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }

    return $Ref
}

# Windows PowerShell 5.1 does not pipe bytes between two native commands: it decodes the first
# one's stdout into strings and re-encodes them onto the second one's stdin. `git patch-id` reads
# a patch byte for byte under --verbatim, so what reaches it is no longer the patch git produced -
# in practice one side of the comparison comes back empty. cmd pipes bytes, which is the same
# reason managed-link.ps1 shells out for mklink (docs/adr/0002).
function Invoke-GitPatchId {
    param([Parameter(Mandatory)][string]$Pipeline)

    return cmd /c ($Pipeline + " | git patch-id --verbatim") 2>$null
}

# The patch a squash merge of this branch would have carried: everything it adds since it left
# the target, as one diff.
function Get-RangePatchId {
    param(
        [Parameter(Mandatory)][string]$FromRef,
        [Parameter(Mandatory)][string]$ToRef
    )

    # --verbatim, because patch-id normalises whitespace by default, and that calls a branch
    # that only ever reindented something identical to the commit it was never merged as.
    $line = Invoke-GitPatchId -Pipeline ('git diff -p "{0}" "{1}"' -f $FromRef, $ToRef)
    if (-not $line) { return $null }

    return ([string]@($line)[0]).Trim().Split(" ")[0]
}

function Test-SquashMergedBranch {
    param(
        [Parameter(Mandatory)][string]$BranchRef,
        [Parameter(Mandatory)][string]$TargetRef
    )

    $mergeBase = git merge-base $TargetRef $BranchRef 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $mergeBase) { return $false }
    $mergeBase = ([string]@($mergeBase)[0]).Trim()

    $branchPatch = Get-RangePatchId -FromRef $mergeBase -ToRef $BranchRef
    if (-not $branchPatch) { return $false }

    # One patch-id per commit the target gained since the branch left it. The squash commit is
    # among them, under a sha that exists nowhere on the branch, which is the whole problem.
    $targetPatches = Invoke-GitPatchId -Pipeline ('git log -p --no-merges "{0}..{1}"' -f $mergeBase, $TargetRef)
    if (-not $targetPatches) { return $false }

    foreach ($line in @($targetPatches)) {
        if (([string]$line).Trim().Split(" ")[0] -eq $branchPatch) { return $true }
    }

    return $false
}

# "ancestor", "squash" or "no". The caller needs the difference: git refuses `branch -d` on a
# branch it cannot see as an ancestor, so a squash verdict has to be deleted with -D.
function Get-BranchMergeVerdict {
    param(
        [Parameter(Mandatory)][string]$BranchRef,
        [Parameter(Mandatory)][string]$TargetRef
    )

    $branch = Resolve-BranchRef -Ref $BranchRef
    $target = Resolve-BranchRef -Ref $TargetRef

    git merge-base --is-ancestor $branch $target 2>$null
    if ($LASTEXITCODE -eq 0) { return "ancestor" }

    if (Test-SquashMergedBranch -BranchRef $branch -TargetRef $target) { return "squash" }

    return "no"
}

function Test-BranchMerged {
    param(
        [Parameter(Mandatory)][string]$BranchRef,
        [Parameter(Mandatory)][string]$TargetRef
    )

    return ((Get-BranchMergeVerdict -BranchRef $BranchRef -TargetRef $TargetRef) -ne "no")
}

function git-list-merged-branches {
    param(
        [string]$Branch = "develop",
        [ValidateSet("local", "remote", "auto")]
        [string]$Scope = "local",
        [string]$Remote = "origin",
        [string]$TargetRef,
        [switch]$IncludeCurrent,
        [switch]$IncludeProtected,
        [switch]$AsObject,
        [Alias("h", "?")]
        [switch]$Help
    )

    if ($Help) {
        Write-Host "Usage:" -ForegroundColor Cyan
        Write-Host "  git-list-merged-branches [-Branch <name>] [-Scope <local|remote|auto>] [-Remote <name>] [-TargetRef <ref>] [-IncludeCurrent] [-IncludeProtected] [-AsObject] [-help]" -ForegroundColor White
        Write-Host ""
        Write-Host "Defaults:" -ForegroundColor Cyan
        Write-Host "  Branch: develop" -ForegroundColor White
        Write-Host "  Scope:  local" -ForegroundColor White
        Write-Host "  Remote: origin" -ForegroundColor White
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Cyan
        Write-Host "  git-list-merged-branches" -ForegroundColor White
        Write-Host "  git-list-merged-branches -Branch main -Scope local" -ForegroundColor White
        Write-Host "  git-list-merged-branches -Branch main -Scope remote -Remote origin" -ForegroundColor White
        Write-Host "  git-list-merged-branches -Scope auto -Branch develop" -ForegroundColor White
        Write-Host "  git-list-merged-branches -TargetRef refs/remotes/origin/main" -ForegroundColor White
        return
    }

    $gitDir = git rev-parse --git-dir 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Not a git repository." -ForegroundColor Red
        return
    }

    if (-not $Branch -or -not $Branch.Trim()) {
        Write-Host "Branch name cannot be empty." -ForegroundColor Red
        return
    }

    if (-not $Remote -or -not $Remote.Trim()) {
        $Remote = "origin"
    }

    $resolvedRef = ""
    $resolvedDisplay = ""
    $listRemoteBranches = $false

    if ($TargetRef) {
        $resolvedRef = $TargetRef.Trim()
        $resolvedDisplay = $resolvedRef
        if ($resolvedRef -like "refs/remotes/*") {
            $listRemoteBranches = $true
        }
    } elseif ($Scope -eq "local") {
        $resolvedRef = "refs/heads/$Branch"
        $resolvedDisplay = "$Branch (local)"
    } elseif ($Scope -eq "remote") {
        $resolvedRef = "refs/remotes/$Remote/$Branch"
        $resolvedDisplay = "$Remote/$Branch"
        $listRemoteBranches = $true
    } else {
        $localRef = "refs/heads/$Branch"
        $remoteRef = "refs/remotes/$Remote/$Branch"

        git show-ref --verify --quiet $localRef
        if ($LASTEXITCODE -eq 0) {
            $resolvedRef = $localRef
            $resolvedDisplay = "$Branch (local)"
        } else {
            git show-ref --verify --quiet $remoteRef
            if ($LASTEXITCODE -eq 0) {
                $resolvedRef = $remoteRef
                $resolvedDisplay = "$Remote/$Branch"
                $listRemoteBranches = $true
            }
        }
    }

    if (-not $resolvedRef) {
        Write-Host "Target branch not found in auto mode: local '$Branch' or '$Remote/$Branch'." -ForegroundColor Yellow
        return
    }

    git show-ref --verify --quiet $resolvedRef
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Target branch not found: $resolvedDisplay" -ForegroundColor Yellow
        return
    }

    $currentBranch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
    if ($listRemoteBranches) {
        $mergedBranches = git for-each-ref --format="%(refname:short)" "refs/remotes/$Remote" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -notlike "*/HEAD" -and $_ -ne $Remote } |
            ForEach-Object {
                $name = if ($_.StartsWith("$Remote/")) {
                    $_.Substring($Remote.Length + 1)
                } else {
                    $_
                }
                [PSCustomObject]@{ Ref = $_; Name = $name }
            } |
            Where-Object { $_.Name -and $_.Name -ne $Branch } |
            Where-Object { $IncludeProtected -or ($_.Name -ne "main" -and $_.Name -ne "develop") } |
            ForEach-Object {
                $verdict = Get-BranchMergeVerdict -BranchRef $_.Ref -TargetRef $resolvedRef
                if ($verdict -ne "no") { [PSCustomObject]@{ Name = $_.Name; Verdict = $verdict } }
            } |
            Sort-Object -Property Name -Unique
    } else {
        $mergedBranches = git branch --format "%(refname:short)" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -ne $Branch } |
            Where-Object { $IncludeCurrent -or $_ -ne $currentBranch } |
            Where-Object { $IncludeProtected -or ($_ -ne "main" -and $_ -ne "develop") } |
            ForEach-Object {
                $verdict = Get-BranchMergeVerdict -BranchRef $_ -TargetRef $resolvedRef
                if ($verdict -ne "no") { [PSCustomObject]@{ Name = $_; Verdict = $verdict } }
            } |
            Sort-Object -Property Name -Unique
    }

    if ($mergedBranches -isnot [System.Array]) {
        $mergedBranches = @($mergedBranches)
    }

    if (-not $mergedBranches -or $mergedBranches.Count -eq 0) {
        if ($listRemoteBranches) {
            Write-Host "No remote branches are merged into $resolvedDisplay." -ForegroundColor Yellow
        } else {
            Write-Host "No local branches are merged into $resolvedDisplay." -ForegroundColor Yellow
        }
        return
    }

    if ($AsObject) {
        $mergedBranches |
            ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.Name
                    Verdict = $_.Verdict
                    Target = $resolvedDisplay
                    TargetRef = $resolvedRef
                    IsRemote = $listRemoteBranches
                    Remote = if ($listRemoteBranches) { $Remote } else { "" }
                }
            }
        return
    }

    if ($listRemoteBranches) {
        Write-Host "Remote branches merged into ${resolvedDisplay}:" -ForegroundColor Cyan
    } else {
        Write-Host "Local branches merged into ${resolvedDisplay}:" -ForegroundColor Cyan
    }
    $mergedBranches | ForEach-Object {
        if ($_.Verdict -eq "squash") {
            Write-Host "  $($_.Name)" -NoNewline -ForegroundColor White
            Write-Host "  (squash-merged)" -ForegroundColor DarkGray
        } else {
            Write-Host "  $($_.Name)" -ForegroundColor White
        }
    }
}

function git-delete-merged-branches {
    param(
        [string]$Branch = "develop",
        [ValidateSet("local", "remote", "auto")]
        [string]$Scope = "local",
        [string]$Remote = "origin",
        [string]$TargetRef,
        [switch]$IncludeCurrent,
        [switch]$IncludeProtected,
        [switch]$Yes,
        [switch]$AsObject,
        [Alias("h", "?")]
        [switch]$Help
    )

    if ($Help) {
        Write-Host "Usage:" -ForegroundColor Cyan
        Write-Host "  git-delete-merged-branches [-Branch <name>] [-Scope <local|remote|auto>] [-Remote <name>] [-TargetRef <ref>] [-IncludeCurrent] [-IncludeProtected] [-Yes] [-help]" -ForegroundColor White
        Write-Host ""
        Write-Host "Behavior:" -ForegroundColor Cyan
        Write-Host "  1) Uses git-list-merged-branches to gather merged branches" -ForegroundColor White
        Write-Host "  2) Prints the branches" -ForegroundColor White
        Write-Host "  3) Prompts for confirmation before deleting" -ForegroundColor White
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Cyan
        Write-Host "  git-delete-merged-branches" -ForegroundColor White
        Write-Host "  git-delete-merged-branches -Branch main -Scope local" -ForegroundColor White
        Write-Host "  git-delete-merged-branches -Branch main -Scope remote -Remote origin" -ForegroundColor White
        return
    }

    $listParams = @{
        Branch = $Branch
        Scope = $Scope
        Remote = $Remote
        IncludeCurrent = $IncludeCurrent
        IncludeProtected = $IncludeProtected
        AsObject = $true
    }

    if ($PSBoundParameters.ContainsKey("TargetRef")) {
        $listParams.TargetRef = $TargetRef
    }

    # Reuse the listing helper as the single source of truth for candidate branches.
    $mergedBranchObjects = git-list-merged-branches @listParams

    if (-not $mergedBranchObjects) {
        return
    }

    if ($mergedBranchObjects -isnot [System.Array]) {
        $mergedBranchObjects = @($mergedBranchObjects)
    }

    $branchNames = $mergedBranchObjects | ForEach-Object { $_.Name } | Where-Object { $_ }
    $squashed = @($mergedBranchObjects | Where-Object { $_.Verdict -eq "squash" })
    if (-not $branchNames -or $branchNames.Count -eq 0) {
        return
    }

    $targetLabel = $mergedBranchObjects[0].Target
    $isRemoteDelete = [bool]$mergedBranchObjects[0].IsRemote
    $deleteRemote = if ($isRemoteDelete -and $mergedBranchObjects[0].Remote) { $mergedBranchObjects[0].Remote } else { $Remote }

    if ($isRemoteDelete) {
        Write-Host "Remote branches merged into ${targetLabel}:" -ForegroundColor Cyan
    } else {
        Write-Host "Local branches merged into ${targetLabel}:" -ForegroundColor Cyan
    }
    $mergedBranchObjects | ForEach-Object {
        if ($_.Verdict -eq "squash") {
            Write-Host "  $($_.Name)" -NoNewline -ForegroundColor White
            Write-Host "  (squash-merged)" -ForegroundColor DarkGray
        } else {
            Write-Host "  $($_.Name)" -ForegroundColor White
        }
    }
    Write-Host ""

    if ($squashed.Count -gt 0 -and -not $isRemoteDelete) {
        # git refuses `branch -d` on a branch it cannot reach by ancestry, so these need -D.
        # Say so before asking: the safety net that normally catches a mistake is not there.
        Write-Host "$($squashed.Count) of these landed as a squash, so git will not see them as merged." -ForegroundColor Yellow
        Write-Host "They will be force-deleted with -D." -ForegroundColor Yellow
        Write-Host ""
    }

    $scopeLabel = if ($isRemoteDelete) { "remote" } else { "local" }
    if (-not $Yes) {
        $confirmation = Read-Host "Delete these $($branchNames.Count) $scopeLabel branch(es)? (y/N)"
        if ($confirmation -ne "y" -and $confirmation -ne "Y") {
            Write-Host "Cancelled." -ForegroundColor DarkGray
            return
        }
    }

    foreach ($record in $mergedBranchObjects) {
        $branchName = $record.Name
        if ($isRemoteDelete) {
            $deleteOutput = git push $deleteRemote --delete $branchName 2>&1
        } elseif ($record.Verdict -eq "squash") {
            $deleteOutput = git branch -D $branchName 2>&1
        } else {
            $deleteOutput = git branch -d $branchName 2>&1
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Deleted: $branchName" -ForegroundColor Green
        } else {
            Write-Host "Could not delete: $branchName" -ForegroundColor Yellow
            if ($deleteOutput) {
                Write-Host "  $deleteOutput" -ForegroundColor DarkGray
            }
        }
    }

    if ($AsObject) {
        $mergedBranchObjects
    }
}
