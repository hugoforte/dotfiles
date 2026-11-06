# ~/.aws/config is every aws/config among the repo and the overlays, merged into one generated
# file. Everything happens under TestDrive:.

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell\aws-config.ps1')

    function New-WorkDir {
        $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $d | Out-Null
        return $d
    }

    # A root (the repo or an overlay) shipping aws/config with $Content.
    function New-Root {
        # $Content untyped: [string] would turn "no file" ($null) into an empty one.
        param([string]$Work, [string]$Name, $Content)
        $root = Join-Path $Work $Name
        New-Item -ItemType Directory -Path (Join-Path $root 'aws') -Force | Out-Null
        if ($null -ne $Content) { [IO.File]::WriteAllText((Join-Path $root 'aws\config'), $Content) }
        return $root
    }

    # The aws/config of each root, as overlays.ps1's Get-OverlaySource gives them: whether each
    # exists is aws-config.ps1's to check.
    function Sources {
        param([string[]]$Roots)
        return @($Roots | ForEach-Object { Join-Path $_ 'aws\config' })
    }

    # mklink on Windows, as managed-link.ps1 makes links (Developer Mode, unelevated); ln elsewhere.
    function New-Link {
        param([string]$Path, [string]$Target)
        New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
        if ($env:OS -eq 'Windows_NT') { cmd /c mklink "`"$Path`"" "`"$Target`"" | Out-Null } else { ln -s $Target $Path }
    }
}

Describe 'Get-AwsConfigContent' {

    BeforeEach { $work = New-WorkDir }

    It 'is nothing when no root ships aws/config' {
        $repo = New-Root $work 'repo'

        Get-AwsConfigContent -Sources (Sources $repo) | Should -BeNullOrEmpty
    }

    It 'puts each source in, in the order of the roots' {
        $acme = New-Root $work 'acme' "[profile acme]`nregion = us-east-1`n"
        $globex = New-Root $work 'globex' "[sso-session globex]`nsso_region = us-east-1`n"

        $content = Get-AwsConfigContent -Sources (Sources $acme, $globex)

        $content.IndexOf('[profile acme]') | Should -BeLessThan $content.IndexOf('[sso-session globex]')
    }

    It 'names each source above what it contributed' {
        $globex = New-Root $work 'globex' "[sso-session globex]`n"

        Get-AwsConfigContent -Sources (Sources $globex) | Should -Match ([regex]::Escape("# from $(Join-Path $globex 'aws\config')`n[sso-session globex]"))
    }

    It 'opens with a header saying the file is generated' {
        $globex = New-Root $work 'globex' "[sso-session globex]`n"

        (Get-AwsConfigContent -Sources (Sources $globex)) | Should -BeLike '# Written by dotfiles from 1 aws/config file(s); the next sync replaces any edit made here.*'
    }

    It 'writes LF line endings from a CRLF source' {
        $acme = New-Root $work 'acme' "[profile acme]`r`nregion = us-east-1`r`n"

        Get-AwsConfigContent -Sources (Sources $acme) | Should -Not -Match "`r"
    }

    It 'keeps a source without a final newline apart from the next' {
        $acme = New-Root $work 'acme' "[profile acme]`nregion = us-east-1"
        $globex = New-Root $work 'globex' "[sso-session globex]`n"

        Get-AwsConfigContent -Sources (Sources $acme, $globex) | Should -BeLike "*region = us-east-1`n`n# from*"
    }

    It 'refuses a section two sources both declare, naming both' {
        $acme = New-Root $work 'acme' "[default]`nregion = us-east-1`n"
        $globex = New-Root $work 'globex' "[default]`nregion = us-west-2`n"

        { Get-AwsConfigContent -Sources (Sources $acme, $globex) } | Should -Throw "*[default]*acme*globex*"
    }

    It 'treats spacing inside a section name as the same section' {
        $acme = New-Root $work 'acme' "[profile shared]`n"
        $globex = New-Root $work 'globex' "[ profile  shared ]`n"

        { Get-AwsConfigContent -Sources (Sources $acme, $globex) } | Should -Throw "*[profile shared]*"
    }

    It 'lets profiles of the same name as a session through, since they are different sections' {
        $acme = New-Root $work 'acme' "[profile globex]`n"
        $globex = New-Root $work 'globex' "[sso-session globex]`n"

        { Get-AwsConfigContent -Sources (Sources $acme, $globex) } | Should -Not -Throw
    }

    It 'reads a section line as the AWS CLI does, ignoring what follows the bracket' {
        $acme = New-Root $work 'acme' "[profile acme]`n"
        $globex = New-Root $work 'globex' "[profile acme] ; a copy`n"

        { Get-AwsConfigContent -Sources (Sources $acme, $globex) } | Should -Throw "*[profile acme]*"
    }

    It 'treats [default] and [profile default] as the one profile they are to the AWS CLI' {
        $acme = New-Root $work 'acme' "[default]`n"
        $globex = New-Root $work 'globex' "[profile default]`n"

        { Get-AwsConfigContent -Sources (Sources $acme, $globex) } | Should -Throw "*[profile default]*"
    }

    It 'treats a quoted profile name as the name' {
        $acme = New-Root $work 'acme' "[profile acme]`n"
        $globex = New-Root $work 'globex' "[profile `"acme`"]`n"

        { Get-AwsConfigContent -Sources (Sources $acme, $globex) } | Should -Throw "*[profile acme]*"
    }

    It 'lets names that differ only in case through, as the AWS CLI does' {
        $acme = New-Root $work 'acme' "[profile Prod]`n"
        $globex = New-Root $work 'globex' "[profile prod]`n"

        { Get-AwsConfigContent -Sources (Sources $acme, $globex) } | Should -Not -Throw
    }

    It 'puts a root listed twice in once' {
        $acme = New-Root $work 'acme' "[profile acme]`n"

        $content = Get-AwsConfigContent -Sources (Sources $acme, "$acme\")

        ([regex]::Matches($content, '\[profile acme\]')).Count | Should -Be 1
    }
}

Describe 'Set-AwsConfig' {

    BeforeEach {
        $work = New-WorkDir
        $acme = New-Root $work 'acme' "[profile acme]`n"
        $globex = New-Root $work 'globex' "[sso-session globex]`n"
        $dst = Join-Path (Join-Path $work '.aws') 'config'
    }

    It 'writes the merged file when nothing is there' {
        (Set-AwsConfig -Path $dst -Sources (Sources $acme, $globex)).Action | Should -Be 'Created'

        (Get-Content -LiteralPath $dst | Where-Object { $_ -like '`[*' }) | Should -Be '[profile acme]', '[sso-session globex]'
    }

    It 'records a checksum of what follows the header, on its second line' {
        Set-AwsConfig -Path $dst -Sources (Sources $acme) | Out-Null

        (Get-Content -LiteralPath $dst -TotalCount 2)[1] | Should -Match '^# dotfiles-sha256: [0-9a-f]{64}$'
    }

    It 'leaves a current file alone' {
        Set-AwsConfig -Path $dst -Sources (Sources $acme, $globex) | Out-Null

        (Set-AwsConfig -Path $dst -Sources (Sources $acme, $globex)).Action | Should -Be 'AlreadyCorrect'
    }

    It 'rewrites its own file when an overlay is added' {
        Set-AwsConfig -Path $dst -Sources (Sources $acme) | Out-Null

        (Set-AwsConfig -Path $dst -Sources (Sources $acme, $globex)).Action | Should -Be 'Updated'
    }

    It 'replaces the link setup used to make, without a backup' {
        New-Link -Path $dst -Target (Join-Path $acme 'aws\config')

        $result = Set-AwsConfig -Path $dst -Sources (Sources $acme, $globex)

        $result.Action, [bool]$result.BackupPath, [bool](Get-Item -LiteralPath $dst).LinkType | Should -Be 'Created', $false, $false
    }

    It 'leaves the link''s source untouched when it replaces the link' {
        New-Link -Path $dst -Target (Join-Path $acme 'aws\config')

        Set-AwsConfig -Path $dst -Sources (Sources $acme, $globex) | Out-Null

        [IO.File]::ReadAllText((Join-Path $acme 'aws\config')) | Should -Be "[profile acme]`n"
    }

    It 'backs up a file it did not write before replacing it' {
        New-Item -ItemType Directory -Path (Split-Path $dst -Parent) | Out-Null
        [IO.File]::WriteAllText($dst, "[profile mine]`n")

        $result = Set-AwsConfig -Path $dst -Sources (Sources $acme)

        $result.Action, [IO.File]::ReadAllText($result.BackupPath) | Should -Be 'BackedUpAndWritten', "[profile mine]`n"
    }

    It 'backs up its own file once someone has edited the header away' {
        Set-AwsConfig -Path $dst -Sources (Sources $acme) | Out-Null
        [IO.File]::WriteAllText($dst, "[profile added-by-aws-configure]`n" + [IO.File]::ReadAllText($dst))

        (Set-AwsConfig -Path $dst -Sources (Sources $acme)).Action | Should -Be 'BackedUpAndWritten'
    }

    It 'keeps a profile aws configure appended, in a backup, when the sources change' {
        Set-AwsConfig -Path $dst -Sources (Sources $acme) | Out-Null
        [IO.File]::AppendAllText($dst, "`n[profile added-by-aws-configure]`nregion = us-east-1`n")

        $result = Set-AwsConfig -Path $dst -Sources (Sources $acme, $globex)

        $result.Action, ([IO.File]::ReadAllText($result.BackupPath) -match 'added-by-aws-configure') | Should -Be 'BackedUpAndWritten', $true
    }

    It 'keeps a profile aws configure appended, in a backup, when the sources did not change' {
        Set-AwsConfig -Path $dst -Sources (Sources $acme) | Out-Null
        [IO.File]::AppendAllText($dst, "`n[profile added-by-aws-configure]`n")

        (Set-AwsConfig -Path $dst -Sources (Sources $acme)).Action | Should -Be 'BackedUpAndWritten'
    }

    It 'leaves no staged file behind' {
        Set-AwsConfig -Path $dst -Sources (Sources $acme) | Out-Null
        Set-AwsConfig -Path $dst -Sources (Sources $acme, $globex) | Out-Null

        Test-Path -LiteralPath "$dst.dotfiles-new" | Should -BeFalse
    }

    It 'writes nothing when two sources declare one section' {
        $clash = New-Root $work 'clash' "[profile acme]`n"

        { Set-AwsConfig -Path $dst -Sources (Sources $acme, $clash) } | Should -Throw
        Test-Path -LiteralPath $dst | Should -BeFalse
    }

    It 'removes its own file once no source is left' {
        Set-AwsConfig -Path $dst -Sources (Sources $acme) | Out-Null

        (Set-AwsConfig -Path $dst -Sources @()).Action | Should -Be 'Removed'
        Test-Path -LiteralPath $dst | Should -BeFalse
    }

    It 'removes a link left dangling once no source is left' {
        New-Link -Path $dst -Target (Join-Path $acme 'aws\config')
        Remove-Item -LiteralPath (Join-Path $acme 'aws\config')

        (Set-AwsConfig -Path $dst -Sources @()).Action | Should -Be 'Removed'
    }

    It 'leaves a link that still resolves when no source is left, since someone made it' {
        New-Link -Path $dst -Target (Join-Path $acme 'aws\config')

        (Set-AwsConfig -Path $dst -Sources @()).Action | Should -Be 'Missing'
    }

    It 'leaves its own file once edited when no source is left' {
        Set-AwsConfig -Path $dst -Sources (Sources $acme) | Out-Null
        [IO.File]::AppendAllText($dst, "`n[profile mine]`n")

        (Set-AwsConfig -Path $dst -Sources @()).Action | Should -Be 'Missing'
    }

    It 'leaves a file it did not write when no source is left' {
        New-Item -ItemType Directory -Path (Split-Path $dst -Parent) | Out-Null
        [IO.File]::WriteAllText($dst, "[profile mine]`n")

        (Set-AwsConfig -Path $dst -Sources @()).Action | Should -Be 'Missing'
        [IO.File]::ReadAllText($dst) | Should -Be "[profile mine]`n"
    }
}

Describe 'Test-AwsConfig' {

    BeforeEach {
        $work = New-WorkDir
        $acme = New-Root $work 'acme' "[profile acme]`n"
        $dst = Join-Path (Join-Path $work '.aws') 'config'
    }

    It 'reports a current file as correct' {
        Set-AwsConfig -Path $dst -Sources (Sources $acme) | Out-Null

        (Test-AwsConfig -Path $dst -Sources (Sources $acme)).Reason | Should -Be 'Correct'
    }

    It 'reports the link setup used to make as not its own' {
        New-Link -Path $dst -Target (Join-Path $acme 'aws\config')

        (Test-AwsConfig -Path $dst -Sources (Sources $acme)).Reason | Should -Be 'NotOurs'
    }

    It 'reports a file it would remove' {
        Set-AwsConfig -Path $dst -Sources (Sources $acme) | Out-Null

        (Test-AwsConfig -Path $dst -Sources @()).Reason | Should -Be 'Leftover'
    }

    It 'reports no source and nothing there as correct' {
        (Test-AwsConfig -Path $dst -Sources @()).IsCorrect | Should -BeTrue
    }

    It 'changes nothing' {
        Test-AwsConfig -Path $dst -Sources (Sources $acme) | Out-Null

        Test-Path -LiteralPath $dst | Should -BeFalse
    }
}
