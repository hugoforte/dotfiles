# AWS Helper Functions

function list-functions {
    Write-Host ""
    Write-Host "=== Available AWS Functions ===" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "aws-whoami" -ForegroundColor Green
    Write-Host "  Display current AWS identity and account information"
    Write-Host ""
    
    Write-Host "aws-profile [ProfileName]" -ForegroundColor Green
    Write-Host "  Switch to a specific AWS profile or display the current one"
    Write-Host "  Example: aws-profile production"
    Write-Host ""
    
    Write-Host "aws-switch-profile" -ForegroundColor Green
    Write-Host "  Interactive menu to browse and switch between AWS profiles"
    Write-Host "  Shows all available profiles from ~/.aws/config and ~/.aws/credentials"
    Write-Host "  Automatically logs in via SSO if session has expired"
    Write-Host ""
    
    Write-Host "list-functions" -ForegroundColor Green
    Write-Host "  Display this help message with all available functions"
    Write-Host ""

    Write-Host "git-list-merged-branches [BranchName] [Location]" -ForegroundColor Green
    Write-Host "  List local branches merged into a target branch (default: develop local)"
    Write-Host "  Examples: git-list-merged-branches, git-list-merged-branches main, git-list-merged-branches main origin"
    Write-Host ""
}

function aws-whoami {
    Write-Host "Current AWS Identity:" -ForegroundColor Cyan
    aws sts get-caller-identity
}

function aws-profile {
    param([string]$ProfileName)

    if ($ProfileName) {
        $env:AWS_PROFILE = $ProfileName
        Write-Host "Switched to AWS profile: $ProfileName" -ForegroundColor Green
        aws sts get-caller-identity
    } else {
        if ($env:AWS_PROFILE) {
            Write-Host "Current profile: $env:AWS_PROFILE" -ForegroundColor Cyan
        } else {
            Write-Host "Using default profile" -ForegroundColor Cyan
        }
    }
}

function aws-switch-profile {
    $configPath = "$env:USERPROFILE\.aws\config"
    $credentialsPath = "$env:USERPROFILE\.aws\credentials"

    $profiles = @()

    if (Test-Path $configPath) {
        $profiles += Get-Content $configPath |
            Select-String -Pattern '^\[(profile\s+)?(.+)\]$' |
            ForEach-Object { $_.Matches.Groups[2].Value }
    }

    if (Test-Path $credentialsPath) {
        $profiles += Get-Content $credentialsPath |
            Select-String -Pattern '^\[(.+)\]$' |
            ForEach-Object { $_.Matches.Groups[1].Value }
    }

    $profiles = $profiles | Select-Object -Unique | Sort-Object

    if ($profiles.Count -eq 0) {
        Write-Host "No AWS profiles found!" -ForegroundColor Red
        return
    }

    Write-Host "`nAvailable AWS Profiles:" -ForegroundColor Cyan
    Write-Host "------------------------" -ForegroundColor Cyan

    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $marker = if ($profiles[$i] -eq $env:AWS_PROFILE) { " (current)" } else { "" }
        Write-Host "  [$($i + 1)] $($profiles[$i])$marker" -ForegroundColor White
    }

    Write-Host "`n  [0] Cancel" -ForegroundColor DarkGray
    Write-Host ""

    $selection = Read-Host "Select profile number"

    if ($selection -eq "0" -or $selection -eq "") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }

    [int]$selectionNumber = 0
    if (-not [int]::TryParse($selection, [ref]$selectionNumber)) {
        Write-Host "Invalid selection. Please enter a number." -ForegroundColor Red
        return
    }

    $index = $selectionNumber - 1
    if ($index -ge 0 -and $index -lt $profiles.Count) {
        $selectedProfile = $profiles[$index]
        $env:AWS_PROFILE = $selectedProfile
        Write-Host "`nSwitched to: $selectedProfile" -ForegroundColor Green
        
        # Try to get caller identity, and if it fails, attempt SSO login
        $identity = aws sts get-caller-identity 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Session expired or not logged in. Logging in via SSO..." -ForegroundColor Yellow
            aws sso login
            if ($LASTEXITCODE -eq 0) {
                Write-Host "`nSuccessfully logged in. Identity:" -ForegroundColor Green
                aws sts get-caller-identity
            } else {
                Write-Host "Failed to log in via SSO." -ForegroundColor Red
            }
        } else {
            Write-Output $identity
        }
    } else {
        Write-Host "Invalid selection." -ForegroundColor Red
    }
}

# Backward-compatible wrapper for users who call the plural form.
function aws-switch-profiles {
    aws-switch-profile
}

function git-list-merged-branches {
    param(
        [string]$BranchName = "develop",
        [string]$Location = "local"
    )

    $gitDir = git rev-parse --git-dir 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Not a git repository." -ForegroundColor Red
        return
    }

    $normalizedLocation = $Location.Trim().ToLower()
    if (-not $normalizedLocation) {
        $normalizedLocation = "local"
    }

    if (-not $BranchName -or -not $BranchName.Trim()) {
        Write-Host "Branch name cannot be empty." -ForegroundColor Red
        return
    }

    $targetRef = ""
    $targetDisplay = ""
    if ($normalizedLocation -eq "local") {
        $targetRef = "refs/heads/$BranchName"
        $targetDisplay = "$BranchName (local)"
    } else {
        $targetRef = "refs/remotes/$normalizedLocation/$BranchName"
        $targetDisplay = "$normalizedLocation/$BranchName"
    }

    git show-ref --verify --quiet $targetRef
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Target branch not found: $targetDisplay" -ForegroundColor Yellow
        return
    }

    $currentBranch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
    $mergedBranches = git branch --format "%(refname:short)" --merged $targetRef |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and $_ -ne $BranchName -and $_ -ne $currentBranch } |
        Select-Object -Unique | Sort-Object

    if ($mergedBranches -isnot [System.Array]) {
        $mergedBranches = @($mergedBranches)
    }

    if (-not $mergedBranches -or $mergedBranches.Count -eq 0) {
        Write-Host "No local branches are merged into $targetDisplay." -ForegroundColor Yellow
        return
    }

    Write-Host "Local branches merged into $targetDisplay:" -ForegroundColor Cyan
    $mergedBranches | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
}
