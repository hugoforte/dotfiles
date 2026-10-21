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

        Get-AwsConfigContent -Roots $repo | Should -BeNullOrEmpty
    }

    It 'puts each source in, in the order of the roots' {
        $texo = New-Root $work 'linenmaster' "[profile texo]`nregion = us-east-1`n"
        $kealu = New-Root $work 'kealu' "[sso-session kealu]`nsso_region = us-east-1`n"

        $content = Get-AwsConfigContent -Roots $texo, $kealu

        $content.IndexOf('[profile texo]') | Should -BeLessThan $content.IndexOf('[sso-session kealu]')
    }

    It 'names each source above what it contributed' {
        $kealu = New-Root $work 'kealu' "[sso-session kealu]`n"

        Get-AwsConfigContent -Roots $kealu | Should -Match ([regex]::Escape("# from $(Join-Path $kealu 'aws\config')`n[sso-session kealu]"))
    }

    It 'opens with a header saying the file is generated' {
        $kealu = New-Root $work 'kealu' "[sso-session kealu]`n"

        (Get-AwsConfigContent -Roots $kealu) | Should -BeLike '# Written by dotfiles from 1 aws/config file(s); the next sync replaces any edit made here.*'
    }

    It 'writes LF line endings from a CRLF source' {
        $texo = New-Root $work 'linenmaster' "[profile texo]`r`nregion = us-east-1`r`n"

        Get-AwsConfigContent -Roots $texo | Should -Not -Match "`r"
    }

    It 'keeps a source without a final newline apart from the next' {
        $texo = New-Root $work 'linenmaster' "[profile texo]`nregion = us-east-1"
        $kealu = New-Root $work 'kealu' "[sso-session kealu]`n"

        Get-AwsConfigContent -Roots $texo, $kealu | Should -BeLike "*region = us-east-1`n`n# from*"
    }

    It 'refuses a section two sources both declare, naming both' {
        $texo = New-Root $work 'linenmaster' "[default]`nregion = us-east-1`n"
        $kealu = New-Root $work 'kealu' "[default]`nregion = us-west-2`n"

        { Get-AwsConfigContent -Roots $texo, $kealu } | Should -Throw "*[default]*linenmaster*kealu*"
    }

    It 'treats spacing inside a section name as the same section' {
        $texo = New-Root $work 'linenmaster' "[profile shared]`n"
        $kealu = New-Root $work 'kealu' "[ profile  shared ]`n"

        { Get-AwsConfigContent -Roots $texo, $kealu } | Should -Throw "*[profile shared]*"
    }

    It 'lets profiles of the same name as a session through, since they are different sections' {
        $texo = New-Root $work 'linenmaster' "[profile kealu]`n"
        $kealu = New-Root $work 'kealu' "[sso-session kealu]`n"

        { Get-AwsConfigContent -Roots $texo, $kealu } | Should -Not -Throw
    }
}

Describe 'Set-AwsConfig' {

    BeforeEach {
        $work = New-WorkDir
        $texo = New-Root $work 'linenmaster' "[profile texo]`n"
        $kealu = New-Root $work 'kealu' "[sso-session kealu]`n"
        $dst = Join-Path (Join-Path $work '.aws') 'config'
    }

    It 'writes the merged file when nothing is there' {
        (Set-AwsConfig -Path $dst -Roots $texo, $kealu).Action | Should -Be 'Created'

        [IO.File]::ReadAllText($dst) | Should -Be (Get-AwsConfigContent -Roots $texo, $kealu)
    }

    It 'leaves a current file alone' {
        Set-AwsConfig -Path $dst -Roots $texo, $kealu | Out-Null

        (Set-AwsConfig -Path $dst -Roots $texo, $kealu).Action | Should -Be 'AlreadyCorrect'
    }

    It 'rewrites its own file when an overlay is added' {
        Set-AwsConfig -Path $dst -Roots $texo | Out-Null

        (Set-AwsConfig -Path $dst -Roots $texo, $kealu).Action | Should -Be 'Updated'
    }

    It 'replaces the link setup used to make, without a backup' {
        New-Link -Path $dst -Target (Join-Path $texo 'aws\config')

        $result = Set-AwsConfig -Path $dst -Roots $texo, $kealu

        $result.Action, [bool]$result.BackupPath, [bool](Get-Item -LiteralPath $dst).LinkType | Should -Be 'Created', $false, $false
    }

    It 'leaves the link''s source untouched when it replaces the link' {
        New-Link -Path $dst -Target (Join-Path $texo 'aws\config')

        Set-AwsConfig -Path $dst -Roots $texo, $kealu | Out-Null

        [IO.File]::ReadAllText((Join-Path $texo 'aws\config')) | Should -Be "[profile texo]`n"
    }

    It 'backs up a file it did not write before replacing it' {
        New-Item -ItemType Directory -Path (Split-Path $dst -Parent) | Out-Null
        [IO.File]::WriteAllText($dst, "[profile mine]`n")

        $result = Set-AwsConfig -Path $dst -Roots $texo

        $result.Action, [IO.File]::ReadAllText($result.BackupPath) | Should -Be 'BackedUpAndWritten', "[profile mine]`n"
    }

    It 'backs up its own file once someone has edited the header away' {
        Set-AwsConfig -Path $dst -Roots $texo | Out-Null
        [IO.File]::WriteAllText($dst, "[profile added-by-aws-configure]`n" + [IO.File]::ReadAllText($dst))

        (Set-AwsConfig -Path $dst -Roots $texo).Action | Should -Be 'BackedUpAndWritten'
    }

    It 'writes nothing when two sources declare one section' {
        $clash = New-Root $work 'clash' "[profile texo]`n"

        { Set-AwsConfig -Path $dst -Roots $texo, $clash } | Should -Throw
        Test-Path -LiteralPath $dst | Should -BeFalse
    }

    It 'removes its own file once no source is left' {
        Set-AwsConfig -Path $dst -Roots $texo | Out-Null

        (Set-AwsConfig -Path $dst -Roots @()).Action | Should -Be 'Removed'
        Test-Path -LiteralPath $dst | Should -BeFalse
    }

    It 'removes a link to an aws/config once no source is left' {
        New-Link -Path $dst -Target (Join-Path $texo 'aws\config')

        (Set-AwsConfig -Path $dst -Roots @()).Action | Should -Be 'Removed'
    }

    It 'leaves a file it did not write when no source is left' {
        New-Item -ItemType Directory -Path (Split-Path $dst -Parent) | Out-Null
        [IO.File]::WriteAllText($dst, "[profile mine]`n")

        (Set-AwsConfig -Path $dst -Roots @()).Action | Should -Be 'Missing'
        [IO.File]::ReadAllText($dst) | Should -Be "[profile mine]`n"
    }
}

Describe 'Test-AwsConfig' {

    BeforeEach {
        $work = New-WorkDir
        $texo = New-Root $work 'linenmaster' "[profile texo]`n"
        $dst = Join-Path (Join-Path $work '.aws') 'config'
    }

    It 'reports a current file as correct' {
        Set-AwsConfig -Path $dst -Roots $texo | Out-Null

        (Test-AwsConfig -Path $dst -Roots $texo).Reason | Should -Be 'Correct'
    }

    It 'reports the link setup used to make as not its own' {
        New-Link -Path $dst -Target (Join-Path $texo 'aws\config')

        (Test-AwsConfig -Path $dst -Roots $texo).Reason | Should -Be 'NotOurs'
    }

    It 'reports a file it would remove' {
        Set-AwsConfig -Path $dst -Roots $texo | Out-Null

        (Test-AwsConfig -Path $dst -Roots @()).Reason | Should -Be 'Leftover'
    }

    It 'reports no source and nothing there as correct' {
        (Test-AwsConfig -Path $dst -Roots @()).IsCorrect | Should -BeTrue
    }

    It 'changes nothing' {
        Test-AwsConfig -Path $dst -Roots $texo | Out-Null

        Test-Path -LiteralPath $dst | Should -BeFalse
    }
}
