# Keeps the stores that fill a profile - package caches, model downloads, editor extensions, agent
# data - off the system drive on a machine that has a data drive.
# Dot-sourced by install-data-drive.ps1, after native.ps1.
#
# A machine names its data drive as DataDrive in an overlay's machines/<KEY>.psd1 or in
# ai/secrets/machine.local.psd1. Each store then lives on that drive at the path it would have on C:
# (D:\Users\me\AppData\Local\npm-cache for C:\Users\me\AppData\Local\npm-cache), with a directory
# junction left at the old path, so whatever has the old path baked in still finds it. A store whose
# tool reads a variable for its location gets that variable too, so a tool that deletes and
# recreates its folder recreates it on the data drive rather than behind a removed junction.
#
# ASCII only: Windows PowerShell 5.1 reads a script with no byte-order mark as ANSI.

# Every store, as a path relative to the profile and the user variable its tool reads, if any.
# Stores that belong to a running program (Hermes, T3 Code) are moved only once it has stopped:
# see Move-StoreToDataDrive.
function Get-DataDriveStores {
    @(
        @{ Relative = 'AppData\Local\npm-cache';    Variable = 'npm_config_cache' }
        @{ Relative = '.nuget\packages';            Variable = 'NUGET_PACKAGES' }
        @{ Relative = 'AppData\Local\NuGet\v3-cache'; Variable = 'NUGET_HTTP_CACHE_PATH' }
        @{ Relative = '.cache\huggingface';         Variable = 'HF_HOME' }
        @{ Relative = 'AppData\Local\uv\cache';     Variable = 'UV_CACHE_DIR' }
        @{ Relative = 'AppData\Local\pip\cache';    Variable = 'PIP_CACHE_DIR' }
        @{ Relative = 'AppData\Local\ms-playwright'; Variable = 'PLAYWRIGHT_BROWSERS_PATH' }
        @{ Relative = '.cache\puppeteer';           Variable = 'PUPPETEER_CACHE_DIR' }
        @{ Relative = '.gradle';                    Variable = 'GRADLE_USER_HOME' }
        # CARGO_HOME is left alone: rustup put %USERPROFILE%\.cargo\bin on PATH, and the junction
        # keeps that entry working.
        @{ Relative = '.cargo' }
        @{ Relative = '.rustup' }
        @{ Relative = '.cache\codex-runtimes' }
        @{ Relative = '.vscode\extensions' }
        @{ Relative = 'AppData\Local\hermes'; Processes = @('hermes') }
        @{ Relative = '.t3'; Processes = @('T3 Code (Beta)', 'T3 Code') }
    )
}

# The first running program that holds a store, by name or by an executable inside it, or $null.
# A program can keep a store busy with no file open at the moment of the move, then write into the
# old path while it is being moved, so a store is never moved while one is running.
function Get-StoreHolder {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Processes = @()
    )
    $prefix = $Path.TrimEnd('\') + '\'
    foreach ($process in (Get-Process -ErrorAction SilentlyContinue)) {
        if ($Processes -contains $process.ProcessName) { return $process.ProcessName }
        $exe = $null
        try { $exe = $process.Path } catch { }
        if ($exe -and $exe.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $process.ProcessName }
    }
    return $null
}

# A drive letter written as 'd', 'D:' or 'D:\', as 'D:'. Anything else is an error naming Source.
function ConvertTo-DataDrive {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$Source
    )
    if ($Value -notmatch '^([A-Za-z]):?\\?$') { throw "DataDrive in $Source is '$Value', not a drive letter such as 'D:'" }
    return "$($Matches[1].ToUpperInvariant()):"
}

# The DataDrive of the first given machine file that has the key, as 'D:'; $null when none has it,
# or when that first one sets it to '' - which is how machine.local.psd1 turns off an overlay's.
function Get-DataDrive {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Path)

    foreach ($file in $Path) {
        if (-not $file -or -not (Test-Path -LiteralPath $file)) { continue }
        $data = Import-PowerShellDataFile -LiteralPath $file
        if (-not $data.ContainsKey('DataDrive')) { continue }
        if (-not $data.DataDrive) { return $null }
        return ConvertTo-DataDrive -Value $data.DataDrive -Source $file
    }
    return $null
}

# Makes the profile's folder on the data drive, Root, and gives it the profile's own access list,
# not inheriting the drive's: a data drive's root typically lets every signed-in user modify it,
# and the stores moved under Root hold programs and credentials. 'Created', 'Secured' or 'AlreadySecure'.
function Initialize-DataDriveProfile {
    param(
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)][string]$Root,
        [switch]$Check
    )
    $exists = Test-Path -LiteralPath $Root
    if ($exists -and (Get-Acl -LiteralPath $Root).AreAccessRulesProtected) { return 'AlreadySecure' }
    if ($Check) { return $(if ($exists) { 'Unsecured' } else { 'Missing' }) }

    if (-not $exists) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }
    $acl = Get-Acl -LiteralPath $Root
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRule($rule) }
    foreach ($rule in (Get-Acl -LiteralPath $ProfilePath).Access) { $acl.AddAccessRule($rule) }
    Set-Acl -LiteralPath $Root -AclObject $acl
    return $(if ($exists) { 'Secured' } else { 'Created' })
}

# What to do with a store's location variable:
#   Ok       it already names Target
#   Set      unset, or naming the store's own path on the system drive; point it at Target
#   Foreign  someone pointed it elsewhere; leave it and say so
function Get-StoreVariableAction {
    param(
        [AllowEmptyString()][AllowNull()][string]$Current,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target
    )
    if (-not $Current -or $Current.TrimEnd('\') -ieq $Path.TrimEnd('\')) { return 'Set' }
    if ($Current.TrimEnd('\') -ieq $Target.TrimEnd('\')) { return 'Ok' }
    return 'Foreign'
}

# Where a store under the profile lives on the data drive: the same path with the drive swapped.
function Get-DataDriveTarget {
    param(
        [Parameter(Mandatory)][string]$DataDrive,
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Relative
    )
    $profileOnData = $DataDrive + ($ProfilePath -replace '^[A-Za-z]:', '')
    if (-not $Relative) { return $profileOnData }
    return Join-Path $profileOnData $Relative
}

# The junction's target, or $null when Path is no junction.
function Get-JunctionTarget {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item -or -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $null }
    return @($item.Target)[0]
}

# The folder a store is renamed to while it moves.
function Get-StoreAside {
    param([Parameter(Mandatory)][string]$Path)
    return "$Path.moving-to-data-drive"
}

# Whether a folder holds anything at all.
function Test-FolderHasEntries {
    param([Parameter(Mandatory)][string]$Path)
    return [bool](Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
}

# Where a store stands:
#   Moved            Path is a junction to Target, and Target is there
#   Broken           Path is a junction to Target, and Target is gone
#   Absent           nothing at Path, and nothing at Target
#   Orphaned         nothing at Path, but Target holds the store - after the system drive was rebuilt
#   OnSystem         Path is a real folder, and Target is empty or not there
#   OnBoth           Path is a real folder, and Target holds files too
#   Interrupted      a move stopped partway: the store is in Path's aside folder
#   LinkedElsewhere  Path is a junction or link somewhere else; left alone, since someone chose it
function Get-StoreState {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target
    )
    if (Test-Path -LiteralPath (Get-StoreAside -Path $Path)) { return 'Interrupted' }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) {
        if (Test-FolderHasEntries -Path $Target) { return 'Orphaned' }
        return 'Absent'
    }
    $linked = Get-JunctionTarget -Path $Path
    if ($null -ne $linked) {
        if ($linked.TrimEnd('\') -ine $Target.TrimEnd('\')) { return 'LinkedElsewhere' }
        if (Test-Path -LiteralPath $Target) { return 'Moved' }
        return 'Broken'
    }
    if (Test-FolderHasEntries -Path $Target) { return 'OnBoth' }
    return 'OnSystem'
}

# Every junction and symlink under Path, without descending into any, as Relative (to Path),
# Kind (Junction, SymbolicLink) and Target, the link's own text, so a relative symlink stays relative.
function Get-StoreLinks {
    param([Parameter(Mandatory)][string]$Path)
    $base = $Path.TrimEnd('\').Length + 1
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($Path)
    while ($pending.Count -gt 0) {
        foreach ($item in (Get-ChildItem -LiteralPath $pending.Pop() -Force)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                [pscustomobject]@{
                    Relative    = $item.FullName.Substring($base)
                    Kind        = $item.LinkType
                    IsDirectory = $item.PSIsContainer
                    Target      = @($item.Target)[0]
                }
            } elseif ($item.PSIsContainer) {
                $pending.Push($item.FullName)
            }
        }
    }
}

# Makes one link Get-StoreLinks recorded, under Root. A junction needs no privilege; a symlink is
# made with mklink, which honours Developer Mode as managed-link.ps1 relies on.
function New-StoreLink {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Link
    )
    $at = Join-Path $Root $Link.Relative
    New-Item -ItemType Directory -Path (Split-Path $at) -Force | Out-Null
    if ($Link.Kind -eq 'Junction') {
        New-Item -ItemType Junction -Path $at -Target $Link.Target | Out-Null
        return
    }
    $mklink = if ($Link.IsDirectory) {
        Invoke-Native cmd /c mklink /D "`"$at`"" "`"$($Link.Target)`""
    } else {
        Invoke-Native cmd /c mklink "`"$at`"" "`"$($Link.Target)`""
    }
    if (-not $mklink.Ok) { throw "could not make the symlink $at -> $($Link.Target) (enable Developer Mode or run elevated): $($mklink.Output)" }
}

# Moves Source's whole tree into Target, junctions and symlinks moved as links rather than followed
# or dropped (a Hugging Face snapshot is all symlinks, and a node workspace holds junctions), then
# removes Source, refusing while anything is left in it. robocopy moves the files; its /SL needs a
# privilege an unelevated sync does not hold, so the links are made here.
function Move-StoreTree {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target
    )
    $links = @(Get-StoreLinks -Path $Source)
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    $output = robocopy $Source $Target /E /MOVE /XJ /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NP
    $exit = $LASTEXITCODE
    if ($exit -ge 8) {
        $tail = (@($output) | Where-Object { $_.Trim() } | Select-Object -Last 5) -join ' | '
        throw "robocopy could not move $Source to $Target (exit $exit): $tail; what it did not move is still in $Source"
    }
    foreach ($link in $links) {
        if (-not (Get-Item -LiteralPath (Join-Path $Target $link.Relative) -Force -ErrorAction SilentlyContinue)) {
            New-StoreLink -Root $Target -Link $link
        }
        $old = Join-Path $Source $link.Relative
        if ($link.IsDirectory) { [IO.Directory]::Delete($old, $false) } else { [IO.File]::Delete($old) }
    }
    if (-not (Test-Path -LiteralPath $Source)) { return }
    $left = @(Get-ChildItem -LiteralPath $Source -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer })
    if ($left.Count -gt 0) { throw "$($left.Count) file(s) are still in $Source after the move, such as $($left[0].FullName); nothing was deleted" }
    [IO.Directory]::Delete($Source, $true)
}

# Moves a store to Target and leaves a junction at Path. Returns:
#   Moved      done, now or before
#   Relinked   Target already held the store, so only the junction was made
#   Absent     nothing there; nothing done, so no folder appears for a tool that is not installed
#   InUse      a program holds a file in it; nothing done
#   Recreated  a program made Path again during the move; the store is on Target, Path is left
#   OnBoth, Broken   nothing done: a person decides which copy is the store, or where it went
#
# The folder is renamed aside first: Windows refuses to rename a folder while any file under it is
# open, so the rename proves nothing is writing to it, and a store is never left half on each drive
# - a SQLite database moved without its -wal file would be corrupt. For the same reason two copies
# are never merged: a fresh, empty database is newer than the real one it would replace.
function Move-StoreToDataDrive {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target
    )

    $state = Get-StoreState -Path $Path -Target $Target
    $aside = Get-StoreAside -Path $Path
    switch ($state) {
        { $_ -in 'Moved', 'Absent', 'OnBoth', 'Broken' } { return $state }
        'LinkedElsewhere' { throw "$Path is a link to somewhere other than $Target; left alone" }
        'Interrupted' {
            if (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue) {
                throw "$aside is left from a move that did not finish, and $Path exists again; decide which holds the store"
            }
            Move-StoreTree -Source $aside -Target $Target
        }
        'Orphaned' {
            New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
            return 'Relinked'
        }
        'OnSystem' {
            try {
                Rename-Item -LiteralPath $Path -NewName (Split-Path $aside -Leaf) -ErrorAction Stop
            } catch {
                $inner = $_.Exception
                while ($inner.InnerException) { $inner = $inner.InnerException }
                if ($inner -is [IO.IOException] -or $inner -is [UnauthorizedAccessException]) { return 'InUse' }
                throw
            }
            Move-StoreTree -Source $aside -Target $Target
        }
    }

    if (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue) { return 'Recreated' }
    New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
    return 'Moved'
}
