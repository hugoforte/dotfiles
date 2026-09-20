# Markdown helper functions.

function md-lint {
    <#
    .SYNOPSIS
    Lint markdown with markdownlint-cli2, falling back to the dotfiles default config.

    .DESCRIPTION
    markdownlint-cli2 reads a config only from the current directory downwards - a config in a
    parent directory or in your home directory is ignored - so there is no way to set defaults
    globally. This passes the dotfiles config with --config, unless the current directory has a
    config of its own, in which case the repo wins and nothing is passed.

    .EXAMPLE
    md-lint                 # every .md under the current directory
    md-lint README.md       # one file
    md-lint --fix           # arguments pass straight through
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    if (-not (Get-Command markdownlint-cli2 -ErrorAction SilentlyContinue)) {
        Write-Host "markdownlint-cli2 not found. Install it with:" -ForegroundColor Red
        Write-Host "  powershell\install-tools.ps1" -ForegroundColor Yellow
        return
    }

    $repoConfigs = @('.markdownlint-cli2.jsonc', '.markdownlint-cli2.yaml', '.markdownlint-cli2.cjs',
                     '.markdownlint.jsonc', '.markdownlint.json', '.markdownlint.yaml', '.markdownlint.yml')
    $hasOwnConfig = $false
    foreach ($candidate in $repoConfigs) {
        if (Test-Path (Join-Path (Get-Location) $candidate)) { $hasOwnConfig = $true; break }
    }

    if (-not $Arguments) { $Arguments = @('**/*.md') }

    if ($hasOwnConfig) {
        & markdownlint-cli2 @Arguments
    } else {
        $defaultConfig = Join-Path $PSScriptRoot "markdownlint.jsonc"
        & markdownlint-cli2 --config $defaultConfig @Arguments
    }
}
