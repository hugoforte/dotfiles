# Register (or remove) a scheduled task that runs `cswap auto` at sign-in, so claude-swap moves
# ~/.claude to another of the accounts it holds before the active one reaches its 5-hour or
# 7-day limit. Part of the claude-swap option in tools.psd1: run it once the accounts are added
# (cswap add). Safe to re-run; it also starts the task, so there is no need to sign in again.

param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$taskName = "Claude Swap Auto"

if ($Uninstall) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "[OK] Removed scheduled task '$taskName'" -ForegroundColor Green
    } else {
        Write-Host "Scheduled task '$taskName' not found" -ForegroundColor Yellow
    }
    exit 0
}

# By full path, so the task does not depend on uv's bin directory being on the PATH it starts with.
$cswap = Get-Command cswap -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$cswapPath = if ($cswap) { $cswap.Source } else { Join-Path $env:USERPROFILE ".local\bin\cswap.exe" }
if (!(Test-Path -LiteralPath $cswapPath)) {
    Write-Host "ERROR: cswap is not on PATH or at $cswapPath. Add claude-swap to OptionalTools in ai\secrets\machine.local.psd1 and run dotfiles-tools" -ForegroundColor Red
    exit 1
}

# Through a hidden powershell.exe, as the sync task is: cswap is a console program and would
# otherwise keep a console window open for as long as it runs, which is the whole session.
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -Command `"& '$cswapPath' auto`""

$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# cswap auto is a loop that runs until sign-out, so no time limit; on a laptop it must also start
# and keep running on battery, which a scheduled task by default does not.
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $logon `
    -Settings $settings -Description "cswap auto: switch ~/.claude to another claude-swap account before a usage limit" `
    -Force | Out-Null

if ((Get-ScheduledTask -TaskName $taskName).State -ne 'Running') {
    Start-ScheduledTask -TaskName $taskName
}

Write-Host "[OK] Registered and started scheduled task '$taskName'" -ForegroundColor Green
Write-Host "    Runs $cswapPath auto at sign-in. See what it is doing with: cswap list" -ForegroundColor DarkGray
Write-Host "    Remove with: .\install-cswap-task.ps1 -Uninstall" -ForegroundColor DarkGray
