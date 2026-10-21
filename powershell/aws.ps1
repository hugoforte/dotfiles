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

# Writes ~/.aws/config from every aws/config in this repo and the overlays, the same file setup.ps1
# and the sync write (aws-config.ps1).
function aws-setup-profile {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $targetConfigPath = Join-Path (Join-Path $env:USERPROFILE ".aws") "config"

    # Loaded here, not at file scope: profile.ps1 dot-sources aws.ps1 into every shell, and a
    # checkout without these modules beside it would then error on every shell start. The
    # repo's rule is to dot-source helpers only after a path check (powershell.instructions.md).
    foreach ($module in @("overlays.ps1", "aws-config.ps1")) {
        $modulePath = Join-Path $PSScriptRoot $module
        if (-not (Test-Path -LiteralPath $modulePath)) {
            Write-Host "Cannot write AWS config: $modulePath not found" -ForegroundColor Red
            return
        }
        . $modulePath
    }

    try {
        $overlays = Get-OverlayList -LocalPath (Join-Path $repoRoot "ai\secrets\machine.local.psd1")
        $roots = @($repoRoot) + $overlays
        if (-not (Get-AwsConfigSource -Roots $roots).Count) {
            Write-Host "No aws/config in $repoRoot or any overlay" -ForegroundColor Red
            return
        }
        $result = Set-AwsConfig -Path $targetConfigPath -Roots $roots
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        return
    }

    if ($result.Action -eq "AlreadyCorrect") {
        Write-Host "AWS config is already current: $targetConfigPath" -ForegroundColor Green
        return
    }

    if ($result.BackupPath) {
        Write-Host "Backed up existing AWS config to: $($result.BackupPath)" -ForegroundColor Yellow
    }

    Write-Host "Wrote AWS config: $targetConfigPath, from $((Get-AwsConfigSource -Roots $roots) -join ', ')" -ForegroundColor Green
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
