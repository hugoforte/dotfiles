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

    $targetRef = ""
    $targetDisplay = ""
    $listRemoteBranches = $false

    if ($TargetRef) {
        $targetRef = $TargetRef.Trim()
        $targetDisplay = $targetRef
        if ($targetRef -like "refs/remotes/*") {
            $listRemoteBranches = $true
        }
    } elseif ($Scope -eq "local") {
        $targetRef = "refs/heads/$Branch"
        $targetDisplay = "$Branch (local)"
    } elseif ($Scope -eq "remote") {
        $targetRef = "refs/remotes/$Remote/$Branch"
        $targetDisplay = "$Remote/$Branch"
        $listRemoteBranches = $true
    } else {
        $localRef = "refs/heads/$Branch"
        $remoteRef = "refs/remotes/$Remote/$Branch"

        git show-ref --verify --quiet $localRef
        if ($LASTEXITCODE -eq 0) {
            $targetRef = $localRef
            $targetDisplay = "$Branch (local)"
        } else {
            git show-ref --verify --quiet $remoteRef
            if ($LASTEXITCODE -eq 0) {
                $targetRef = $remoteRef
                $targetDisplay = "$Remote/$Branch"
                $listRemoteBranches = $true
            }
        }
    }

    if (-not $targetRef) {
        Write-Host "Target branch not found in auto mode: local '$Branch' or '$Remote/$Branch'." -ForegroundColor Yellow
        return
    }

    git show-ref --verify --quiet $targetRef
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Target branch not found: $targetDisplay" -ForegroundColor Yellow
        return
    }

    $currentBranch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
    if ($listRemoteBranches) {
        $mergedBranches = git for-each-ref --format="%(refname:short)" --merged $targetRef "refs/remotes/$Remote" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -notlike "*/HEAD" -and $_ -ne $Remote } |
            ForEach-Object {
                if ($_.StartsWith("$Remote/")) {
                    $_.Substring($Remote.Length + 1)
                } else {
                    $_
                }
            } |
            Where-Object { $_ -and $_ -ne $Branch } |
            Where-Object { $IncludeProtected -or ($_ -ne "main" -and $_ -ne "develop") } |
            Select-Object -Unique | Sort-Object
    } else {
        $mergedBranches = git branch --format "%(refname:short)" --merged $targetRef |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -ne $Branch } |
            Where-Object { $IncludeCurrent -or $_ -ne $currentBranch } |
            Where-Object { $IncludeProtected -or ($_ -ne "main" -and $_ -ne "develop") } |
            Select-Object -Unique | Sort-Object
    }

    if ($mergedBranches -isnot [System.Array]) {
        $mergedBranches = @($mergedBranches)
    }

    if (-not $mergedBranches -or $mergedBranches.Count -eq 0) {
        if ($listRemoteBranches) {
            Write-Host "No remote branches are merged into $targetDisplay." -ForegroundColor Yellow
        } else {
            Write-Host "No local branches are merged into $targetDisplay." -ForegroundColor Yellow
        }
        return
    }

    if ($AsObject) {
        $mergedBranches |
            ForEach-Object {
                [PSCustomObject]@{
                    Name = $_
                    Target = $targetDisplay
                    TargetRef = $targetRef
                    IsRemote = $listRemoteBranches
                    Remote = if ($listRemoteBranches) { $Remote } else { "" }
                }
            }
        return
    }

    if ($listRemoteBranches) {
        Write-Host "Remote branches merged into ${targetDisplay}:" -ForegroundColor Cyan
    } else {
        Write-Host "Local branches merged into ${targetDisplay}:" -ForegroundColor Cyan
    }
    $mergedBranches | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
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
        [switch]$AsObject,
        [Alias("h", "?")]
        [switch]$Help
    )

    if ($Help) {
        Write-Host "Usage:" -ForegroundColor Cyan
        Write-Host "  git-delete-merged-branches [-Branch <name>] [-Scope <local|remote|auto>] [-Remote <name>] [-TargetRef <ref>] [-IncludeCurrent] [-IncludeProtected] [-help]" -ForegroundColor White
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
    $branchNames | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
    Write-Host ""

    $scopeLabel = if ($isRemoteDelete) { "remote" } else { "local" }
    $confirmation = Read-Host "Delete these $($branchNames.Count) $scopeLabel branch(es)? (y/N)"
    if ($confirmation -ne "y" -and $confirmation -ne "Y") {
        Write-Host "Cancelled." -ForegroundColor DarkGray
        return
    }

    foreach ($branchName in $branchNames) {
        if ($isRemoteDelete) {
            $deleteOutput = git push $deleteRemote --delete $branchName 2>&1
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
