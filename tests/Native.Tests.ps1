# Invoke-Native judges a native command by its exit code, not by whether it wrote to stderr:
# under $ErrorActionPreference = 'Stop', Windows PowerShell 5.1 turns a stderr line into a
# terminating error, which is how sync.ps1 used to die on a git pull that fetched anything.

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell\native.ps1')
}

Describe 'Invoke-Native' {
    BeforeEach { $ErrorActionPreference = 'Stop' }

    It 'is Ok when the command writes to stderr and exits 0' {
        (Invoke-Native cmd /c 'echo From https://example 1>&2').Ok | Should -BeTrue
    }

    It 'keeps what the command wrote to stderr' {
        (Invoke-Native cmd /c 'echo From https://example 1>&2').Output | Should -Be 'From https://example'
    }

    It 'is not Ok when the command exits non-zero' {
        (Invoke-Native cmd /c 'exit 3').Ok | Should -BeFalse
    }

    It 'reports the exit code' {
        (Invoke-Native cmd /c 'exit 3').ExitCode | Should -Be 3
    }

    It 'passes a lone argument whole, as sync.ps1 does with install.sh' {
        (Invoke-Native git --version).Ok | Should -BeTrue
    }

    It 'is not Ok when the command does not exist, whatever ran before it' {
        $null = Invoke-Native cmd /c 'exit 0'
        (Invoke-Native no-such-command-here arg).Ok | Should -BeFalse
    }

    It 'passes the command its own flags, -C included' {
        (Invoke-Native git -C $PSScriptRoot rev-parse --is-inside-work-tree).Output | Should -Be 'true'
    }
}
