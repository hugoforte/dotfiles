# Fetches a github-release entry's installer: the one asset of the repo's latest release whose
# name matches the entry's Asset pattern. Dot-sourced by install-tools.ps1, after native.ps1 and
# tool-selection.ps1.
#
# The release is asked for without signing in first, so a public repo needs no gh. GitHub answers
# 404 for a private repo it will not show an anonymous caller (and for a public repo with no
# release), and 403 or 429 when it rate-limits anonymous calls; only then is the signed-in gh asked
# instead. The gh-auth manual step is what makes a private repo installable.

# The HTTP status of a failed Invoke-RestMethod or Invoke-WebRequest, or $null when the failure
# was not an HTTP answer. 5.1 throws a WebException and 7 an HttpResponseException; both carry
# the response, whose StatusCode reads as the number.
function Get-HttpStatusCode {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    $response = $ErrorRecord.Exception.Response
    if ($null -eq $response -or $null -eq $response.StatusCode) { return $null }
    return [int]$response.StatusCode
}

# Downloads the asset of Repo's latest release matching Pattern (a -like wildcard) into Directory,
# and returns the file's full path. Anonymously when GitHub shows the release to anyone; through
# the signed-in gh when it answers 404, 403 or 429. Throws, naming the repo, when neither can fetch
# it.
function Save-GitHubReleaseAsset {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Directory
    )

    $release = $null
    $refusal = $null
    try {
        $release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing
    } catch {
        $status = Get-HttpStatusCode -ErrorRecord $_
        if ($status -eq 404) {
            $refusal = "GitHub answers 404 for the latest release of $Repo without signing in: it has no published release, or it is a private repo"
        } elseif ($status -eq 403 -or $status -eq 429) {
            $refusal = "GitHub answers $status for the latest release of $Repo without signing in: rate limited"
        } else {
            throw "could not read the latest release of $Repo from GitHub: $($_.Exception.Message)"
        }
    }

    if ($refusal) {
        return (Save-GitHubReleaseAssetSignedIn -Repo $Repo -Pattern $Pattern -Directory $Directory -Refusal $refusal)
    }

    $asset = Select-ReleaseAsset -Assets @($release.assets) -Pattern $Pattern
    $path = Join-Path $Directory $asset.name
    try {
        Invoke-WebRequest $asset.browser_download_url -OutFile $path -UseBasicParsing
    } catch {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        throw "could not download $($asset.name) from the latest release of $Repo`: $($_.Exception.Message)"
    }
    return $path
}

# The signed-in half of Save-GitHubReleaseAsset, for a repo GitHub does not show, or will not show
# yet, without signing in; Refusal says how GitHub answered the anonymous call. The asset is chosen
# by Select-ReleaseAsset, as the anonymous path chooses it, then fetched by its exact name from the
# same release.
function Save-GitHubReleaseAssetSignedIn {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Refusal
    )

    $view = Invoke-Native gh release view --repo $Repo --json 'tagName,assets'
    if ($null -eq $view.ExitCode) {
        throw "$Refusal. gh is not on PATH to ask signed in: install GitHub.cli and run gh auth login, or open a new shell if GitHub.cli was just installed"
    }
    if (-not $view.Ok) {
        # gh release view fails alike for a repo with no release, a repo the signed-in account
        # cannot see and a token GitHub refuses; whether gh can read the repo itself tells the first
        # from the other two.
        $repoCheck = Invoke-Native gh api "repos/$Repo" --silent
        if ($repoCheck.Ok) {
            throw "$Refusal. gh can see $Repo but it has no published latest release: $($view.Output)"
        }
        throw "$Refusal. The signed-in gh account cannot see $Repo`: check gh auth status, then gh auth login or gh auth switch. gh said: $($view.Output)"
    }
    # StdOut alone: with GH_DEBUG set, gh logs to stderr on a run that succeeds.
    try {
        $release = $view.StdOut | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "gh release view --repo $Repo did not answer JSON: $($view.Output)"
    }
    if ($null -eq $release) {
        throw "gh release view --repo $Repo did not answer JSON, only: $($view.Output)"
    }

    $asset = Select-ReleaseAsset -Assets @($release.assets) -Pattern $Pattern
    $download = Invoke-Native gh release download $release.tagName --repo $Repo --pattern $asset.name --dir $Directory --clobber
    if (-not $download.Ok) {
        Remove-Item -LiteralPath (Join-Path $Directory $asset.name) -Force -ErrorAction SilentlyContinue
        throw "gh release download of $($asset.name) from $Repo $($release.tagName) failed: $($download.Output)"
    }
    $path = Join-Path $Directory $asset.name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "gh release download of $($asset.name) from $Repo $($release.tagName) reported success, but $path is not there"
    }
    return $path
}
