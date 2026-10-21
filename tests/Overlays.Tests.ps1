# The overlay rules in PowerShell (hugoforte/dotfiles#67): which overlays a machine lists, the one
# source or every source of a path, the entries under a directory, the machine key, the overlay
# repositories, how skill registries merge, and what ~/.gitconfig-overlays includes. The sh twin is
# tests/overlays.test.sh. Everything happens under TestDrive:.

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell\overlays.ps1')

    function New-WorkDir {
        $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $d | Out-Null
        return $d
    }

    function New-File {
        param([string]$Path, [string]$Content = 'x')
        New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
        Set-Content -LiteralPath $Path -Value $Content
    }

    function New-Registry {
        param([string]$Root, [string[]]$Ids)
        $skills = ($Ids | ForEach-Object {
            "@{ Id = '$_'; Marker = '.claude/skills/$_'; Remote = 'github.com/x/$_'; Files = @('.secrets.env') }"
        }) -join "`n"
        New-File (Join-Path $Root 'ai\secrets\registry.psd1') "@{ Skills = @(`n$skills`n) }"
    }
}

Describe 'Test-SkillSecretsOptIn' {

    BeforeEach { $work = New-WorkDir }

    It 'is off when the machine has no machine.local.psd1' {
        Test-SkillSecretsOptIn -LocalPath (Join-Path $work 'machine.local.psd1') | Should -BeFalse
    }

    It 'is off when machine.local.psd1 declares no SearchRoots, as one written only for OptionalTools' {
        $local = Join-Path $work 'machine.local.psd1'
        New-File $local "@{ OptionalTools = @('openwhispr') }"

        Test-SkillSecretsOptIn -LocalPath $local | Should -BeFalse
    }

    It 'is on when machine.local.psd1 declares SearchRoots empty, so deploy-secrets.ps1 reports it' {
        $local = Join-Path $work 'machine.local.psd1'
        New-File $local "@{ SearchRoots = @() }"

        Test-SkillSecretsOptIn -LocalPath $local | Should -BeTrue
    }

    It 'is on when machine.local.psd1 declares SearchRoots' {
        $local = Join-Path $work 'machine.local.psd1'
        New-File $local "@{ SearchRoots = @('C:\source') }"

        Test-SkillSecretsOptIn -LocalPath $local | Should -BeTrue
    }
}

Describe 'Get-Overlays' {

    BeforeEach {
        $repo = New-WorkDir
        $local = Join-Path $repo 'ai\secrets\machine.local.psd1'
    }

    It 'lists no overlays when the machine has no machine.local.psd1' {
        @((Get-Overlays -RepoPath $repo).Overlays).Count | Should -Be 0
    }

    It 'lists no overlays when machine.local.psd1 lists none' {
        New-File $local "@{ SearchRoots = @('C:\source') }"

        @((Get-Overlays -RepoPath $repo).Overlays).Count | Should -Be 0
    }

    It 'returns the listed overlays in order' {
        $a = New-WorkDir; $b = New-WorkDir
        New-File $local "@{ Overlays = @('$a', '$b') }"

        (Get-Overlays -RepoPath $repo).Overlays | Should -Be @($a, $b)
    }

    It 'fails, naming the path, when a listed overlay does not exist' {
        $missing = Join-Path $repo 'no-such-overlay'
        New-File $local "@{ Overlays = @('$missing') }"

        { Get-Overlays -RepoPath $repo } | Should -Throw "*$missing*"
    }

    It 'takes overlays passed in place of the file''s list, checked the same way' {
        $a = New-WorkDir
        New-File $local "@{ Overlays = @('$(Join-Path $repo 'gone')') }"

        (Get-Overlays -RepoPath $repo -Overlays $a).Overlays | Should -Be @($a)
        { Get-Overlays -RepoPath $repo -Overlays (Join-Path $repo 'also-gone') } | Should -Throw '*also-gone*'
    }

    It 'keys the machine by its name uppercased, up to its first dot' {
        (Get-Overlays -RepoPath $repo -ComputerName 'box.example.com').MachineKey | Should -Be 'BOX'
    }

    It 'lists a repository holding two overlays once' {
        $private = New-WorkDir
        git -C $private init -q
        $a = Join-Path $private 'a'; $b = Join-Path $private 'b'
        New-Item -ItemType Directory -Path $a, $b | Out-Null

        (Get-Overlays -RepoPath $repo -Overlays $a, $b).RepoRoots | Should -Be @([IO.Path]::GetFullPath($private))
    }

    It 'leaves out an overlay that is not in a repository' {
        @((Get-Overlays -RepoPath $repo -Overlays (New-WorkDir)).RepoRoots).Count | Should -Be 0
    }
}

Describe 'Get-OverlaySource' {

    BeforeEach {
        $repo = New-WorkDir; $a = New-WorkDir; $b = New-WorkDir
        $set = Get-Overlays -RepoPath $repo -Overlays $a, $b -ComputerName 'box'
    }

    It 'has no source for a one path no root ships' {
        @(Get-OverlaySource -Set $set -Path 'aws/config').Count | Should -Be 0
    }

    It 'has the source that ships a one path' {
        New-File (Join-Path $b 'aws\config')

        Get-OverlaySource -Set $set -Path 'aws/config' | Should -Be (Join-Path $b 'aws\config')
    }

    It 'fails, naming both, when two roots ship a one path' {
        New-File (Join-Path $repo 'aws\config')
        New-File (Join-Path $b 'aws\config')

        { Get-OverlaySource -Set $set -Path 'aws/config' } | Should -Throw "*$repo*$b*"
    }

    It 'ignores the repo for a path read from the overlays alone' {
        New-File (Join-Path $repo 'ssh\authorized_keys')

        @(Get-OverlaySource -Set $set -Path 'ssh/authorized_keys').Count | Should -Be 0
    }

    It 'reads {KEY} as the machine key' {
        New-File (Join-Path $a 'machines\BOX.psd1')
        New-File (Join-Path $a 'machines\OTHER.psd1')

        Get-OverlaySource -Set $set -Path 'machines/{KEY}.psd1' | Should -Be (Join-Path $a 'machines\BOX.psd1')
    }

    It 'matches nothing for a {KEY} path on a machine with no key' {
        New-File (Join-Path $a 'machines\BOX.psd1')
        $nameless = Get-Overlays -RepoPath $repo -Overlays $a -ComputerName ''

        @(Get-OverlaySource -Set $nameless -Path 'machines/{KEY}.psd1').Count | Should -Be 0
    }

    It 'has each overlay''s folder for a path ending in /' {
        New-File (Join-Path $a 'machines\OTHER.psd1')
        New-File (Join-Path $b 'machines')

        Get-OverlaySource -Set $set -Path 'machines/' | Should -Be (Join-Path $a 'machines')
    }

    It 'has every source of an all path, in overlay order' {
        New-File (Join-Path $b 'git\gitconfig')
        New-File (Join-Path $a 'git\gitconfig')

        Get-OverlaySource -Set $set -Path 'git/gitconfig' | Should -Be @((Join-Path $a 'git\gitconfig'), (Join-Path $b 'git\gitconfig'))
    }

    It 'puts the repo first for a path read from the repo and the overlays' {
        New-File (Join-Path $repo 'powershell\tools.psd1')
        New-File (Join-Path $b 'powershell\tools.psd1')

        Get-OverlaySource -Set $set -Path 'powershell/tools.psd1' |
            Should -Be @((Join-Path $repo 'powershell\tools.psd1'), (Join-Path $b 'powershell\tools.psd1'))
    }

    It 'refuses a path not in the table' {
        { Get-OverlaySource -Set $set -Path 'not/a/rule' } | Should -Throw '*not/a/rule*'
    }

    It 'refuses a directory of entries, which has no sources of its own' {
        { Get-OverlaySource -Set $set -Path 'ai/skills/*/' } | Should -Throw '*ai/skills*'
    }
}

Describe 'Get-OverlayEntry' {

    It 'lists each entry in overlay order, an earlier overlay keeping a name without case, a claimant before them' {
        $repo = New-WorkDir; $a = New-WorkDir; $b = New-WorkDir
        foreach ($dir in "$a\ai\skills\alpha", "$a\ai\skills\own", "$a\ai\skills\shared", "$b\ai\skills\Shared", "$repo\ai\skills\own") {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        New-File "$a\ai\skills\README.md"
        $set = Get-Overlays -RepoPath $repo -Overlays $a, $b

        $entries = Get-OverlayEntry -Set $set -Path 'ai/skills/*/' -ClaimedBy "$repo\ai\skills" |
            ForEach-Object { "$($_.Name)|$($_.Path)|$($_.ClashesWith)" }

        $entries | Should -Be @(
            "alpha|$a\ai\skills\alpha|"
            "own|$a\ai\skills\own|$repo\ai\skills\own"
            "shared|$a\ai\skills\shared|"
            "Shared|$b\ai\skills\Shared|$a\ai\skills\shared"
        )
    }

    It 'matches only the files a pattern of files names, by the same first-wins rule' {
        $repo = New-WorkDir; $a = New-WorkDir; $b = New-WorkDir
        New-File "$a\ai\rules\style.md"
        New-File "$a\ai\rules\notes.txt"
        New-Item -ItemType Directory -Path "$a\ai\rules\folder.md" | Out-Null
        New-File "$b\ai\rules\Style.md"
        New-File "$b\ai\rules\team.md"
        New-File "$repo\ai\rules\team.md"
        $set = Get-Overlays -RepoPath $repo -Overlays $a, $b

        $entries = Get-OverlayEntry -Set $set -Path 'ai/rules/*.md' -ClaimedBy "$repo\ai\rules" |
            ForEach-Object { "$($_.Name)|$($_.Path)|$($_.ClashesWith)" }

        $entries | Should -Be @(
            "style.md|$a\ai\rules\style.md|"
            "Style.md|$b\ai\rules\Style.md|$a\ai\rules\style.md"
            "team.md|$b\ai\rules\team.md|$repo\ai\rules\team.md"
        )
    }
}

Describe 'Get-MergedSkillRegistry' {

    BeforeEach { $repo = New-WorkDir; $overlay = New-WorkDir }

    It 'merges the skills of every registry' {
        New-Registry $repo 'alpha'
        New-Registry $overlay 'beta'

        $skills = @(Get-MergedSkillRegistry -Path "$repo\ai\secrets\registry.psd1", "$overlay\ai\secrets\registry.psd1")

        $skills.Id | Should -Be @('alpha', 'beta')
    }

    It 'reads each skill''s secrets from beside the registry that registered it' {
        New-Registry $repo 'alpha'
        New-Registry $overlay 'beta'

        $beta = Get-MergedSkillRegistry -Path "$repo\ai\secrets\registry.psd1", "$overlay\ai\secrets\registry.psd1" | Where-Object Id -eq 'beta'

        $beta.SecretsDir | Should -Be (Join-Path $overlay 'ai\secrets\beta')
    }

    It 'fails, naming both registries, when two register the same Id' {
        New-Registry $repo 'alpha'
        New-Registry $overlay 'alpha'

        { Get-MergedSkillRegistry -Path "$repo\ai\secrets\registry.psd1", "$overlay\ai\secrets\registry.psd1" } | Should -Throw "*$repo*$overlay*"
    }
}

Describe 'Get-GitOverlayIncludeContent' {

    It 'includes each fragment, in order, with forward slashes' {
        $a = New-WorkDir; $b = New-WorkDir

        $paths = (Get-GitOverlayIncludeContent -Fragments "$a\git\gitconfig", "$b\git\gitconfig") -split "`n" |
            Where-Object { $_ -match '^\tpath = ' } |
            ForEach-Object { $_ -replace '^\tpath = ', '' }

        $paths | Should -Be @("$($a -replace '\\', '/')/git/gitconfig", "$($b -replace '\\', '/')/git/gitconfig")
    }

    It 'includes nothing when there are no fragments' {
        (Get-GitOverlayIncludeContent) | Should -Not -Match '\[include\]'
    }
}

Describe 'Update-GitOverlayInclude' {

    BeforeEach {
        $work = New-WorkDir
        $fragment = Join-Path (New-WorkDir) 'git\gitconfig'
        $path = Join-Path $work '.gitconfig-overlays'
    }

    It 'writes the file when it is missing' {
        Update-GitOverlayInclude -Fragments $fragment -Path $path | Should -Be 'Written'
        [IO.File]::ReadAllText($path) | Should -Be (Get-GitOverlayIncludeContent -Fragments $fragment)
    }

    It 'writes it without a byte-order mark' {
        Update-GitOverlayInclude -Fragments $fragment -Path $path | Out-Null
        [IO.File]::ReadAllBytes($path)[0] | Should -Be ([byte][char]'#')
    }

    It 'leaves a current file alone and says so' {
        Update-GitOverlayInclude -Fragments $fragment -Path $path | Out-Null
        Update-GitOverlayInclude -Fragments $fragment -Path $path | Should -Be 'AlreadyCorrect'
    }

    It 'rewrites a file the fragments no longer match' {
        Set-Content -LiteralPath $path -Value 'stale'
        Update-GitOverlayInclude -Fragments $fragment -Path $path | Should -Be 'Written'
    }

    It 'with -Check reports and changes nothing' {
        Update-GitOverlayInclude -Fragments $fragment -Path $path -Check | Should -Be 'WouldWrite'
        Test-Path -LiteralPath $path | Should -BeFalse
    }
}

Describe 'New-MachineLocalFile' {

    BeforeEach {
        $work = New-WorkDir
        $local = Join-Path $work 'machine.local.psd1'
        $example = Join-Path (Split-Path $PSScriptRoot -Parent) 'ai\secrets\machine.local.psd1.example'
    }

    It 'searches the folder the checkouts are in, not the example''s' {
        New-MachineLocalFile -ExamplePath $example -LocalPath $local -SearchRoot 'D:\git'

        (Import-PowerShellDataFile $local).SearchRoots | Should -Be @('D:\git')
    }

    It 'keeps the rest of the example' {
        New-MachineLocalFile -ExamplePath $example -LocalPath $local -SearchRoot 'D:\git'

        [IO.File]::ReadAllText($local) | Should -Match 'OptionalTools = @\(\)'
    }

    It 'refuses an example whose SearchRoots it cannot recognise rather than guessing' {
        $odd = Join-Path $work 'odd.example'
        [IO.File]::WriteAllText($odd, "@{`n    SearchRoots = @(`n        # where checkouts live`n        'C:\source'`n    )`n}`n")

        { New-MachineLocalFile -ExamplePath $odd -LocalPath $local -SearchRoot 'D:\git' } | Should -Throw '*SearchRoots*'
    }
}

Describe 'Set-OverlayListInFile' {

    BeforeEach {
        $work = New-WorkDir
        $local = Join-Path $work 'machine.local.psd1'
    }

    It 'adds an Overlays entry to a file without one, keeping the rest' {
        [IO.File]::WriteAllText($local, "@{`n    # where checkouts live`n    SearchRoots = @('C:\source')`n}`n")

        Set-OverlayListInFile -LocalPath $local -Overlays 'D:\p\personal', 'D:\p\work'

        $data = Import-PowerShellDataFile $local
        $data.Overlays | Should -Be @('D:\p\personal', 'D:\p\work')
        $data.SearchRoots | Should -Be @('C:\source')
        [IO.File]::ReadAllText($local) | Should -Match '# where checkouts live'
    }

    It 'replaces an empty entry' {
        [IO.File]::WriteAllText($local, "@{`n    SearchRoots = @('C:\source')`n    Overlays = @()`n}`n")

        Set-OverlayListInFile -LocalPath $local -Overlays 'D:\p\personal'

        (Import-PowerShellDataFile $local).Overlays | Should -Be @('D:\p\personal')
    }

    It 'replaces a multi-line entry' {
        [IO.File]::WriteAllText($local, "@{`n    Overlays = @(`n        'D:\old\one',`n        'D:\old\two'`n    )`n    SearchRoots = @('C:\source')`n}`n")

        Set-OverlayListInFile -LocalPath $local -Overlays 'D:\p\personal'

        $data = Import-PowerShellDataFile $local
        $data.Overlays | Should -Be @('D:\p\personal')
        $data.SearchRoots | Should -Be @('C:\source')
    }

    It 'writes an entry the install.sh reader can parse: one quoted path per line' {
        [IO.File]::WriteAllText($local, "@{ SearchRoots = @('C:\source') }")

        Set-OverlayListInFile -LocalPath $local -Overlays 'D:\p\personal', 'D:\p\work'

        ([IO.File]::ReadAllText($local) -split "`n" | Where-Object { $_ -match "^\s+'D:" }).Count | Should -Be 2
    }

    It 'refuses an Overlays entry it cannot recognise rather than guessing' {
        [IO.File]::WriteAllText($local, "@{`n    Overlays = @(`n        # personal first`n        'D:\p\personal'`n    )`n}`n")

        { Set-OverlayListInFile -LocalPath $local -Overlays 'D:\x' } | Should -Throw '*edit it by hand*'
    }
}
