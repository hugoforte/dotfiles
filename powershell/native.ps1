# Runs a native command and judges it by its exit code. Under $ErrorActionPreference = 'Stop',
# Windows PowerShell 5.1 turns any line a native command writes to stderr into a terminating
# error - and git writes its progress there - so the preference is relaxed for this call only.
#
#   $pull = Invoke-Native git -C $repo pull --ff-only
#   if (-not $pull.Ok) { ... $pull.Output ... }
#
# No param block, on purpose: a declared parameter would capture the command's own flags, so
# `git -C <path>` would bind -C to it.
function Invoke-Native {
    $command = $args[0]
    # @(...) because a lone argument would otherwise be a string, which @splatting passes a
    # character at a time.
    $arguments = @($args | Select-Object -Skip 1)
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Ok = $false; ExitCode = $null; Output = "$command not found" }
    }
    $ErrorActionPreference = "Continue"
    # A stderr line arrives as an ErrorRecord, which Out-String would render with its position
    # and category; the line itself is what is worth keeping.
    $lines = & $command @arguments 2>&1 | ForEach-Object { "$_" }
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{ Ok = ($exitCode -eq 0); ExitCode = $exitCode; Output = ($lines -join "`n").Trim() }
}
