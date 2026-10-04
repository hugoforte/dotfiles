# Add-PathEntry, the decision behind putting the repo's bin/ on the user PATH. Add-UserPathEntry
# applies it to the real user environment and is not run here.

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell\user-path.ps1')
}

Describe 'Add-PathEntry' {
    It 'appends an entry the list does not have' {
        Add-PathEntry -PathList 'C:\a;C:\b' -Entry 'C:\dotfiles\bin' | Should -Be 'C:\a;C:\b;C:\dotfiles\bin'
    }

    It 'returns nothing when the entry is already there' {
        Add-PathEntry -PathList 'C:\a;C:\dotfiles\bin' -Entry 'C:\dotfiles\bin' | Should -BeNullOrEmpty
    }

    It 'matches an entry whatever its case' {
        Add-PathEntry -PathList 'C:\DOTFILES\Bin' -Entry 'C:\dotfiles\bin' | Should -BeNullOrEmpty
    }

    It 'matches an entry written with a trailing backslash' {
        Add-PathEntry -PathList 'C:\dotfiles\bin\' -Entry 'C:\dotfiles\bin' | Should -BeNullOrEmpty
    }

    It 'matches an entry written with a %VAR% reference' {
        $env:DOTFILES_TEST_HOME = 'C:\Users\me'
        try {
            Add-PathEntry -PathList '%DOTFILES_TEST_HOME%\dotfiles\bin' -Entry 'C:\Users\me\dotfiles\bin' | Should -BeNullOrEmpty
        } finally {
            Remove-Item Env:DOTFILES_TEST_HOME
        }
    }

    It 'keeps %VAR% references unexpanded in the list it returns' {
        Add-PathEntry -PathList '%USERPROFILE%\a' -Entry 'C:\b' | Should -Be '%USERPROFILE%\a;C:\b'
    }

    It 'drops empty entries rather than carrying them forward' {
        Add-PathEntry -PathList 'C:\a;;C:\b;' -Entry 'C:\c' | Should -Be 'C:\a;C:\b;C:\c'
    }

    It 'starts a list when there is no user PATH yet' {
        Add-PathEntry -PathList $null -Entry 'C:\dotfiles\bin' | Should -Be 'C:\dotfiles\bin'
    }
}
