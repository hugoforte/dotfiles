# powershell/sync.ps1, run as the scheduled task runs it, against a dotfiles clone and an overlay
# repo clone whose origins are bare repos under TestDrive:, so the pulls are real. The steps that
# reach past the fixture (install-tools.ps1, deploy-secrets.ps1, the user PATH) are stubs, and
# USERPROFILE and LOCALAPPDATA point into TestDrive:.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent

    # The exit code decides, not stderr: under ErrorActionPreference Stop, 5.1 turns a line git
    # writes there, such as a line-ending warning, into a terminating error.
    function Invoke-Git {
        $ErrorActionPreference = 'Continue'
        git @args 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git $args failed" }
    }

    # commit <dir> <message>: commit everything in <dir>
    function Save-Commit {
        param([string]$Dir, [string]$Message)
        Invoke-Git -C $Dir add -A
        Invoke-Git -C $Dir -c user.name=t -c user.email=t@example.com commit -q -m $Message
    }

    # A seed committed to a bare origin, and a clone of that origin: what a machine has.
    function New-ClonedRepo {
        param([string]$Seed, [string]$Name)
        Invoke-Git init -q $Seed
        Save-Commit $Seed 'seed'
        $origin = Join-Path $TestDrive "$Name.git"
        Invoke-Git clone -q --bare $Seed $origin
        $clone = Join-Path $TestDrive $Name
        Invoke-Git clone -q $origin $clone
        return $clone
    }
}

Describe 'sync.ps1' {

    BeforeAll {
        $home_ = Join-Path $TestDrive 'home'
        New-Item -ItemType Directory -Path $home_, (Join-Path $home_ 'AppData') | Out-Null

        # The overlay repo: one overlay whose marker file ai/install.sh reports.
        $overlaySeed = Join-Path $TestDrive 'overlay-seed'
        New-Item -ItemType Directory -Path (Join-Path $overlaySeed 'personal') | Out-Null
        Set-Content -LiteralPath (Join-Path $overlaySeed 'personal\marker') -Value 'before'
        $private = New-ClonedRepo $overlaySeed 'private'

        # dotfiles: the real powershell/, with the steps that reach past the fixture stubbed, and an
        # ai/install.sh that writes down the overlay marker it sees.
        $seed = Join-Path $TestDrive 'dotfiles-seed'
        New-Item -ItemType Directory -Path (Join-Path $seed 'ai\secrets'), (Join-Path $seed 'powershell') | Out-Null
        Copy-Item (Join-Path $repoRoot 'powershell\*.ps1') (Join-Path $seed 'powershell')
        Set-Content -LiteralPath (Join-Path $seed 'powershell\install-tools.ps1') -Value '[pscustomobject]@{ Ok = 1 }; exit 0'
        Set-Content -LiteralPath (Join-Path $seed 'powershell\deploy-secrets.ps1') -Value '[pscustomobject]@{ Ok = 1 }; exit 0'
        Set-Content -LiteralPath (Join-Path $seed 'powershell\user-path.ps1') -Value 'function Add-UserPathEntry { param($Directory) "AlreadyPresent" }'
        $seen = Join-Path $TestDrive 'seen.txt'
        $marker = Join-Path $private 'personal\marker'
        [IO.File]::WriteAllText((Join-Path $seed 'ai\install.sh'), "cat '$($marker -replace '\\', '/')' > '$($seen -replace '\\', '/')'`n")
        Set-Content -LiteralPath (Join-Path $seed '.gitignore') -Value '/ai/secrets/machine.local.psd1'
        $dotfiles = New-ClonedRepo $seed 'dotfiles'
        New-Item -ItemType Directory -Path (Join-Path $dotfiles 'ai\secrets') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dotfiles 'ai\secrets\machine.local.psd1') -Value "@{ Overlays = @('$private\personal') }"

        # A change pushed to the overlay repo since this machine last pulled.
        $pusher = Join-Path $TestDrive 'pusher'
        Invoke-Git clone -q (Join-Path $TestDrive 'private.git') $pusher
        Set-Content -LiteralPath (Join-Path $pusher 'personal\marker') -Value 'after'
        Save-Commit $pusher 'change the marker'
        Invoke-Git -C $pusher push -q origin HEAD

        # A rig checkout and a node ahead of the real one, exiting 1 as rig update does whenever its
        # doctor checks report anything.
        $rigRoot = Join-Path $TestDrive 'rig'
        New-Item -ItemType Directory -Path (Join-Path $rigRoot 'bin') | Out-Null
        Set-Content -LiteralPath (Join-Path $rigRoot 'bin\rig.mjs') -Value ''
        $stubs = Join-Path $TestDrive 'stubs'
        New-Item -ItemType Directory -Path $stubs | Out-Null
        $nodeArgs = Join-Path $TestDrive 'node-args.txt'
        $nodeSource = @"
using System;
using System.IO;
static class Program {
    static int Main(string[] args) {
        File.WriteAllText(@"$nodeArgs", string.Join(" ", args));
        char esc = (char)27;
        Console.WriteLine(esc + "[32m+" + esc + "[0m tool: fast-forwarded 1 commit(s)");
        Console.WriteLine("  abc1234 a commit that arrived");
        Console.WriteLine(esc + "[33m!" + esc + "[0m data root other: 2 uncommitted change(s)");
        Console.WriteLine(esc + "[32m+" + esc + "[0m personal: data root /somewhere");
        return 1;
    }
}
"@
        Add-Type -TypeDefinition $nodeSource -OutputAssembly (Join-Path $stubs 'node.exe') -OutputType ConsoleApplication

        $env:RIG_ROOT, $savedRigRoot = $rigRoot, $env:RIG_ROOT
        $env:PATH, $savedPath = "$stubs;$env:PATH", $env:PATH
        $env:USERPROFILE, $savedProfile = $home_, $env:USERPROFILE
        $env:LOCALAPPDATA, $savedAppData = (Join-Path $home_ 'AppData'), $env:LOCALAPPDATA
        try {
            $output = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dotfiles 'powershell\sync.ps1') 2>&1
            $exit = $LASTEXITCODE
        } finally {
            $env:USERPROFILE = $savedProfile
            $env:LOCALAPPDATA = $savedAppData
            $env:PATH = $savedPath
            $env:RIG_ROOT = $savedRigRoot
        }
        $syncLog = Get-Content -LiteralPath (Join-Path $home_ 'AppData\dotfiles\sync.log') -Raw
    }

    It 'succeeds' {
        $exit | Should -Be 0 -Because ($output -join "`n")
    }

    It 'runs ai/install.sh after pulling the overlay repos, so it links what they now supply' {
        (Get-Content -LiteralPath $seen) | Should -Be 'after'
    }

    It 'runs rig update from the checkout, and its doctor findings do not fail the sync' {
        Get-Content -LiteralPath $nodeArgs -Raw | Should -Match 'bin\\rig\.mjs update$'
    }

    It 'logs what happened to the tool and each data root, without the doctor''s findings or colour' {
        $syncLog | Should -Match 'tool: fast-forwarded 1 commit'
        $syncLog | Should -Match 'data root other: 2 uncommitted'
        $syncLog | Should -Not -Match 'personal: data root /somewhere'
        $syncLog | Should -Not -Match ([regex]::Escape([string][char]27))
    }
}
