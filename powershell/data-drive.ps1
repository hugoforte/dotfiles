# Keeps the stores that fill a profile - package caches, model downloads, editor extensions, agent
# data - off the system drive on a machine that has a data drive.
# Dot-sourced by install-data-drive.ps1.
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

# The DataDrive the given machine files name, the first that names one, as a drive root such as
# 'D:'; $null when none does. A value that is not a drive letter is an error naming the file.
function Get-DataDrive {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Path)

    foreach ($file in $Path) {
        if (-not $file -or -not (Test-Path -LiteralPath $file)) { continue }
        $value = (Import-PowerShellDataFile -LiteralPath $file).DataDrive
        if (-not $value) { continue }
        if ($value -notmatch '^([A-Za-z]):?\\?$') { throw "DataDrive in $file is '$value', not a drive letter such as 'D:'" }
        return "$($Matches[1].ToUpperInvariant()):"
    }
    return $null
}

# Where a store under the profile lives on the data drive: the same path with the drive swapped.
function Get-DataDriveTarget {
    param(
        [Parameter(Mandatory)][string]$DataDrive,
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)][string]$Relative
    )
    $underRoot = $ProfilePath -replace '^[A-Za-z]:', ''
    return Join-Path (Join-Path $DataDrive $underRoot) $Relative
}

# The junction's target, or $null when Path is no junction.
function Get-JunctionTarget {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item -or -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $null }
    return @($item.Target)[0]
}

# Where a store stands:
#   Moved       Path is a junction to Target
#   Absent      nothing at Path
#   OnSystem    Path is a real folder
#   LinkedElsewhere  Path is a junction or link somewhere else; left alone, since someone chose it
function Get-StoreState {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        if (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue) { return 'LinkedElsewhere' }
        return 'Absent'
    }
    $linked = Get-JunctionTarget -Path $Path
    if ($null -eq $linked) { return 'OnSystem' }
    if ($linked.TrimEnd('\') -ieq $Target.TrimEnd('\')) { return 'Moved' }
    return 'LinkedElsewhere'
}

# Moves a store to Target and leaves a junction at Path. Returns 'Moved' (now or before), 'Absent'
# (nothing there; nothing done), 'InUse' when a program holds a file in it, or 'Recreated' when a
# program made the folder again while it was being moved, so no junction could take its place.
#
# The folder is renamed aside first: Windows refuses to rename a folder while any file under it is
# open, so the rename proves nothing is writing to it, and a store is never left half on each drive
# - a SQLite database moved without its -wal file would be corrupt. A merge into an existing Target
# keeps the newer copy of a file both have.
function Move-StoreToDataDrive {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target
    )

    $state = Get-StoreState -Path $Path -Target $Target
    # A store this machine has never made is left unmade: a junction would make a folder on the data
    # drive for a tool that may not be installed.
    if ($state -in 'Moved', 'Absent') { return $state }
    if ($state -eq 'LinkedElsewhere') { throw "$Path is a link to somewhere other than $Target; left alone" }

    $aside = "$Path.moving-to-data-drive"
    if (Test-Path -LiteralPath $aside) { throw "$aside is left from a move that did not finish; move what is in it to $Target and delete it" }
    try {
        Rename-Item -LiteralPath $Path -NewName (Split-Path $aside -Leaf) -ErrorAction Stop
    } catch {
        return 'InUse'
    }
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    $null = robocopy $aside $Target /E /MOVE /XO /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /NFL /NDL /NJH /NJS /NP
    $exit = $LASTEXITCODE
    if ($exit -ge 8) { throw "robocopy could not move $aside to $Target (exit $exit); what it did not move is still in $aside" }
    # /MOVE leaves a file behind when /XO skipped it because Target's copy is newer.
    if (Test-Path -LiteralPath $aside) { $null = cmd /c rd /s /q $aside }
    if (Test-Path -LiteralPath $aside) { throw "moved $Path to $Target, but could not delete $aside" }

    # A program started during the move can make the folder again; the next run merges what it wrote.
    if (Test-Path -LiteralPath $Path) { return 'Recreated' }
    $null = cmd /c mklink /J $Path $Target
    if ($LASTEXITCODE -ne 0) { throw "moved $Path to $Target, but could not make a junction at $Path (mklink exit $LASTEXITCODE)" }
    return 'Moved'
}
