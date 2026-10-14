# Register (or remove) a scheduled task that runs `cswap auto` at sign-in, so claude-swap moves
# ~/.claude to another of the accounts it holds before the active one reaches its 5-hour or
# 7-day limit. Part of the claude-swap option in tools.psd1: run it once the accounts are added
# (cswap add). Safe to re-run; it also starts the task, so there is no need to sign in again.

param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$taskName = "Claude Swap Auto"
$logPath = Join-Path $env:LOCALAPPDATA "dotfiles\cswap-auto.log"

# Unregistering a task leaves the copy it started running, so stop that first. Stopping it ends
# the task's powershell.exe but not the cswap it started, which would run on with no loop to
# restart it, so end the processes under the loop too. The loop is the powershell.exe whose
# command line writes to cswap-auto.log.
function Stop-CswapTask {
    if (!(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
        return $false
    }
    $processes = @(Get-CimInstance Win32_Process)
    $tree = @($processes | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*cswap-auto.log*' })
    for ($i = 0; $i -lt $tree.Count; $i++) {
        $tree += @($processes | Where-Object { $_.ParentProcessId -eq $tree[$i].ProcessId })
    }
    Stop-ScheduledTask -TaskName $taskName
    $tree | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    return $true
}

if ($Uninstall) {
    if (Stop-CswapTask) {
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
# Task Scheduler's restart settings only cover a task that fails to start, not a program that
# exits, so the loop restarts cswap auto itself a minute after it stops. --json writes one event
# per line, which is what goes to the log.
New-Item -ItemType Directory -Force (Split-Path $logPath) | Out-Null
$quotedCswap = $cswapPath -replace "'", "''"
$quotedLog = $logPath -replace "'", "''"
$loop = "while (`$true) { & '$quotedCswap' auto --json >> '$quotedLog' 2>&1; Start-Sleep 60 }"
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -Command `"$loop`""

$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# The loop runs until sign-out, so no time limit; on a laptop it must also start and keep running
# on battery, which a scheduled task by default does not.
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

# A re-run replaces the task, so stop the copy already running; the new one starts below.
Stop-CswapTask | Out-Null

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $logon `
    -Settings $settings -Description "cswap auto: switch ~/.claude to another claude-swap account before a usage limit" `
    -Force | Out-Null

Start-ScheduledTask -TaskName $taskName

Write-Host "[OK] Registered and started scheduled task '$taskName'" -ForegroundColor Green
Write-Host "    Runs $cswapPath auto at sign-in. Log: $logPath. Accounts and usage: cswap list" -ForegroundColor DarkGray
Write-Host "    Remove with: .\install-cswap-task.ps1 -Uninstall" -ForegroundColor DarkGray
