# powershell/github-release.ps1: fetching a github-release entry's installer, anonymously for a
# public repo and through the signed-in gh for a private one. GitHub and gh are mocks
# (Invoke-RestMethod, Invoke-WebRequest and Invoke-Native), so no request reaches GitHub and gh is
# never run; a "download" writes a file under TestDrive:. Get-HttpStatusCode alone is also asked of
# a real Invoke-RestMethod against an HttpListener on localhost.

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

    # What 5.1 throws (a WebException) and what 7 throws (an HttpResponseException) differ, and a
    # hand-built exception proves neither, so these ask a real local server.
    Context 'what a real Invoke-RestMethod throws' {

        BeforeAll {
            # An HttpListener on a free localhost port. Throws where the platform will not let this
            # user bind one, such as http.sys on Windows without a URL reservation.
            function New-LocalListener {
                $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
                $probe.Start()
                $port = $probe.LocalEndpoint.Port
                $probe.Stop()
                $listener = [Net.HttpListener]::new()
                $listener.Prefixes.Add("http://localhost:$port/")
                $listener.Start()
                return $listener
            }
        }

        It 'reads <_> from the error' -ForEach 404, 403 {
            $status = $_
            try {
                $listener = New-LocalListener
            } catch [Net.HttpListenerException] {
                Set-ItResult -Skipped -Because "an HttpListener cannot bind localhost on this platform: $($_.Exception.Message)"
                return
            }
            # The answer comes from another runspace, because Invoke-RestMethod blocks this one.
            $server = [powershell]::Create().AddScript({
                param($Listener, $Status)
                $context = $Listener.GetContext()
                $context.Response.StatusCode = $Status
                $context.Response.Close()
            }).AddArgument($listener).AddArgument($status)
            $handle = $server.BeginInvoke()
            try {
                $read = 'no error thrown'
                try {
                    Invoke-RestMethod ($listener.Prefixes | Select-Object -First 1) -UseBasicParsing -TimeoutSec 10 | Out-Null
                } catch {
                    $read = Get-HttpStatusCode -ErrorRecord $_
                }
                $read | Should -Be $status
            } finally {
                # Closing the listener ends a GetContext no request reached.
                $listener.Close()
                $null = $handle.AsyncWaitHandle.WaitOne(5000)
                $server.Dispose()
            }
        }
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

        It 'gives up on the release lookup after 30 seconds, but lets the download take as long as it takes' {
            Save-GitHubReleaseAsset -Repo 'example/public-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir | Out-Null

            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $TimeoutSec -eq 30 }
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { -not $TimeoutSec }
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

        It 'removes the partial file when the download is interrupted, as by Ctrl+C, which no catch sees' {
            Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value 'half'; break interrupted }

            :interrupted foreach ($once in 1) {
                Save-GitHubReleaseAsset -Repo 'example/public-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir
            }
            Join-Path $dir $setup | Should -Not -Exist
        }
    }

    Context 'GitHub refuses or fails the anonymous call some other way than 404' {

        It 'names the repo and does not fall back to gh' {
            Mock Invoke-RestMethod { throw (New-HttpError 500) }
            Mock Invoke-Native { throw 'gh must not be run' }

            { Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw '*example/private-app*500*'
            Should -Invoke Invoke-Native -Times 0 -Exactly
        }

        It 'falls back to the signed-in gh when GitHub rate-limits the anonymous call with <_>' -ForEach 403, 429 {
            $status = $_
            Mock Invoke-RestMethod { throw (New-HttpError $status) }
            Mock Invoke-Native { New-NativeResult 0 $ghRelease } -ParameterFilter { $args[2] -eq 'view' }
            Mock Invoke-Native {
                Set-Content -LiteralPath (Join-Path $dir $setup) -Value 'installer'
                New-NativeResult 0
            } -ParameterFilter { $args[2] -eq 'download' }

            Save-GitHubReleaseAsset -Repo 'example/public-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir |
                Should -Be (Join-Path $dir $setup)
        }

        It 'says it was rate limited with <_> when gh is not on PATH to fall back to' -ForEach 403, 429 {
            $status = $_
            Mock Invoke-RestMethod { throw (New-HttpError $status) }
            Mock Invoke-Native { New-NativeResult $null 'gh is not a program on PATH' }

            { Save-GitHubReleaseAsset -Repo 'example/public-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw "*$status*example/public-app*rate limited*gh is not on PATH*"
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

        It 'refuses, naming the repo, both reasons for the 404 and what to do, when gh is not on PATH' {
            Mock Invoke-Native { New-NativeResult $null 'gh is not a program on PATH' }

            { Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw '*example/private-app*no published release*private repo*gh is not on PATH*gh auth login*open a new shell if GitHub.cli was just installed*'
        }

        It 'says the repo has no published release when gh can see the repo but not a latest release' {
            Mock Invoke-Native { New-NativeResult 1 'release not found' } -ParameterFilter { $args[2] -eq 'view' }
            Mock Invoke-Native { New-NativeResult 0 } -ParameterFilter { $args[1] -eq 'api' }

            { Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw '*gh can see example/private-app but it has no published latest release*release not found*'
            Should -Invoke Invoke-Native -Times 1 -Exactly -ParameterFilter {
                $args[1] -eq 'api' -and $args[2] -eq 'repos/example/private-app' -and $args -contains '--silent'
            }
        }

        It 'says the signed-in account cannot see the repo, and how to fix it, when gh cannot see the repo either' {
            Mock Invoke-Native { New-NativeResult 1 'release not found' } -ParameterFilter { $args[2] -eq 'view' }
            Mock Invoke-Native { New-NativeResult 1 'HTTP 404: Not Found' } -ParameterFilter { $args[1] -eq 'api' }

            { Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw '*the signed-in gh account cannot see example/private-app*gh auth status*gh auth login*gh auth switch*release not found*'
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

        It 'removes the partial file gh leaves when its download fails' {
            Mock Invoke-Native { New-NativeResult 0 $ghRelease } -ParameterFilter { $args[2] -eq 'view' }
            Mock Invoke-Native {
                Set-Content -LiteralPath (Join-Path $dir $setup) -Value 'half'
                New-NativeResult 1 'connection reset'
            } -ParameterFilter { $args[2] -eq 'download' }

            { Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw '*connection reset*'
            Join-Path $dir $setup | Should -Not -Exist
        }

        It 'removes the partial file when the gh download is interrupted, as by Ctrl+C' {
            Mock Invoke-Native { New-NativeResult 0 $ghRelease } -ParameterFilter { $args[2] -eq 'view' }
            Mock Invoke-Native {
                Set-Content -LiteralPath (Join-Path $dir $setup) -Value 'half'
                break interrupted
            } -ParameterFilter { $args[2] -eq 'download' }

            :interrupted foreach ($once in 1) {
                Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir
            }
            Join-Path $dir $setup | Should -Not -Exist
        }

        It 'refuses when gh says it downloaded but the file is not there' {
            Mock Invoke-Native { New-NativeResult 0 $ghRelease } -ParameterFilter { $args[2] -eq 'view' }
            Mock Invoke-Native { New-NativeResult 0 } -ParameterFilter { $args[2] -eq 'download' }

            { Save-GitHubReleaseAsset -Repo 'example/private-app' -Pattern 'App-Setup_*_x64.exe' -Directory $dir } |
                Should -Throw '*example/private-app*not there*'
        }
    }
}
