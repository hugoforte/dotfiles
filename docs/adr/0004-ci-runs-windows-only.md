# CI runs windows-latest, and only windows-latest

`.github/workflows/check.yml` has one job on one OS. A cross-platform matrix is the obvious thing
to reach for and would be worse than useless here.

Both defects this repo has actually shipped were invisible on any other platform. `Write-Host`
writes to the information stream, which **Windows PowerShell 5.1** does not capture through
`| Out-String`, so the scheduled task logged a hardcoded `"ok"` for runs that warned. And jq on
Windows emits CRLF into a repo whose `.gitattributes` is `* text=auto eol=lf`, which is why
`settings_write_json` strips `\r`.

A Linux runner passes both of those vacuously. That is worse than not testing them, because a
green check that cannot fail looks like coverage. For the same reason every PowerShell step is
`shell: powershell` (5.1) and never `pwsh` (7.x): 5.1 is what the scheduled task runs, and the
two differ on exactly the behaviour under test.

Ubuntu becomes worth adding if a genuinely platform-independent suite ever appears here. Today
there is none — this repo configures Windows machines.
