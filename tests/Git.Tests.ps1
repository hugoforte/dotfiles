# Pester 5 suite for powershell/git.ps1, run under Windows PowerShell 5.1.
#
# The seam under test is how a branch is judged merged. `git branch --merged` answers ancestry
# only, so it is right about merge commits and fast-forwards and wrong about every squash merge.
# Each Context builds a real repository under TestDrive: and merges into it one way, because the
# difference between the three merge styles is the whole subject.
#
# Nothing here touches the real machine or the network: every repository is created, committed to
# and thrown away inside TestDrive:, and no remote is ever contacted.

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $RepoRoot 'powershell/git.ps1')

    # A repository with `main` and nothing else. Identity is set locally so the suite does not
    # depend on, or touch, the machine's git config.
    function New-TestRepo {
        $path = Join-Path ([string]$TestDrive) ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $path | Out-Null
        Push-Location $path
        git init --quiet --initial-branch=main 2>&1 | Out-Null
        git config user.email 'test@example.com'
        git config user.name 'Test'
        git config commit.gpgsign false
        # Without this git warns about LF to CRLF on every add, and a native command writing to
        # stderr is an error to Pester.
        git config core.autocrlf false
        Set-Content -Path 'base.txt' -Value 'base' -Encoding utf8
        git add -A 2>&1 | Out-Null
        git commit --quiet -m 'base' 2>&1 | Out-Null
        Pop-Location
        return $path
    }

    # A branch off main carrying $Count commits, each touching its own file.
    function New-FeatureBranch {
        param(
            [Parameter(Mandatory)][string]$Name,
            [int]$Count = 2
        )
        # Branch names carry slashes, and a slash in a file name would ask for a directory.
        $stem = $Name.Replace('/', '-')
        git checkout --quiet -b $Name main 2>&1 | Out-Null
        1..$Count | ForEach-Object {
            Set-Content -Path "$stem-$_.txt" -Value "$Name $_" -Encoding utf8
            git add -A 2>&1 | Out-Null
            git commit --quiet -m "$Name commit $_" 2>&1 | Out-Null
        }
        git checkout --quiet main 2>&1 | Out-Null
    }

    # What GitHub's "Squash and merge" does: one new commit on main carrying the branch's tree,
    # sharing no sha with any commit on the branch.
    function Invoke-SquashMerge {
        param([Parameter(Mandatory)][string]$Name)
        git checkout --quiet main 2>&1 | Out-Null
        git merge --quiet --squash $Name 2>&1 | Out-Null
        git commit --quiet -m "$Name squashed (#1)" 2>&1 | Out-Null
    }

    # A bare repository beside the work tree, wired up as `origin`. The remote scope is the only
    # one whose delete is irreversible, so it needs a real remote rather than a stand-in.
    function New-BareOrigin {
        $bare = Join-Path ([string]$TestDrive) ([guid]::NewGuid().ToString('n') + '.git')
        git init --quiet --bare $bare 2>&1 | Out-Null
        git remote add origin $bare 2>&1 | Out-Null
        git push --quiet origin main 2>&1 | Out-Null
        return $bare
    }

    function Get-MergedNames {
        param([string]$Branch = 'main')
        $listed = git-list-merged-branches -Branch $Branch -Scope local -AsObject -IncludeCurrent
        return @($listed | ForEach-Object { $_.Name })
    }
}

Describe 'git.ps1 merged-branch detection' {

    Context 'A squash merge, which is what GitHub does by default' {

        BeforeAll {
            $repo = New-TestRepo
            Push-Location $repo
            New-FeatureBranch -Name 'feat/squashed' -Count 2
            Invoke-SquashMerge -Name 'feat/squashed'
        }

        AfterAll { Pop-Location }

        # Premise, not coverage: this pins the git behaviour the rest of the file exists to work
        # around. It cannot go red for a defect in git.ps1 - only if upstream git changes.
        It 'premise: git branch --merged cannot see it' {
            $ancestry = @(git branch --format '%(refname:short)' --merged main | ForEach-Object { $_.Trim() })
            $ancestry | Should -Not -Contain 'feat/squashed'
        }

        It 'is reported as merged' {
            Test-BranchMerged -BranchRef 'feat/squashed' -TargetRef 'main' | Should -BeTrue
        }

        It 'is listed by git-list-merged-branches' {
            Get-MergedNames | Should -Contain 'feat/squashed'
        }
    }

    Context 'A merge commit, which ancestry already answered' {

        BeforeAll {
            $repo = New-TestRepo
            Push-Location $repo
            New-FeatureBranch -Name 'feat/merged' -Count 2
            git merge --quiet --no-ff -m 'merge feat/merged' 'feat/merged' 2>&1 | Out-Null
        }

        AfterAll { Pop-Location }

        It 'is still listed' {
            Get-MergedNames | Should -Contain 'feat/merged'
        }
    }

    Context 'A fast-forward, the other case ancestry answered' {

        BeforeAll {
            $repo = New-TestRepo
            Push-Location $repo
            New-FeatureBranch -Name 'feat/ff' -Count 1
            git merge --quiet --ff-only 'feat/ff' 2>&1 | Out-Null
        }

        AfterAll { Pop-Location }

        It 'is still listed' {
            Get-MergedNames | Should -Contain 'feat/ff'
        }
    }

    Context 'A branch that was never merged' {

        BeforeAll {
            $repo = New-TestRepo
            Push-Location $repo
            New-FeatureBranch -Name 'feat/open' -Count 2
        }

        AfterAll { Pop-Location }

        It 'is not reported as merged' {
            Test-BranchMerged -BranchRef 'feat/open' -TargetRef 'main' | Should -BeFalse
        }

        It 'is not listed' {
            Get-MergedNames | Should -Not -Contain 'feat/open'
        }
    }

    Context 'A branch squash-merged, then continued' {

        BeforeAll {
            $repo = New-TestRepo
            Push-Location $repo
            New-FeatureBranch -Name 'feat/continued' -Count 1
            Invoke-SquashMerge -Name 'feat/continued'
            git checkout --quiet 'feat/continued' 2>&1 | Out-Null
            Set-Content -Path 'continued-later.txt' -Value 'later' -Encoding utf8
            git add -A 2>&1 | Out-Null
            git commit --quiet -m 'work after the squash' 2>&1 | Out-Null
            git checkout --quiet main 2>&1 | Out-Null
        }

        AfterAll { Pop-Location }

        It 'is not reported as merged, because it now carries work main has not got' {
            Test-BranchMerged -BranchRef 'feat/continued' -TargetRef 'main' | Should -BeFalse
        }
    }

    Context 'Branches the listing excludes whatever their merge state' {

        BeforeAll {
            $repo = New-TestRepo
            Push-Location $repo
            New-FeatureBranch -Name 'feat/squashed' -Count 1
            Invoke-SquashMerge -Name 'feat/squashed'
            git branch develop main 2>&1 | Out-Null
        }

        AfterAll { Pop-Location }

        It 'leaves out the target branch itself' {
            Get-MergedNames | Should -Not -Contain 'main'
        }

        It 'leaves out develop unless asked for it' {
            Get-MergedNames | Should -Not -Contain 'develop'
        }

        It 'includes develop with -IncludeProtected' {
            $listed = git-list-merged-branches -Branch main -Scope local -AsObject -IncludeCurrent -IncludeProtected
            @($listed | ForEach-Object { $_.Name }) | Should -Contain 'develop'
        }

        It 'leaves out the current branch unless asked for it' {
            git checkout --quiet 'feat/squashed' 2>&1 | Out-Null
            try {
                $listed = git-list-merged-branches -Branch main -Scope local -AsObject
                @($listed | ForEach-Object { $_.Name }) | Should -Not -Contain 'feat/squashed'
            } finally {
                git checkout --quiet main 2>&1 | Out-Null
            }
        }
    }

    Context 'A branch that differs only in whitespace' {

        BeforeAll {
            $repo = New-TestRepo
            Push-Location $repo
            Set-Content -Path 'f.txt' -Value "line1`nline2" -Encoding utf8
            git add -A 2>&1 | Out-Null
            git commit --quiet -m 'f base' 2>&1 | Out-Null

            git checkout --quiet -b 'feat/ws' main 2>&1 | Out-Null
            Set-Content -Path 'f.txt' -Value "line1`nline2`nline3   " -Encoding utf8
            git add -A 2>&1 | Out-Null
            git commit --quiet -m 'line3, with trailing spaces' 2>&1 | Out-Null

            # main gains the same line without the trailing whitespace: a different patch, which
            # patch-id would call identical unless it is asked not to normalise.
            git checkout --quiet main 2>&1 | Out-Null
            Set-Content -Path 'f.txt' -Value "line1`nline2`nline3" -Encoding utf8
            git add -A 2>&1 | Out-Null
            git commit --quiet -m 'line3 (#7)' 2>&1 | Out-Null
        }

        AfterAll { Pop-Location }

        It 'is not merged, because the files genuinely differ' {
            Test-BranchMerged -BranchRef 'feat/ws' -TargetRef 'main' | Should -BeFalse
        }
    }

    Context 'A tag sharing a branch name' {

        BeforeAll {
            $repo = New-TestRepo
            Push-Location $repo
            git tag release main 2>&1 | Out-Null
            New-FeatureBranch -Name 'release' -Count 1
        }

        AfterAll { Pop-Location }

        It 'answers for the branch, not the tag git would resolve first' {
            Test-BranchMerged -BranchRef 'release' -TargetRef 'main' | Should -BeFalse
        }
    }

    Context 'The -TargetRef argument' {

        BeforeAll {
            $repo = New-TestRepo
            Push-Location $repo
            git branch develop main 2>&1 | Out-Null
            New-FeatureBranch -Name 'feat/only-in-develop' -Count 1
            git checkout --quiet develop 2>&1 | Out-Null
            git merge --quiet --no-ff -m 'merge' 'feat/only-in-develop' 2>&1 | Out-Null
            git checkout --quiet main 2>&1 | Out-Null
        }

        AfterAll { Pop-Location }

        It 'is honoured rather than silently discarded' {
            $listed = git-list-merged-branches -TargetRef 'refs/heads/main' -AsObject -IncludeCurrent
            @($listed | ForEach-Object { $_.Name }) | Should -Not -Contain 'feat/only-in-develop'
        }
    }

    Context 'The remote scope' {

        BeforeAll {
            $repo = New-TestRepo
            Push-Location $repo
            New-BareOrigin | Out-Null
            New-FeatureBranch -Name 'feat/rsq' -Count 1
            New-FeatureBranch -Name 'feat/rnever' -Count 1
            git push --quiet origin 'feat/rsq' 'feat/rnever' 2>&1 | Out-Null
            Invoke-SquashMerge -Name 'feat/rsq'
            git push --quiet origin main 2>&1 | Out-Null
            git fetch --quiet origin 2>&1 | Out-Null
        }

        AfterAll { Pop-Location }

        It 'lists a squash-merged remote branch' {
            $listed = git-list-merged-branches -Branch main -Scope remote -AsObject
            @($listed | ForEach-Object { $_.Name }) | Should -Contain 'feat/rsq'
        }

        It 'leaves an unmerged remote branch alone' {
            $listed = git-list-merged-branches -Branch main -Scope remote -AsObject
            @($listed | ForEach-Object { $_.Name }) | Should -Not -Contain 'feat/rnever'
        }
    }

    Context 'Deleting what was listed' {

        BeforeAll {
            $repo = New-TestRepo
            Push-Location $repo
            New-FeatureBranch -Name 'feat/sq' -Count 2
            Invoke-SquashMerge -Name 'feat/sq'
            New-FeatureBranch -Name 'feat/ff' -Count 1
            git merge --quiet --ff-only 'feat/ff' 2>&1 | Out-Null
            New-FeatureBranch -Name 'feat/open' -Count 1
            git-delete-merged-branches -Branch main -Scope local -Yes 6>&1 | Out-Null
        }

        AfterAll { Pop-Location }

        It 'actually removes a squash-merged branch, which git branch -d refuses to do' {
            @(git branch --format '%(refname:short)') | Should -Not -Contain 'feat/sq'
        }

        It 'actually removes an ancestry-merged branch' {
            @(git branch --format '%(refname:short)') | Should -Not -Contain 'feat/ff'
        }

        It 'keeps the branch that was never merged' {
            @(git branch --format '%(refname:short)') | Should -Contain 'feat/open'
        }

        It 'keeps the target branch' {
            @(git branch --format '%(refname:short)') | Should -Contain 'main'
        }
    }

    Context 'The verdict a listing carries' {

        BeforeAll {
            $repo = New-TestRepo
            Push-Location $repo
            New-FeatureBranch -Name 'feat/sq' -Count 1
            Invoke-SquashMerge -Name 'feat/sq'
            New-FeatureBranch -Name 'feat/ff' -Count 1
            git merge --quiet --ff-only 'feat/ff' 2>&1 | Out-Null
        }

        AfterAll { Pop-Location }

        It 'says squash for the one git cannot see' {
            Get-BranchMergeVerdict -BranchRef 'feat/sq' -TargetRef 'main' | Should -Be 'squash'
        }

        It 'says ancestor for the one it can' {
            Get-BranchMergeVerdict -BranchRef 'feat/ff' -TargetRef 'main' | Should -Be 'ancestor'
        }

        It 'says no for the one that never landed' {
            New-FeatureBranch -Name 'feat/open' -Count 1
            Get-BranchMergeVerdict -BranchRef 'feat/open' -TargetRef 'main' | Should -Be 'no'
        }
    }
}
