# Which manifest entries a machine gets (optional tools are opted into per machine, by name, in
# machine.local.psd1 or an overlay's machines/<COMPUTERNAME>.psd1), how the manifests of dotfiles
# and its overlays merge, and the pure parts of the github-release install method: picking the
# installer asset and recognising the installed program. Everything happens under TestDrive:.

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell\tool-selection.ps1')

    function New-LocalFile {
        param([string]$Content)
        $path = Join-Path $TestDrive ("machine-{0}.local.psd1" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        Set-Content -LiteralPath $path -Value $Content
        return $path
    }

    $always = @{ Id = 'jqlang.jq'; Source = 'winget' }
    $app = @{ Id = 'hugoforte/openwhispr'; Source = 'github-release'; Optional = 'openwhispr' }
    $firstRun = @{ Id = 'openwhispr-first-run'; Source = 'manual'; Optional = 'openwhispr' }
    $manifest = @($always, $app, $firstRun)
}

Describe 'Get-OptedInOptionList' {

    It 'is empty when the machine has no machine.local.psd1' {
        @(Get-OptedInOptionList -Path (Join-Path $TestDrive 'absent.psd1')).Count | Should -Be 0
    }

    It 'is empty when machine.local.psd1 opts into nothing' {
        $local = New-LocalFile "@{ Overlays = @() }"

        @(Get-OptedInOptionList -Path $local).Count | Should -Be 0
    }

    It 'returns the options the machine lists' {
        $local = New-LocalFile "@{ OptionalTools = @('openwhispr') }"

        Get-OptedInOptionList -Path $local | Should -Be @('openwhispr')
    }

    It 'takes a single option written as a bare string' {
        $local = New-LocalFile "@{ OptionalTools = 'openwhispr' }"

        @(Get-OptedInOptionList -Path $local) | Should -Be @('openwhispr')
    }

    It 'adds the options of the machine file to those of machine.local.psd1' {
        $local = New-LocalFile "@{ OptionalTools = @('openwhispr') }"
        $machine = New-LocalFile "@{ OptionalTools = @('media-server') }"

        Get-OptedInOptionList -Path $local, $machine | Should -Be @('openwhispr', 'media-server')
    }

    It 'lists an option named in both files once' {
        $local = New-LocalFile "@{ OptionalTools = @('openwhispr') }"
        $machine = New-LocalFile "@{ OptionalTools = @('openwhispr', 'dev') }"

        Get-OptedInOptionList -Path $local, $machine | Should -Be @('openwhispr', 'dev')
    }
}

Describe 'Get-MergedToolManifest' {

    BeforeAll {
        function New-Manifest {
            param([string[]]$Ids)
            $entries = ($Ids | ForEach-Object { "@{ Id = '$_'; Source = 'manual' }" }) -join "`n"
            return New-LocalFile "@{ Tools = @(`n$entries`n) }"
        }
    }

    It 'returns the entries of every manifest, in the order given' {
        $dotfiles = New-Manifest 'jqlang.jq', 'OpenJS.NodeJS'
        $overlay = New-Manifest 'media-backups-setup'

        (Get-MergedToolManifest -Path $dotfiles, $overlay).Id | Should -Be @('jqlang.jq', 'OpenJS.NodeJS', 'media-backups-setup')
    }

    It 'skips a manifest that does not exist, as an overlay that ships none' {
        $dotfiles = New-Manifest 'jqlang.jq'

        (Get-MergedToolManifest -Path $dotfiles, (Join-Path $TestDrive 'absent.psd1')).Id | Should -Be @('jqlang.jq')
    }

    It 'refuses an id declared in two manifests, naming both' {
        $dotfiles = New-Manifest 'jqlang.jq'
        $overlay = New-Manifest 'jqlang.jq'

        { Get-MergedToolManifest -Path $dotfiles, $overlay } | Should -Throw "*$dotfiles*$overlay*"
    }

    It 'refuses an id declared twice in one manifest' {
        $dotfiles = New-Manifest 'jqlang.jq', 'jqlang.jq'

        { Get-MergedToolManifest -Path $dotfiles } | Should -Throw "*'jqlang.jq'*"
    }
}

Describe 'Test-GitHubReleaseEntry' {

    It 'accepts an entry with Asset, InstallArgs and Present' {
        Test-GitHubReleaseEntry -Tool @{ Id = 'o/r'; Source = 'github-release'; Asset = 'x-*.exe'; InstallArgs = @('/S'); Present = 'X *' } |
            Should -BeNullOrEmpty
    }

    It 'names the fields an entry is missing' {
        Test-GitHubReleaseEntry -Tool @{ Id = 'o/r'; Source = 'github-release'; Asset = 'x-*.exe' } |
            Should -Be 'o/r: a github-release entry needs InstallArgs, Present'
    }
}

Describe 'Select-MachineTools' {

    It 'keeps every entry that is not optional' {
        (Select-MachineTools -Tools $manifest -OptedIn @()).Selected.Id | Should -Contain 'jqlang.jq'
    }

    It 'leaves out an option the machine did not opt into' {
        (Select-MachineTools -Tools $manifest -OptedIn @()).Selected.Id | Should -Not -Contain 'hugoforte/openwhispr'
    }

    It 'names an option the machine did not opt into as available' {
        (Select-MachineTools -Tools $manifest -OptedIn @()).Available | Should -Be @('openwhispr')
    }

    It 'brings every entry of an opted-in option, its manual step included' {
        (Select-MachineTools -Tools $manifest -OptedIn @('openwhispr')).Selected.Id |
            Should -Be @('jqlang.jq', 'hugoforte/openwhispr', 'openwhispr-first-run')
    }

    It 'names no option as available once the machine opted into it' {
        @((Select-MachineTools -Tools $manifest -OptedIn @('openwhispr')).Available).Count | Should -Be 0
    }

    It 'names an opted-in option the manifest does not declare, so a typo is not silent' {
        (Select-MachineTools -Tools $manifest -OptedIn @('open-whisper')).Unknown | Should -Be @('open-whisper')
    }
}

Describe 'Select-ReleaseAsset' {

    BeforeAll {
        $assets = @(
            @{ name = 'latest.yml'; browser_download_url = 'https://example/latest.yml' }
            @{ name = 'OpenWhispr-Setup-1.10.2-hf.1.exe.blockmap'; browser_download_url = 'https://example/x.blockmap' }
            @{ name = 'OpenWhispr-Setup-1.10.2-hf.1.exe'; browser_download_url = 'https://example/setup.exe' }
        )
    }

    It 'picks the one asset matching the pattern' {
        (Select-ReleaseAsset -Assets $assets -Pattern 'OpenWhispr-Setup-*.exe').browser_download_url |
            Should -Be 'https://example/setup.exe'
    }

    It 'refuses when no asset matches, naming the pattern' {
        { Select-ReleaseAsset -Assets $assets -Pattern 'Nothing-*.msi' } | Should -Throw '*Nothing-*.msi*'
    }

    It 'refuses when the pattern matches more than one asset' {
        { Select-ReleaseAsset -Assets $assets -Pattern 'OpenWhispr-Setup-*' } | Should -Throw '*more than one*'
    }

    It 'refuses a release with no assets the same way, naming the pattern' {
        { Select-ReleaseAsset -Assets @() -Pattern 'OpenWhispr-Setup-*.exe' } | Should -Throw '*OpenWhispr-Setup-*.exe*'
    }
}

Describe 'Test-ProgramListed' {

    It 'finds a program whose display name matches' {
        Test-ProgramListed -DisplayName 'OpenWhispr*' -Listed @('Git', 'OpenWhispr 1.10.2-hf.1') | Should -BeTrue
    }

    It 'does not find a program that is not listed' {
        Test-ProgramListed -DisplayName 'OpenWhispr*' -Listed @('Git', 'Node.js') | Should -BeFalse
    }

    It 'does not take upstream OpenWhispr for the fork the manifest declares' {
        $entry = (Import-PowerShellDataFile (Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell\tools.psd1')).Tools |
            Where-Object { $_.Id -eq 'hugoforte/openwhispr' }

        Test-ProgramListed -DisplayName $entry.Present -Listed @('OpenWhispr 1.10.2') | Should -BeFalse
    }

    It 'finds the fork the manifest declares once it is installed' {
        $entry = (Import-PowerShellDataFile (Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell\tools.psd1')).Tools |
            Where-Object { $_.Id -eq 'hugoforte/openwhispr' }

        Test-ProgramListed -DisplayName $entry.Present -Listed @('OpenWhispr 1.10.2-hf.1') | Should -BeTrue
    }

    It 'finds nothing on a machine that lists no programs' {
        Test-ProgramListed -DisplayName 'OpenWhispr*' -Listed @() | Should -BeFalse
    }
}
