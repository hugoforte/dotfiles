# Runs a native command and judges it by its exit code. Under $ErrorActionPreference = 'Stop',
# Windows PowerShell 5.1 turns any line a native command writes to stderr into a terminating
# error - and git writes its progress there - so the preference is relaxed for this call only.
#
#   $pull = Invoke-Native git -C $repo pull --ff-only
#   if (-not $pull.Ok) { ... $pull.Output ... }
#
# Output is stdout and stderr together, in the order they arrived, for a message; StdOut is stdout
# alone, for a caller that parses the command's answer while it logs to stderr (gh with GH_DEBUG).
#
# No param block, on purpose: a declared parameter would capture the command's own flags, so
# `git -C <path>` would bind -C to it. PowerShell still consumes a bare `--` before the
# command sees it, so a caller that needs one passes it quoted: '--'.
function Invoke-Native {
    $command = $args[0]
    # @(...) because a lone argument would otherwise be a string, which @splatting passes a
    # character at a time.
    $arguments = @($args | Select-Object -Skip 1)
    # Application only: a function, alias or script sets no $LASTEXITCODE, so the verdict would
    # be whatever the previous native command left behind.
    if (-not (Get-Command $command -CommandType Application -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Ok = $false; ExitCode = $null; Output = "$command is not a program on PATH"; StdOut = '' }
    }
    $ErrorActionPreference = "Continue"
    # A stderr line arrives as an ErrorRecord, which Out-String would render with its position
    # and category; the line itself is what is worth keeping. Its type is also what tells it from
    # a stdout line.
    $stdout = New-Object System.Collections.Generic.List[string]
    $lines = & $command @arguments 2>&1 | ForEach-Object {
        if ($_ -isnot [System.Management.Automation.ErrorRecord]) { $stdout.Add("$_") }
        "$_"
    }
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        Ok       = ($exitCode -eq 0)
        ExitCode = $exitCode
        Output   = ($lines -join "`n").Trim()
        StdOut   = ($stdout -join "`n").Trim()
    }
}
