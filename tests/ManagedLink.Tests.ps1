# The managed link is one idea implemented seven times across three mechanisms
# (hugoforte/dotfiles#6). These tests are the contract the one module has to meet, and they
# were written before it existed.
#
# Everything happens under TestDrive:. Nothing here creates a link anywhere a real machine
# would notice, and nothing needs elevation - which is the point of the module choosing
# `cmd /c mklink` over `New-Item -ItemType SymbolicLink`. See the work's context doc for the
# probe that settled that.

BeforeAll {
    # Two-argument Join-Path only: the three-argument form is PowerShell 7+, and these
    # scripts target Windows PowerShell 5.1.
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell\managed-link.ps1')

    # Pester's TestDrive is per *file*, not per test, so without this every test sees the
    # links the previous ones left behind - which is how the first run of these tests failed.
    function New-WorkDir {
        $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $d | Out-Null
        return $d
    }

    function New-SourceFile {
        param([string]$Root, [string]$Name = 'source.txt', [string]$Content = 'from the repo')
        $p = Join-Path $Root $Name
        Set-Content -LiteralPath $p -Value $Content -NoNewline
        return $p
    }

    # The property that matters everywhere: the target is a symlink AND resolves to the source.
    function Assert-LinkedTo {
        param([string]$Path, [string]$Source)
        $item = Get-Item -LiteralPath $Path -Force
        $item.LinkType | Should -Be 'SymbolicLink'
        ($item.Target | Select-Object -First 1) | Should -Be $Source
    }
}

Describe 'Set-ManagedLink' {

    BeforeEach { $work = New-WorkDir }

    Context 'when nothing is at the target' {

        It 'creates the link' {
            $src = New-SourceFile $work
            $dst = Join-Path $work 'link.txt'

            Set-ManagedLink -Path $dst -Source $src | Out-Null

            Assert-LinkedTo -Path $dst -Source $src
        }

        It 'makes the source readable through the target' {
            $src = New-SourceFile $work -Content 'hello through the link'
            $dst = Join-Path $work 'link.txt'

            Set-ManagedLink -Path $dst -Source $src | Out-Null

            (Get-Content -LiteralPath $dst -Raw) | Should -Be 'hello through the link'
        }

        It 'creates a missing parent directory rather than failing' {
            $src = New-SourceFile $work
            $dst = Join-Path $work 'nested\deeper\link.txt'

            Set-ManagedLink -Path $dst -Source $src | Out-Null

            Assert-LinkedTo -Path $dst -Source $src
        }

        It 'reports that it created the link' {
            $src = New-SourceFile $work
            $dst = Join-Path $work 'link.txt'

            $r = Set-ManagedLink -Path $dst -Source $src

            $r.Action | Should -Be 'Created'
        }
    }

    Context 'when the correct link is already there' {

        It 'is idempotent and says so' {
            $src = New-SourceFile $work
            $dst = Join-Path $work 'link.txt'
            Set-ManagedLink -Path $dst -Source $src | Out-Null

            $r = Set-ManagedLink -Path $dst -Source $src

            $r.Action | Should -Be 'AlreadyCorrect'
            Assert-LinkedTo -Path $dst -Source $src
        }

        It 'takes no backup, because nothing was displaced' {
            $src = New-SourceFile $work
            $dst = Join-Path $work 'link.txt'
            Set-ManagedLink -Path $dst -Source $src | Out-Null

            $r = Set-ManagedLink -Path $dst -Source $src

            $r.BackupPath | Should -BeNullOrEmpty
            @(Get-ChildItem -LiteralPath $work -Filter '*.backup.*').Count | Should -Be 0
        }
    }

    Context 'when a link to somewhere else is there' {

        It 'repoints it without backing anything up' {
            $src = New-SourceFile $work
            $other = New-SourceFile $work -Name 'other.txt' -Content 'somewhere else'
            $dst = Join-Path $work 'link.txt'
            Set-ManagedLink -Path $dst -Source $other | Out-Null

            $r = Set-ManagedLink -Path $dst -Source $src

            $r.Action | Should -Be 'Repointed'
            $r.BackupPath | Should -BeNullOrEmpty
            Assert-LinkedTo -Path $dst -Source $src
        }

        It 'leaves the file the old link pointed at alone' {
            $src = New-SourceFile $work
            $other = New-SourceFile $work -Name 'other.txt' -Content 'somewhere else'
            $dst = Join-Path $work 'link.txt'
            Set-ManagedLink -Path $dst -Source $other | Out-Null

            Set-ManagedLink -Path $dst -Source $src | Out-Null

            (Get-Content -LiteralPath $other -Raw) | Should -Be 'somewhere else'
        }
    }

    Context 'when a real file is in the way' {

        It 'backs it up rather than refusing or destroying it' {
            $src = New-SourceFile $work
            $dst = Join-Path $work 'link.txt'
            Set-Content -LiteralPath $dst -Value 'the user wrote this' -NoNewline

            $r = Set-ManagedLink -Path $dst -Source $src

            $r.Action | Should -Be 'BackedUpAndLinked'
            $r.BackupPath | Should -Not -BeNullOrEmpty
            (Get-Content -LiteralPath $r.BackupPath -Raw) | Should -Be 'the user wrote this'
            Assert-LinkedTo -Path $dst -Source $src
        }

        It 'puts the backup beside the target by default' {
            $src = New-SourceFile $work
            $dst = Join-Path $work 'link.txt'
            Set-Content -LiteralPath $dst -Value 'the user wrote this' -NoNewline

            $r = Set-ManagedLink -Path $dst -Source $src

            (Split-Path $r.BackupPath -Parent) | Should -Be (Split-Path $dst -Parent)
            (Split-Path $r.BackupPath -Leaf) | Should -BeLike 'link.txt.backup.*'
        }

        It 'puts the backup where BackupDir says, which is why deploy-secrets can keep plaintext out of a checkout' {
            $src = New-SourceFile $work
            $dst = Join-Path $work 'checkout\.secrets.env'
            New-Item -ItemType Directory -Path (Split-Path $dst -Parent) | Out-Null
            Set-Content -LiteralPath $dst -Value 'API_KEY=hunter2' -NoNewline
            $vault = Join-Path $work 'vault'

            $r = Set-ManagedLink -Path $dst -Source $src -BackupDir $vault

            (Split-Path $r.BackupPath -Parent) | Should -Be $vault
            (Get-Content -LiteralPath $r.BackupPath -Raw) | Should -Be 'API_KEY=hunter2'
            # The displaced plaintext must not still be sitting in the checkout.
            @(Get-ChildItem -LiteralPath (Split-Path $dst -Parent) -Filter '*.backup.*').Count | Should -Be 0
        }

        It 'creates BackupDir when it does not exist' {
            $src = New-SourceFile $work
            $dst = Join-Path $work 'link.txt'
            Set-Content -LiteralPath $dst -Value 'displaced' -NoNewline
            $vault = Join-Path $work 'not\yet\there'

            $r = Set-ManagedLink -Path $dst -Source $src -BackupDir $vault

            Test-Path -LiteralPath $r.BackupPath | Should -BeTrue
        }
    }

    Context 'when the source does not exist' {

        It 'refuses rather than creating a broken link' {
            $dst = Join-Path $work 'link.txt'
            $missing = Join-Path $work 'no-such-file.txt'

            { Set-ManagedLink -Path $dst -Source $missing } | Should -Throw

            Test-Path -LiteralPath $dst | Should -BeFalse
        }
    }

    Context 'when the source is a directory' {

        # mklink without /D against a directory makes a *file* symlink that never resolves.
        # No PowerShell caller here links a directory - ai/install.sh does its own with `ln -s`
        # - so this refuses loudly rather than carrying an untested /D path.
        It 'refuses, rather than making a link that does not resolve' {
            $srcDir = Join-Path $work 'a-directory'
            New-Item -ItemType Directory -Path $srcDir | Out-Null
            $dst = Join-Path $work 'link'

            { Set-ManagedLink -Path $dst -Source $srcDir } | Should -Throw

            Test-Path -LiteralPath $dst | Should -BeFalse
        }
    }
}

Describe 'Test-ManagedLink' {

    BeforeEach { $work = New-WorkDir }

    It 'is true for a link pointing at the source' {
        $src = New-SourceFile $work
        $dst = Join-Path $work 'link.txt'
        Set-ManagedLink -Path $dst -Source $src | Out-Null

        (Test-ManagedLink -Path $dst -Source $src).IsCorrect | Should -BeTrue
    }

    It 'is false, and says why, when nothing is there' {
        $src = New-SourceFile $work
        $dst = Join-Path $work 'link.txt'

        $r = Test-ManagedLink -Path $dst -Source $src

        $r.IsCorrect | Should -BeFalse
        $r.Reason | Should -Be 'Missing'
    }

    It 'is false, and says why, when a real file is there' {
        $src = New-SourceFile $work
        $dst = Join-Path $work 'link.txt'
        Set-Content -LiteralPath $dst -Value 'not a link' -NoNewline

        $r = Test-ManagedLink -Path $dst -Source $src

        $r.IsCorrect | Should -BeFalse
        $r.Reason | Should -Be 'NotALink'
    }

    It 'is false, and says why, when it points somewhere else' {
        $src = New-SourceFile $work
        $other = New-SourceFile $work -Name 'other.txt'
        $dst = Join-Path $work 'link.txt'
        Set-ManagedLink -Path $dst -Source $other | Out-Null

        $r = Test-ManagedLink -Path $dst -Source $src

        $r.IsCorrect | Should -BeFalse
        $r.Reason | Should -Be 'WrongTarget'
    }

    It 'reports where a wrong link actually points, so a human can judge it' {
        $src = New-SourceFile $work
        $other = New-SourceFile $work -Name 'other.txt'
        $dst = Join-Path $work 'link.txt'
        Set-ManagedLink -Path $dst -Source $other | Out-Null

        (Test-ManagedLink -Path $dst -Source $src).ActualTarget | Should -Be $other
    }

    It 'changes nothing it looks at' {
        $src = New-SourceFile $work
        $dst = Join-Path $work 'link.txt'
        Set-Content -LiteralPath $dst -Value 'not a link' -NoNewline

        Test-ManagedLink -Path $dst -Source $src | Out-Null

        (Get-Content -LiteralPath $dst -Raw) | Should -Be 'not a link'
        @(Get-ChildItem -LiteralPath $work -Filter '*.backup.*').Count | Should -Be 0
    }
}

Describe 'Remove-ManagedLink' {

    BeforeEach { $work = New-WorkDir }

    It 'removes a link' {
        $src = New-SourceFile $work
        $dst = Join-Path $work 'link.txt'
        Set-ManagedLink -Path $dst -Source $src | Out-Null

        $r = Remove-ManagedLink -Path $dst

        $r.Action | Should -Be 'Removed'
        Test-Path -LiteralPath $dst | Should -BeFalse
    }

    It 'leaves the source alone when it removes the link' {
        $src = New-SourceFile $work
        $dst = Join-Path $work 'link.txt'
        Set-ManagedLink -Path $dst -Source $src | Out-Null

        Remove-ManagedLink -Path $dst | Out-Null

        (Get-Content -LiteralPath $src -Raw) | Should -Be 'from the repo'
    }

    It 'never removes a real file, whatever else happens' {
        $dst = Join-Path $work 'real.txt'
        Set-Content -LiteralPath $dst -Value 'precious' -NoNewline

        $r = Remove-ManagedLink -Path $dst

        $r.Action | Should -Be 'NotALink'
        (Get-Content -LiteralPath $dst -Raw) | Should -Be 'precious'
    }

    It 'is quietly fine when there is nothing to remove' {
        $dst = Join-Path $work 'never-existed.txt'

        $r = Remove-ManagedLink -Path $dst

        $r.Action | Should -Be 'Missing'
    }
}

Describe 'Remove-DanglingManagedLink' {

    BeforeEach {
        $work = New-WorkDir
        $repo = Join-Path $work 'repo'
        New-Item -ItemType Directory -Path $repo | Out-Null
    }

    It 'removes a link into the repo whose source was deleted' {
        $src = New-SourceFile $repo
        $dst = Join-Path $work 'link.txt'
        Set-ManagedLink -Path $dst -Source $src | Out-Null
        Remove-Item -LiteralPath $src

        (Remove-DanglingManagedLink -Path $dst -Under $repo).Action | Should -Be 'Removed'
        Test-Path -LiteralPath $dst | Should -BeFalse
    }

    It 'keeps a link into the repo that still resolves' {
        $src = New-SourceFile $repo
        $dst = Join-Path $work 'link.txt'
        Set-ManagedLink -Path $dst -Source $src | Out-Null

        (Remove-DanglingManagedLink -Path $dst -Under $repo).Action | Should -Be 'Kept'
        Assert-LinkedTo -Path $dst -Source $src
    }

    It 'keeps a dangling link that points outside the repo, because it is not ours' {
        $elsewhere = Join-Path $work 'elsewhere'
        New-Item -ItemType Directory -Path $elsewhere | Out-Null
        $src = New-SourceFile $elsewhere
        $dst = Join-Path $work 'link.txt'
        Set-ManagedLink -Path $dst -Source $src | Out-Null
        Remove-Item -LiteralPath $src

        (Remove-DanglingManagedLink -Path $dst -Under $repo).Action | Should -Be 'Kept'
        (Get-Item -LiteralPath $dst -Force).LinkType | Should -Be 'SymbolicLink'
    }

    It 'keeps a real file' {
        $dst = Join-Path $work 'real.txt'
        Set-Content -LiteralPath $dst -Value 'precious' -NoNewline

        (Remove-DanglingManagedLink -Path $dst -Under $repo).Action | Should -Be 'Kept'
        (Get-Content -LiteralPath $dst -Raw) | Should -Be 'precious'
    }

    It 'is quietly fine when there is nothing there' {
        (Remove-DanglingManagedLink -Path (Join-Path $work 'none') -Under $repo).Action | Should -Be 'Missing'
    }
}
