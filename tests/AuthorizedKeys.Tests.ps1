# ~/.ssh/authorized_keys on Windows is a copy of an overlay's ssh/authorized_keys, kept current by
# the unelevated sync. Everything happens under TestDrive:.

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell\authorized-keys.ps1')

    function New-WorkDir {
        $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $d | Out-Null
        return $d
    }

    function New-KeysFile {
        param([string]$Root, [string]$Content = "ssh-ed25519 AAAA laptop`n")
        $p = Join-Path $Root 'authorized_keys'
        [IO.File]::WriteAllText($p, $Content)
        return $p
    }

    # mklink on Windows, as managed-link.ps1 makes links (Developer Mode, unelevated); ln elsewhere.
    function New-Link {
        param([string]$Path, [string]$Target)
        if ($env:OS -eq 'Windows_NT') { cmd /c mklink "`"$Path`"" "`"$Target`"" | Out-Null } else { ln -s $Target $Path }
    }
}

Describe 'Set-AuthorizedKeysCopy' {

    BeforeEach {
        $work = New-WorkDir
        $src = New-KeysFile $work
        $dst = Join-Path (Join-Path $work '.ssh') 'authorized_keys'
    }

    It 'writes the keys when nothing is there' {
        (Set-AuthorizedKeysCopy -Path $dst -Source $src).Action | Should -Be 'Created'

        [IO.File]::ReadAllText($dst) | Should -BeLike "*ssh-ed25519 AAAA laptop*"
    }

    It 'says where the copy came from, as a comment sshd skips' {
        Set-AuthorizedKeysCopy -Path $dst -Source $src | Out-Null

        (Get-Content -LiteralPath $dst -TotalCount 1) | Should -Be "# Written by dotfiles from $src; the next sync replaces any edit made here."
    }

    It 'writes no byte-order mark, which sshd would read as part of the first line' {
        Set-AuthorizedKeysCopy -Path $dst -Source $src | Out-Null

        [char][IO.File]::ReadAllBytes($dst)[0] | Should -Be '#'
    }

    It 'leaves a current copy alone' {
        Set-AuthorizedKeysCopy -Path $dst -Source $src | Out-Null

        (Set-AuthorizedKeysCopy -Path $dst -Source $src).Action | Should -Be 'AlreadyCorrect'
    }

    It 'replaces its own stale copy without a backup' {
        Set-AuthorizedKeysCopy -Path $dst -Source $src | Out-Null
        [IO.File]::WriteAllText($src, "ssh-ed25519 BBBB desktop`n")

        $result = Set-AuthorizedKeysCopy -Path $dst -Source $src

        $result.Action | Should -Be 'Updated'
        $result.BackupPath | Should -BeNullOrEmpty
        [IO.File]::ReadAllText($dst) | Should -BeLike "*ssh-ed25519 BBBB desktop*"
    }

    It 'backs up a file it did not write before replacing it' {
        New-Item -ItemType Directory -Path (Split-Path $dst -Parent) | Out-Null
        [IO.File]::WriteAllText($dst, "ssh-rsa CCCC someone-elses`n")

        $result = Set-AuthorizedKeysCopy -Path $dst -Source $src

        $result.Action | Should -Be 'BackedUpAndWritten'
        [IO.File]::ReadAllText($result.BackupPath) | Should -Be "ssh-rsa CCCC someone-elses`n"
    }

    It 'writes LF line endings from a CRLF source, and stays current on the next run' {
        [IO.File]::WriteAllText($src, "ssh-ed25519 AAAA laptop`r`nssh-ed25519 BBBB desktop`r`n")

        Set-AuthorizedKeysCopy -Path $dst -Source $src | Out-Null

        [IO.File]::ReadAllText($dst) | Should -Not -BeLike "*`r*"
        (Set-AuthorizedKeysCopy -Path $dst -Source $src).Action | Should -Be 'AlreadyCorrect'
    }

    It 'rewrites a copy whose source changed only in case' {
        Set-AuthorizedKeysCopy -Path $dst -Source $src | Out-Null
        [IO.File]::WriteAllText($src, "ssh-ed25519 AAAA Laptop`n")

        (Set-AuthorizedKeysCopy -Path $dst -Source $src).Action | Should -Be 'Updated'
    }

    It 'replaces a link at the target with the copy' {
        New-Item -ItemType Directory -Path (Split-Path $dst -Parent) | Out-Null
        New-Link -Path $dst -Target (Join-Path $work 'gone')

        Set-AuthorizedKeysCopy -Path $dst -Source $src | Out-Null

        (Get-Item -LiteralPath $dst -Force).LinkType | Should -BeNullOrEmpty
        [IO.File]::ReadAllText($dst) | Should -BeLike "*ssh-ed25519 AAAA laptop*"
    }

    It 'refuses a source that does not exist' {
        { Set-AuthorizedKeysCopy -Path $dst -Source (Join-Path $work 'missing') } | Should -Throw '*does not exist*'
    }
}

Describe 'Remove-AuthorizedKeysCopy' {

    BeforeEach {
        $work = New-WorkDir
        $src = New-KeysFile $work
        $dst = Join-Path (Join-Path $work '.ssh') 'authorized_keys'
    }

    It 'removes its own copy, so keys taken out of every overlay stop working' {
        Set-AuthorizedKeysCopy -Path $dst -Source $src | Out-Null

        (Remove-AuthorizedKeysCopy -Path $dst).Action | Should -Be 'Removed'
        Test-Path -LiteralPath $dst | Should -BeFalse
    }

    It 'leaves a file it did not write' {
        New-Item -ItemType Directory -Path (Split-Path $dst -Parent) | Out-Null
        [IO.File]::WriteAllText($dst, "ssh-rsa CCCC someone-elses`n")

        (Remove-AuthorizedKeysCopy -Path $dst).Action | Should -Be 'NotOurs'
        [IO.File]::ReadAllText($dst) | Should -Be "ssh-rsa CCCC someone-elses`n"
    }

    It 'reports nothing there' {
        (Remove-AuthorizedKeysCopy -Path $dst).Action | Should -Be 'Missing'
    }

    It 'changes nothing with -Check' {
        Set-AuthorizedKeysCopy -Path $dst -Source $src | Out-Null

        (Remove-AuthorizedKeysCopy -Path $dst -Check).Action | Should -Be 'Removed'
        Test-Path -LiteralPath $dst | Should -BeTrue
    }
}

Describe 'Test-AuthorizedKeysCopy' {

    BeforeEach {
        $work = New-WorkDir
        $src = New-KeysFile $work
        $dst = Join-Path (Join-Path $work '.ssh') 'authorized_keys'
    }

    It 'reports a missing copy' {
        (Test-AuthorizedKeysCopy -Path $dst -Source $src).Reason | Should -Be 'Missing'
    }

    It 'reports a current copy as correct' {
        Set-AuthorizedKeysCopy -Path $dst -Source $src | Out-Null

        (Test-AuthorizedKeysCopy -Path $dst -Source $src).IsCorrect | Should -BeTrue
    }

    It 'reports its own copy behind the source as stale' {
        Set-AuthorizedKeysCopy -Path $dst -Source $src | Out-Null
        [IO.File]::WriteAllText($src, "ssh-ed25519 BBBB desktop`n")

        (Test-AuthorizedKeysCopy -Path $dst -Source $src).Reason | Should -Be 'Stale'
    }

    It 'reports a file it did not write as not its own' {
        New-Item -ItemType Directory -Path (Split-Path $dst -Parent) | Out-Null
        [IO.File]::WriteAllText($dst, "ssh-rsa CCCC someone-elses`n")

        (Test-AuthorizedKeysCopy -Path $dst -Source $src).Reason | Should -Be 'NotOurs'
    }

    It 'changes nothing' {
        Test-AuthorizedKeysCopy -Path $dst -Source $src | Out-Null

        Test-Path -LiteralPath $dst | Should -BeFalse
    }
}
