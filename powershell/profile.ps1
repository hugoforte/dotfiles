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

    $index = [int]$selection - 1
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
