# Register (or remove) a scheduled task that runs sync.ps1 at logon and every few hours.
# The task only pulls and re-links; it never commits or pushes.

param(
    [int]$EveryHours = 4,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$taskName = "Dotfiles Sync"
$syncScript = Join-Path $PSScriptRoot "sync.ps1"

if ($Uninstall) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "[OK] Removed scheduled task '$taskName'" -ForegroundColor Green
    } else {
        Write-Host "Scheduled task '$taskName' not found" -ForegroundColor Yellow
    }
    exit 0
}

if (!(Test-Path $syncScript)) {
    Write-Host "ERROR: $syncScript not found" -ForegroundColor Red
    exit 1
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$syncScript`" -Quiet"

$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$logon.Delay = "PT2M"   # let the network come up first

$repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).Date `
    -RepetitionInterval (New-TimeSpan -Hours $EveryHours) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($logon, $repeat) `
    -Settings $settings -Description "git pull --ff-only the dotfiles repo and re-run ai/install.sh" `
    -Force | Out-Null

Write-Host "[OK] Registered scheduled task '$taskName'" -ForegroundColor Green
Write-Host "    Runs at logon and every $EveryHours hours. Log: $env:LOCALAPPDATA\dotfiles\sync.log" -ForegroundColor DarkGray
Write-Host "    Remove with: .\install-sync-task.ps1 -Uninstall" -ForegroundColor DarkGray
