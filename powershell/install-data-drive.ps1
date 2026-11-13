# Moves the profile's big stores to the machine's data drive and points their tools there; see
# data-drive.ps1 for which stores and how.
#
#   install-data-drive.ps1           move what is still on the system drive
#   install-data-drive.ps1 -Check    report only; exit 1 if anything would change
#   -DataDrive D:                    use this drive instead of the machine's files' DataDrive
#
# A machine with no DataDrive in machines/<KEY>.psd1 or machine.local.psd1 is left alone. sync.ps1
# runs this on every sync, so a store a newly installed tool makes moves on the next one. A store
# whose program is running is reported and left for the next run, once the program has stopped.
#
# ASCII only: Windows PowerShell 5.1 reads a script with no byte-order mark as ANSI.

param(
    [string]$DataDrive,
    [switch]$Check,
    [switch]$Quiet,
    [switch]$PassThru
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "output.ps1")
. (Join-Path $PSScriptRoot "overlays.ps1")
. (Join-Path $PSScriptRoot "native.ps1")
. (Join-Path $PSScriptRoot "data-drive.ps1")

$result = New-ScriptResult -Name "install-data-drive.ps1" -Quiet:$Quiet -PassThru:$PassThru
$localPath = Join-Path (Split-Path $PSScriptRoot -Parent) "ai\secrets\machine.local.psd1"

try {
    if ($DataDrive) {
        $drive = ConvertTo-DataDrive -Value $DataDrive -Source '-DataDrive'
    } else {
        $overlaySet = Get-Overlays -RepoPath (Split-Path $PSScriptRoot -Parent)
        $machinePath = Get-OverlaySource -Set $overlaySet -Path "machines/{KEY}.psd1"
        $drive = Get-DataDrive -Path (@($localPath) + @($machinePath | Where-Object { $_ }))
    }
} catch {
    Fail "could not read this machine's DataDrive: $($_.Exception.Message)"
    Exit-WithResult $result 1
}

if (-not $drive) {
    Say "no DataDrive for this machine; every store stays where its tool puts it" DarkGray
    Exit-WithResult $result 0
}
if (-not (Test-Path -LiteralPath "$drive\")) {
    Fail "DataDrive is $drive, and this machine has no $drive drive"
    Exit-WithResult $result 1
}
if ($env:USERPROFILE -like "$drive\*") {
    Say "the profile is already on $drive; nothing to move" DarkGray
    Exit-WithResult $result 0
}

$pending = 0
$root = Get-DataDriveTarget -DataDrive $drive -ProfilePath $env:USERPROFILE -Relative ''
switch (Initialize-DataDriveProfile -ProfilePath $env:USERPROFILE -Root $root -Check:$Check) {
    'AlreadySecure' { Ok "$root has the profile's access list" }
    'Created'       { Change "made $root with the profile's access list" }
    'Secured'       { Change "gave $root the profile's access list in place of the drive's" }
    'Unsecured'     { Warn "$root inherits $drive's access list; would give it the profile's"; $pending++ }
    'Missing'       { Say "$root not made yet" DarkGray }
}

foreach ($store in (Get-DataDriveStores)) {
    $path = Join-Path $env:USERPROFILE $store.Relative
    $target = Get-DataDriveTarget -DataDrive $drive -ProfilePath $env:USERPROFILE -Relative $store.Relative

    try {
        $state = Get-StoreState -Path $path -Target $target

        # Before the move, so a program started while it runs already uses the data drive.
        if ($store.Variable -and $state -ne 'LinkedElsewhere') {
            $current = [Environment]::GetEnvironmentVariable($store.Variable, 'User')
            $action = Get-StoreVariableAction -Current $current -Path $path -Target $target
            if ($action -eq 'Foreign') {
                Warn "$($store.Variable) is '$current', which someone chose; left alone, so $path is not moved"
                continue
            }
            if ($action -eq 'Set') {
                if ($Check) { Warn "$($store.Variable) is '$current', not '$target'"; $pending++ }
                else {
                    [Environment]::SetEnvironmentVariable($store.Variable, $target, 'User')
                    Change "set $($store.Variable)=$target; programs started from now on use it"
                }
            }
        }

        $holder = $null
        if ($state -in 'OnSystem', 'Interrupted') { $holder = Get-StoreHolder -Path $path -Processes $store.Processes }
        if ($Check -or $holder) {
            switch ($state) {
                'Moved'           { Ok "$path -> $target" }
                'Absent'          { Say "$path not made on this machine" DarkGray }
                'LinkedElsewhere' { Warn "$path links somewhere other than $target; left alone" }
                'Broken'          { Warn "$path is a junction to $target, which is gone"; $pending++ }
                'OnBoth'          { Warn "$path and $target both hold the store; keep one and delete the other"; $pending++ }
                default {
                    if ($holder) { Todo "$path is in use by $holder; it moves on a run once $holder has stopped" }
                    else { Warn "$path is $state; would move it to $target" }
                    $pending++
                }
            }
            continue
        }

        switch (Move-StoreToDataDrive -Path $path -Target $target) {
            'Moved'     { if ($state -eq 'Moved') { Ok "$path -> $target" } else { Change "moved $path to $target" } }
            'Relinked'  { Change "linked $path to $target, which already held the store" }
            'Absent'    { Say "$path not made on this machine" DarkGray }
            'InUse'     { Todo "$path is in use; it moves once the program holding it has stopped"; $pending++ }
            'Recreated' { Warn "moved $path to $target, but a program made $path again meanwhile; keep one and delete the other"; $pending++ }
            'Broken'    { Warn "$path is a junction to $target, which is gone"; $pending++ }
            'OnBoth'    { Warn "$path and $target both hold the store; keep one and delete the other"; $pending++ }
        }
    } catch {
        Fail $_.Exception.Message
    }
}

Exit-WithResult $result $(if ($result.Errors -or ($Check -and $pending)) { 1 } else { 0 })
