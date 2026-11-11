# powershell/github-release.ps1: fetching a github-release entry's installer, anonymously for a
# public repo and through the signed-in gh for a private one. GitHub and gh are mocks
# (Invoke-RestMethod, Invoke-WebRequest and Invoke-Native), so no request is made and gh is never
# run; a "download" writes a file under TestDrive:.

BeforeAll {
    $powershell = Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell'
    . (Join-Path $powershell 'native.ps1')
    . (Join-Path $powershell 'tool-selection.ps1')
    . (Join-Path $powershell 'github-release.ps1')

    # What Invoke-RestMethod throws for an HTTP error: an exception carrying the response, whose
    # StatusCode 5.1 and 7 both expose.
    function New-HttpError {
        param([int]$Status)
        $exception = [Exception]::new("Response status code does not indicate success: $Status.")
        $exception | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = [Net.HttpStatusCode]$Status })
        return $exception
    }

    # What Invoke-Native returns. StdOut is Output unless the command also wrote to stderr.
    function New-NativeResult {
        param([object]$ExitCode, [string]$Output = '', [string]$StdOut = $Output)
        return [pscustomobject]@{ Ok = ($ExitCode -eq 0); ExitCode = $ExitCode; Output = $Output; StdOut = $StdOut }
    }

    # The value a native command was given for a flag: the argument after it, wherever it stands.
    function Get-ArgumentAfter {
        param([object[]]$Arguments, [string]$Flag)
        $index = [array]::IndexOf($Arguments, $Flag)
        if ($index -lt 0) { return $null }
        return $Arguments[$index + 1]
    }

    $setup = 'App-Setup_1.2.0_x64.exe'
    $assets = @(
        @{ name = 'latest.json'; browser_download_url = 'https://example/latest.json' }
        @{ name = $setup; browser_download_url = "https://example/$setup" }
    )
    $ghRelease = @{ tagName = 'v1.2.0'; assets = @(@{ name = 'latest.json' }, @{ name = $setup }) } | ConvertTo-Json -Depth 4
}

Describe 'Get-HttpStatusCode' {

    It 'reads the status of an HTTP error' {
        try { throw (New-HttpError 404) } catch { Get-HttpStatusCode -ErrorRecord $_ | Should -Be 404 }
    }

    It 'is null for a failure that was not an HTTP answer, such as no network' {
        try { throw 'No such host is known.' } catch { Get-HttpStatusCode -ErrorRecord $_ | Should -BeNullOrEmpty }
    }
}

Describe 'Save-GitHubReleaseAsset' {

    BeforeEach {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $dir | Out-Null
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value 'installer' }
    }

    Context 'a public repo' {

        BeforeEach {
            Mock Invoke-RestMethod { [pscustomobject]@{ assets = $assets } }
            Mock Invoke-Native { throw 'gh must not be run for a public repo' }
        }

        It 'downloads the matching asset of the latest release and returns its path' {
            $path = Save-GitHubReleaseAsset -Repo 'example/public-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir

            $path | Should -Be (Join-Path $dir $setup)
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq "https://example/$setup" }
        }

        It 'never runs gh, so a machine without it still installs public entries' {
            Save-GitHubReleaseAsset -Repo 'example/public-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir | Out-Null

            Should -Invoke Invoke-Native -Times 0 -Exactly
        }

        It 'refuses a pattern no asset matches, naming the pattern' {
            { Save-GitHubReleaseAsset -Repo 'example/public-app' -Pattern 'Nothing-*.msi' -Directory $dir } |
                Should -Throw '*Nothing-*.msi*'
        }

        It 'names the repo and removes the partial file when the download fails' {
            Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value 'half'; throw 'connection reset' }

            { Save-GitHubReleaseAsset -Repo 'example/public-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw '*example/public-app*connection reset*'
            Join-Path $dir $setup | Should -Not -Exist
        }
    }

    Context 'GitHub fails some other way than 404' {

        It 'names the repo and does not fall back to gh' {
            Mock Invoke-RestMethod { throw (New-HttpError 500) }
            Mock Invoke-Native { throw 'gh must not be run' }

            { Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw '*example/private-app*500*'
            Should -Invoke Invoke-Native -Times 0 -Exactly
        }

        It 'names the repo when there is no network at all' {
            Mock Invoke-RestMethod { throw 'No such host is known.' }
            Mock Invoke-Native { throw 'gh must not be run' }

            { Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw '*example/private-app*No such host*'
        }
    }

    Context 'a private repo, which GitHub answers 404 without signing in' {

        BeforeEach {
            Mock Invoke-RestMethod { throw (New-HttpError 404) }
        }

        It 'downloads the matching asset through the signed-in gh and returns its path' {
            Mock Invoke-Native { New-NativeResult 0 $ghRelease } -ParameterFilter { $args[1] -eq 'release' -and $args[2] -eq 'view' }
            Mock Invoke-Native {
                Set-Content -LiteralPath (Join-Path $dir $setup) -Value 'installer'
                New-NativeResult 0
            } -ParameterFilter { $args[1] -eq 'release' -and $args[2] -eq 'download' }

            $path = Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir

            $path | Should -Be (Join-Path $dir $setup)
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 'asks gh for the exact asset, from the release it read, into the directory' {
            Mock Invoke-Native { New-NativeResult 0 $ghRelease } -ParameterFilter { $args[2] -eq 'view' }
            Mock Invoke-Native {
                Set-Content -LiteralPath (Join-Path $dir $setup) -Value 'installer'
                New-NativeResult 0
            } -ParameterFilter { $args[2] -eq 'download' }

            Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir | Out-Null

            Should -Invoke Invoke-Native -Times 1 -Exactly -ParameterFilter {
                $args[2] -eq 'download' -and
                $args[3] -eq 'v1.2.0' -and
                (Get-ArgumentAfter $args '--repo') -eq 'example/private-app' -and
                (Get-ArgumentAfter $args '--pattern') -eq $setup -and
                (Get-ArgumentAfter $args '--dir') -eq $dir
            }
        }

        It 'reads the release from what gh wrote to stdout, whatever it logged to stderr (GH_DEBUG)' {
            Mock Invoke-Native {
                New-NativeResult 0 "[git] debug: GET /repos/example/private-app/releases/latest`n$ghRelease" $ghRelease
            } -ParameterFilter { $args[2] -eq 'view' }
            Mock Invoke-Native {
                Set-Content -LiteralPath (Join-Path $dir $setup) -Value 'installer'
                New-NativeResult 0
            } -ParameterFilter { $args[2] -eq 'download' }

            Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir |
                Should -Be (Join-Path $dir $setup)
        }

        It 'refuses, naming the repo and what gh answered, when gh release view does not answer JSON' {
            Mock Invoke-Native { New-NativeResult 0 'Welcome to GitHub CLI!' }

            { Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw '*example/private-app*did not answer JSON*Welcome to GitHub CLI!*'
        }

        It 'refuses, naming the repo and what to do, when gh is not on PATH' {
            Mock Invoke-Native { New-NativeResult $null 'gh is not a program on PATH' }

            { Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw '*example/private-app*gh is not on PATH*gh auth login*'
        }

        It 'refuses, naming the repo and saying what gh said, when gh cannot see it either' {
            Mock Invoke-Native { New-NativeResult 1 'release not found' }

            { Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw '*example/private-app*gh auth login done, with access to example/private-app?*release not found*'
        }

        It 'refuses a pattern no asset of the release matches, naming the pattern' {
            Mock Invoke-Native { New-NativeResult 0 $ghRelease }

            { Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'Nothing-*.msi' -Directory $dir } |
                Should -Throw '*Nothing-*.msi*'
            Should -Invoke Invoke-Native -Times 0 -Exactly -ParameterFilter { $args[2] -eq 'download' }
        }

        It 'refuses, naming the repo and the asset, when the download fails' {
            Mock Invoke-Native { New-NativeResult 0 $ghRelease } -ParameterFilter { $args[2] -eq 'view' }
            Mock Invoke-Native { New-NativeResult 1 'HTTP 502' } -ParameterFilter { $args[2] -eq 'download' }

            { Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw "*$setup*example/private-app*HTTP 502*"
        }

        It 'refuses when gh says it downloaded but the file is not there' {
            Mock Invoke-Native { New-NativeResult 0 $ghRelease } -ParameterFilter { $args[2] -eq 'view' }
            Mock Invoke-Native { New-NativeResult 0 } -ParameterFilter { $args[2] -eq 'download' }

            { Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw '*example/private-app*not there*'
        }
    }
}
