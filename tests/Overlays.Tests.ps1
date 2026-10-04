# The overlay rules deploy-secrets.ps1 and setup.ps1 share (hugoforte/dotfiles#26): which
# overlays a machine lists, how skill registries merge, which source a single-target file comes
# from, and what ~/.gitconfig-overlays includes. Everything happens under TestDrive:.

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

Describe 'Get-OverlayList' {

    BeforeEach { $work = New-WorkDir }

    It 'is empty when the machine has no machine.local.psd1' {
        @(Get-OverlayList -LocalPath (Join-Path $work 'machine.local.psd1')).Count | Should -Be 0
    }

    It 'is empty when machine.local.psd1 lists no overlays' {
        $local = Join-Path $work 'machine.local.psd1'
        New-File $local "@{ SearchRoots = @('C:\source') }"

        @(Get-OverlayList -LocalPath $local).Count | Should -Be 0
    }

    It 'returns the listed overlays in order' {
        $a = New-WorkDir; $b = New-WorkDir
        $local = Join-Path $work 'machine.local.psd1'
        New-File $local "@{ Overlays = @('$a', '$b') }"

        Get-OverlayList -LocalPath $local | Should -Be @($a, $b)
    }

    It 'fails, naming the path, when a listed overlay does not exist' {
        $missing = Join-Path $work 'no-such-overlay'
        $local = Join-Path $work 'machine.local.psd1'
        New-File $local "@{ Overlays = @('$missing') }"

        { Get-OverlayList -LocalPath $local } | Should -Throw "*$missing*"
    }
}

Describe 'Get-MergedSkillRegistry' {

    BeforeEach { $repo = New-WorkDir; $overlay = New-WorkDir }

    It 'merges the skills of every root' {
        New-Registry $repo 'alpha'
        New-Registry $overlay 'beta'

        $skills = @(Get-MergedSkillRegistry -Roots $repo, $overlay)

        $skills.Id | Should -Be @('alpha', 'beta')
    }

    It 'reads each skill''s secrets from the root that registered it' {
        New-Registry $repo 'alpha'
        New-Registry $overlay 'beta'

        $beta = Get-MergedSkillRegistry -Roots $repo, $overlay | Where-Object Id -eq 'beta'

        $beta.SecretsDir | Should -Be (Join-Path $overlay 'ai\secrets\beta')
    }

    It 'tolerates a root with no registry' {
        New-Registry $overlay 'beta'

        @(Get-MergedSkillRegistry -Roots $repo, $overlay).Id | Should -Be @('beta')
    }

    It 'fails, naming both registries, when two roots register the same Id' {
        New-Registry $repo 'alpha'
        New-Registry $overlay 'alpha'

        { Get-MergedSkillRegistry -Roots $repo, $overlay } | Should -Throw "*$repo*$overlay*"
    }
}

Describe 'Find-OverlayFile' {

    BeforeEach { $repo = New-WorkDir; $overlay = New-WorkDir }

    It 'is null when no root provides the file' {
        Find-OverlayFile -Roots $repo, $overlay -RelativePath 'aws\config' | Should -BeNullOrEmpty
    }

    It 'returns the one root that provides it' {
        New-File (Join-Path $overlay 'aws\config')

        Find-OverlayFile -Roots $repo, $overlay -RelativePath 'aws\config' |
            Should -Be (Join-Path $overlay 'aws\config')
    }

    It 'fails, naming both, when two roots provide it' {
        New-File (Join-Path $repo 'aws\config')
        New-File (Join-Path $overlay 'aws\config')

        { Find-OverlayFile -Roots $repo, $overlay -RelativePath 'aws\config' } | Should -Throw "*$repo*$overlay*"
    }
}

Describe 'Get-GitOverlayIncludeContent' {

    It 'includes only the overlays that ship git/gitconfig, in order, with forward slashes' {
        $a = New-WorkDir; $none = New-WorkDir; $b = New-WorkDir
        New-File (Join-Path $a 'git\gitconfig')
        New-File (Join-Path $b 'git\gitconfig')

        $paths = (Get-GitOverlayIncludeContent -Overlays $a, $none, $b) -split "`n" |
            Where-Object { $_ -match '^\tpath = ' } |
            ForEach-Object { $_ -replace '^\tpath = ', '' }

        $paths | Should -Be @("$($a -replace '\\', '/')/git/gitconfig", "$($b -replace '\\', '/')/git/gitconfig")
    }

    It 'includes nothing when there are no overlays' {
        (Get-GitOverlayIncludeContent) | Should -Not -Match '\[include\]'
    }
}

Describe 'Update-GitOverlayInclude' {

    BeforeEach {
        $work = New-WorkDir
        $overlay = New-WorkDir
        New-File (Join-Path $overlay 'git\gitconfig')
        $path = Join-Path $work '.gitconfig-overlays'
    }

    It 'writes the file when it is missing' {
        Update-GitOverlayInclude -Overlays $overlay -Path $path | Should -Be 'Written'
        [IO.File]::ReadAllText($path) | Should -Be (Get-GitOverlayIncludeContent -Overlays $overlay)
    }

    It 'writes it without a byte-order mark' {
        Update-GitOverlayInclude -Overlays $overlay -Path $path | Out-Null
        [IO.File]::ReadAllBytes($path)[0] | Should -Be ([byte][char]'#')
    }

    It 'leaves a current file alone and says so' {
        Update-GitOverlayInclude -Overlays $overlay -Path $path | Out-Null
        Update-GitOverlayInclude -Overlays $overlay -Path $path | Should -Be 'AlreadyCorrect'
    }

    It 'rewrites a file the overlays no longer match' {
        Set-Content -LiteralPath $path -Value 'stale'
        Update-GitOverlayInclude -Overlays $overlay -Path $path | Should -Be 'Written'
    }

    It 'with -Check reports and changes nothing' {
        Update-GitOverlayInclude -Overlays $overlay -Path $path -Check | Should -Be 'WouldWrite'
        Test-Path -LiteralPath $path | Should -BeFalse
    }
}

Describe 'Get-OverlayRepoRoots' {

    It 'returns a repository once, however many overlays it holds' {
        $repo = New-WorkDir
        git -C $repo init -q
        New-Item -ItemType Directory -Path (Join-Path $repo 'a'), (Join-Path $repo 'b') | Out-Null

        $roots = @(Get-OverlayRepoRoots -Overlays (Join-Path $repo 'a'), (Join-Path $repo 'b'))

        $roots | Should -Be @([IO.Path]::GetFullPath($repo))
    }

    It 'leaves out an overlay that is not in a repository' {
        @(Get-OverlayRepoRoots -Overlays (New-WorkDir)).Count | Should -Be 0
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
