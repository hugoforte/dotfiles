---
applyTo: "powershell/**/*.ps1"
---

# PowerShell Development Patterns

This file captures how PowerShell code is implemented in this repository.

## File Split Pattern

Use `profile.ps1` as a small entrypoint and place feature logic in separate files.

```powershell
$profileScriptRoot = Split-Path -Parent $profilePath
$awsHelpersPath = Join-Path $profileScriptRoot "aws.ps1"
$gitHelpersPath = Join-Path $profileScriptRoot "git.ps1"
```

Key points:

- Keep `list-functions` in `profile.ps1`.
- Keep AWS helpers in `aws.ps1` and git helpers in `git.ps1`.
- Dot-source helpers only after path checks.

## Symlink-Aware Loader Pattern

When profile is symlinked, resolve target path before locating helper files.

```powershell
$profileItem = Get-Item -LiteralPath $profilePath -ErrorAction SilentlyContinue
if ($profileItem -and $profileItem.LinkType -eq "SymbolicLink" -and $profileItem.Target) {
    $targetPath = $profileItem.Target
    if ($targetPath -is [System.Array]) {
        $targetPath = $targetPath[0]
    }
    if (-not [System.IO.Path]::IsPathRooted($targetPath)) {
        $targetPath = Join-Path (Split-Path -Parent $profilePath) $targetPath
    }
    $profilePath = $targetPath
}
```

Key points:

- Handle `Target` as array or string.
- Resolve relative symlink targets.
- Provide fallback location if helper files are missing.

## AWS Profile Switch Menu Pattern

Interactive switcher uses sorted profile list, numbered menu, cancel option, and safe numeric parsing.

```powershell
$selection = Read-Host "Select profile number"
[int]$selectionNumber = 0
if (-not [int]::TryParse($selection, [ref]$selectionNumber)) {
    Write-Host "Invalid selection. Please enter a number." -ForegroundColor Red
    return
}
```

Key points:

- Use `TryParse` for user input.
- Include `[0] Cancel` path.
- Keep output color semantics consistent.

## Git Helper Parameter Pattern

Use typed parameters with explicit scopes and optional help switch.

```powershell
param(
    [string]$Branch = "develop",
    [ValidateSet("local", "remote", "auto")]
    [string]$Scope = "local",
    [string]$Remote = "origin",
    [switch]$Help
)
```

Key points:

- Prefer `ValidateSet` for bounded options.
- Keep defaults stable (`develop`, `local`, `origin`).
- Support `-help` for discoverability.

## Local vs Remote Branch Handling

Remote operations should enumerate and delete remote refs, not local branches.

```powershell
$mergedBranches = git for-each-ref --format="%(refname:short)" --merged $targetRef "refs/remotes/$Remote" |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and $_ -notlike "*/HEAD" -and $_ -ne $Remote }
```

Key points:

- Exclude `*/HEAD` and bare remote namespace (`origin`).
- Strip `<remote>/` prefix when presenting names.
- Use `git push <remote> --delete <branch>` for remote deletion.

## Setup Script Pattern

`setup.ps1` is idempotent and should gate destructive changes with checks/backups.

```powershell
if ((Test-Path $PROFILE) -and (Get-Item $PROFILE).LinkType -ne "SymbolicLink") {
    $backupPath = "$PROFILE.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $PROFILE $backupPath
    Remove-Item $PROFILE -Force
}
```

Key points:

- Backup regular files before replacement.
- Verify existing symlink targets before recreating.
- Use admin relaunch pattern for symlink creation on Windows.
