# Pester 5 suite for powershell/output.ps1, run under Windows PowerShell 5.1.
#
# The seams, one Context each:
#   - the result object, which is plain data a caller can assert on;
#   - reporting with no result open, which sync.ps1 does on purpose;
#   - the closing summary, which must not inflate the counts it summarises;
#   - Quiet, which silences the console without silencing the record;
#   - the script boundary, where Write-Host does not cross and the result does;
#   - Remove-AnsiEscape, the log-file adapter.
#
# Nothing here touches the real machine: the only file written is a child-script fixture under
# TestDrive:, and the only script dot-sourced is output.ps1 itself.

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $OutputScript = Join-Path $RepoRoot 'powershell/output.ps1'
    . $OutputScript

    # output.ps1 keeps the open result in its script scope. This helper is defined in the same
    # scope by the same dot-source, so clearing the variable here is what those functions see.
    function Reset-OpenResult {
        $script:ScriptResult = $null
    }

    # Write-Host writes to the information stream. Merging stream 6 into the success stream is
    # how 5.1 reads that back - and `| Out-String`, which does not, is the defect under test.
    function Get-ConsoleLines {
        param([Parameter(Mandatory)][scriptblock]$Body)
        return @(& $Body 6>&1 | ForEach-Object { [string]$_ })
    }

    # The escape sequences ai/helpers/output.sh actually emits.
    $Esc = [char]27
}

Describe 'output.ps1' {

    BeforeEach {
        Reset-OpenResult
    }

    Context 'The result object' {

        It 'starts every count at zero' {
            $result = New-ScriptResult -Name 'x.ps1'
            "$($result.Ok)/$($result.Changed)/$($result.Warned)/$($result.Todo)/$($result.Errors)" |
                Should -Be '0/0/0/0/0'
        }

        It 'records each outcome under its own count' {
            $result = New-ScriptResult -Name 'x.ps1' -Quiet
            Ok 'one'; Ok 'two'; Change 'three'; Warn 'four'; Todo 'five'; Fail 'six'
            "$($result.Ok)/$($result.Changed)/$($result.Warned)/$($result.Todo)/$($result.Errors)" |
                Should -Be '2/1/1/1/1'
        }

        It 'does not record Say, which is chatter and not an outcome' {
            $result = New-ScriptResult -Name 'x.ps1' -Quiet
            Say 'just talking'
            @($result.Messages).Count | Should -Be 0
        }

        It 'names the script and lists only the counts that are not zero' {
            $result = New-ScriptResult -Name 'install-tools.ps1' -Quiet
            Ok 'git'; Ok 'jq'; Warn 'shellcheck missing'
            Get-ResultSummary $result | Should -Be 'install-tools.ps1: 2 ok, 1 warning(s)'
        }

        It 'summarises a result with nothing on it as nothing to report' {
            $result = New-ScriptResult -Name 'install-tools.ps1' -Quiet
            Get-ResultSummary $result | Should -Be 'install-tools.ps1: nothing to report'
        }

        It 'prefixes each recorded line the way the console printed it' {
            $result = New-ScriptResult -Name 'x.ps1' -Quiet
            Ok 'fine'; Change 'changed'; Warn 'warned'; Todo 'to do'; Fail 'failed'
            (Get-ResultLines $result) -join '|' |
                Should -Be '[OK] fine|[..] changed|[!!] warned|[->] to do|[XX] failed'
        }

        It 'keeps only the kinds a log asks for' {
            $result = New-ScriptResult -Name 'x.ps1' -Quiet
            Ok 'fine'; Change 'changed'; Warn 'warned'; Todo 'to do'; Fail 'failed'
            (Get-ResultLines $result -Kinds Warn, Error, Todo) -join '|' |
                Should -Be '[!!] warned|[->] to do|[XX] failed'
        }
    }

    Context 'Reporting with no result open' {

        # sync.ps1 dot-sources output.ps1 for Get-ResultSummary, Get-ResultLines and
        # Remove-AnsiEscape without opening a result of its own, and must not die for saying so.
        It 'lets Say through, because a reader of results reports none of its own' {
            { Say 'reading someone else''s result' } | Should -Not -Throw
        }

        It 'throws on <Verb>, which is a programming error rather than a reporting one' -TestCases @(
            @{ Verb = 'Ok' }
            @{ Verb = 'Change' }
            @{ Verb = 'Warn' }
            @{ Verb = 'Todo' }
            @{ Verb = 'Fail' }
        ) {
            param($Verb)
            { & $Verb 'an outcome with nowhere to go' } |
                Should -Throw -ExpectedMessage '*No script result is open*'
        }

        It 'throws from Get-ScriptResult and says what to call instead' {
            { Get-ScriptResult } | Should -Throw -ExpectedMessage '*call New-ScriptResult before reporting*'
        }
    }

    Context 'The closing summary does not inflate the counts' {

        # deploy-secrets.ps1's tail: two genuine problems, then summary lines that count them.
        BeforeEach {
            $DeployResult = New-ScriptResult -Name 'deploy-secrets.ps1' -Quiet
            $drift = 0
            $drift++; Warn 'skillA/.secrets.env would be updated'
            $drift++; Warn 'repoB\.claude\skills\x: missing'
            Summary Warn "$drift item(s) would change. Run deploy-secrets.ps1 to apply."
        }

        It 'leaves the count at the number of genuine problems' {
            $DeployResult.Warned | Should -Be 2
        }

        It 'leaves the summary text honest' {
            Get-ResultSummary $DeployResult | Should -Be 'deploy-secrets.ps1: 2 warning(s)'
        }

        It 'gives sync.log two lines, not three' {
            @(Get-ResultLines $DeployResult -Kinds Warn, Error, Todo).Count | Should -Be 2
        }

        It 'leaves the clean path reporting honestly too' {
            $result = New-ScriptResult -Name 'install-tools.ps1' -Quiet
            Ok 'git'; Ok 'jq'
            Summary Ok 'tools up to date'
            Get-ResultSummary $result | Should -Be 'install-tools.ps1: 2 ok'
        }
    }

    Context 'Quiet silences the console, not the record' {

        It 'shows every outcome when Quiet is off' {
            $null = New-ScriptResult -Name 'q.ps1'
            $lines = Get-ConsoleLines { Ok 'a'; Change 'b'; Warn 'c'; Todo 'd'; Fail 'e'; Say 'f' }
            $lines -join '|' | Should -Be '[OK] a|[..] b|[!!] c|[->] d|[XX] e|f'
        }

        It 'keeps only the problems on the console when Quiet is on' {
            $null = New-ScriptResult -Name 'q.ps1' -Quiet
            $lines = Get-ConsoleLines { Ok 'a'; Change 'b'; Warn 'c'; Todo 'd'; Fail 'e'; Say 'f'; Summary Ok 'g' }
            $lines -join '|' | Should -Be '[!!] c|[XX] e'
        }

        It 'records what it did not print' {
            $result = New-ScriptResult -Name 'q.ps1' -Quiet
            $null = Get-ConsoleLines { Ok 'hidden'; Warn 'shown' }
            "$($result.Ok)/$($result.Warned)" | Should -Be '1/1'
        }
    }

    Context 'Crossing the script boundary' {

        BeforeAll {
            # The fixture a caller invokes: written at run time so no stray script is committed.
            $ChildScript = Join-Path $TestDrive 'child-under-test.ps1'
            Set-Content -LiteralPath $ChildScript -Encoding UTF8 -Value @'
param(
    [Parameter(Mandatory)][string]$OutputScript,
    [switch]$Quiet,
    [switch]$PassThru,
    [int]$ExitCode = 0
)
$ErrorActionPreference = 'Stop'
. $OutputScript
$result = New-ScriptResult -Name 'child.ps1' -Quiet:$Quiet -PassThru:$PassThru
Say 'chatter that is not an outcome' Cyan
Ok 'a thing that was fine'
Ok 'another thing that was fine'
Change 'a thing that changed'
Warn 'a thing that warned'
Todo 'a thing for you to do'
Fail 'a thing that failed'
Exit-WithResult $result $ExitCode
'@

            $Crossed = & $ChildScript -OutputScript $OutputScript -Quiet -PassThru -ExitCode 3
            $CrossedExitCode = $LASTEXITCODE
        }

        It 'hands back one result, not an array of them' {
            $Crossed -is [array] | Should -BeFalse
        }

        It 'hands back plain data the caller can read' {
            $Crossed.GetType().FullName | Should -Be 'System.Management.Automation.PSCustomObject'
        }

        It 'lets the exit code survive Exit-WithResult' {
            $CrossedExitCode | Should -Be 3
        }

        It 'carries the counts across intact' {
            "$($Crossed.Ok)/$($Crossed.Changed)/$($Crossed.Warned)/$($Crossed.Todo)/$($Crossed.Errors)" |
                Should -Be '2/1/1/1/1'
        }

        It 'can be summarised by the caller, which opened no result of its own' {
            Get-ResultSummary $Crossed |
                Should -Be 'child.ps1: 2 ok, 1 changed, 1 warning(s), 1 to do, 1 error(s)'
        }

        It 'can be filtered by the caller for the lines sync.log wants' {
            (Get-ResultLines $Crossed -Kinds Warn, Error, Todo) -join '|' |
                Should -Be '[!!] a thing that warned|[->] a thing for you to do|[XX] a thing that failed'
        }

        It 'sends nothing across when the caller did not ask for it' {
            $quiet = & $ChildScript -OutputScript $OutputScript -Quiet -ExitCode 0
            $quiet | Should -BeNullOrEmpty
        }

        # The defect the result object exists to fix. Write-Host writes to the information
        # stream, which Windows PowerShell 5.1 does not capture through a pipeline: a caller
        # that scrapes a child script's console gets an empty string, however much it printed.
        It 'gives a caller scraping the console nothing at all' {
            $captured = & $ChildScript -OutputScript $OutputScript -ExitCode 0 | Out-String
            "$captured".Length | Should -Be 0
        }
    }

    Context 'Remove-AnsiEscape' {

        It 'strips the colour codes ai/helpers/output.sh emits' {
            $coloured = "$Esc[0;32m[OK] green$Esc[0m and $Esc[0;31m[XX] red$Esc[0m"
            Remove-AnsiEscape $coloured | Should -Be '[OK] green and [XX] red'
        }

        It 'leaves text that was never coloured alone' {
            Remove-AnsiEscape '[OK] plain text' | Should -Be '[OK] plain text'
        }

        It 'passes an empty string straight back' {
            Remove-AnsiEscape '' | Should -Be ''
        }
    }
}
