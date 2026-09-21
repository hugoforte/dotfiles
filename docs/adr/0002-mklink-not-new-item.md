# Symlinks are made with `cmd /c mklink`, not `New-Item -ItemType SymbolicLink`

`powershell/managed-link.ps1` shells out to `cmd` to make every symlink, which looks like
something to tidy up into the native cmdlet. It is not. Measured on Windows 11, PowerShell 5.1,
unelevated, with Developer Mode on:

| Mechanism | Result |
| --- | --- |
| `New-Item -ItemType SymbolicLink` | fails — "Administrator privilege required for this operation." |
| `cmd /c mklink` | works |
| `ln -s` under `MSYS=winsymlinks:nativestrict` | works |

Windows PowerShell 5.1 never passes `SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE`, so its cmdlet
cannot benefit from Developer Mode however the machine is configured. PowerShell 7 can, but these
scripts run under 5.1 — that is what a scheduled task and a fresh machine get.

Before this was settled the repo held three contradictory beliefs at once: `deploy-secrets.ps1`
used mklink and documented why, `tools.psd1` declared Developer Mode sufficient, and `setup.ps1`
used the cmdlet and self-elevated to make it work. The fact now lives in one place.

**`setup.ps1` still self-elevates, and that is not leftover.** It runs `install-tools.ps1`, and
winget installs machine-wide only when elevated. Removing the elevation would silently move every
package to `--scope user`. The elevation is about winget; it was never about symlinks.
See [0003](0003-back-up-then-link.md) for what happens to a real file in the way.
