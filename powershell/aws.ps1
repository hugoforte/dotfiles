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

function aws-setup-profile {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $sourceConfigPath = Join-Path $repoRoot "aws\config"
    $awsDir = Join-Path $env:USERPROFILE ".aws"
    $targetConfigPath = Join-Path $awsDir "config"

    if (-not (Test-Path -LiteralPath $sourceConfigPath)) {
        Write-Host "Source AWS config not found at: $sourceConfigPath" -ForegroundColor Red
        return
    }

    if (-not (Test-Path -LiteralPath $awsDir)) {
        New-Item -ItemType Directory -Path $awsDir | Out-Null
        Write-Host "Created AWS directory: $awsDir" -ForegroundColor Green
    }

    if (Test-Path -LiteralPath $targetConfigPath) {
        $sourceContent = Get-Content -LiteralPath $sourceConfigPath -Raw
        $targetContent = Get-Content -LiteralPath $targetConfigPath -Raw

        if ($sourceContent -eq $targetContent) {
            Write-Host "AWS config is already up to date." -ForegroundColor Green
            return
        }

        $backupPath = "$targetConfigPath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item -LiteralPath $targetConfigPath -Destination $backupPath -Force
        Write-Host "Backed up existing AWS config to: $backupPath" -ForegroundColor Yellow
    }

    Copy-Item -LiteralPath $sourceConfigPath -Destination $targetConfigPath -Force
    Write-Host "Copied AWS config from repo to: $targetConfigPath" -ForegroundColor Green
    Write-Host "Run 'aws sso login' to authenticate." -ForegroundColor DarkGray
}

function aws-view-profile {
    $configPath = Join-Path (Join-Path $env:USERPROFILE ".aws") "config"

    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-Host "AWS config file not found at: $configPath" -ForegroundColor Red
        return
    }

    Write-Host "AWS config: $configPath" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Cyan
    Get-Content -LiteralPath $configPath
}

function aws-goto-profile-path {
    $awsDir = Join-Path $env:USERPROFILE ".aws"

    if (-not (Test-Path -LiteralPath $awsDir)) {
        New-Item -ItemType Directory -Path $awsDir | Out-Null
        Write-Host "Created AWS directory: $awsDir" -ForegroundColor Green
    }

    Set-Location -LiteralPath $awsDir
    Write-Host "Changed directory to: $awsDir" -ForegroundColor Green
}

function aws-switch-profile {
    $configPath = "$env:USERPROFILE\.aws\config"
    $credentialsPath = "$env:USERPROFILE\.aws\credentials"

    $profiles = @()

    if (Test-Path $configPath) {
        $profiles += Get-Content $configPath |
            Select-String -Pattern '^\[(profile\s+)?(.+)\]$' |
            ForEach-Object { $_.Matches.Groups[2].Value } |
            Where-Object { $_ -notmatch '^sso-session\s' }
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
