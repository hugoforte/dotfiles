$script:RigRootCandidates = @(
    $env:RIG_ROOT,
    "D:\rig",
    "C:\rig",
    (Join-Path $env:USERPROFILE "rig")
)

function Get-RigRoot {
    foreach ($candidate in $script:RigRootCandidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }

        # [System.IO.Path]::Combine rather than Join-Path: Join-Path throws on a
        # candidate whose drive does not exist, which is exactly the case we are
        # probing for.
        $entry = [System.IO.Path]::Combine($candidate, "bin\rig.mjs")

        if (Test-Path -LiteralPath $entry -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function rig {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $root = Get-RigRoot

    if (-not $root) {
        Write-Host "rig is not installed on this machine." -ForegroundColor Red
        Write-Host ""
        Write-Host "Looked in:" -ForegroundColor Cyan
        foreach ($candidate in $script:RigRootCandidates) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            Write-Host "  $candidate" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "Install it with:" -ForegroundColor Cyan
        Write-Host "  git clone https://github.com/hugoforte/rig.git D:\rig" -ForegroundColor White
        Write-Host "  node D:\rig\bin\rig.mjs init" -ForegroundColor White
        Write-Host ""
        Write-Host "Or set RIG_ROOT to an existing checkout." -ForegroundColor DarkGray
        return
    }

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Host "rig needs Node.js 18+ on PATH, and node was not found." -ForegroundColor Red
        return
    }

    node ([System.IO.Path]::Combine($root, "bin\rig.mjs")) @Arguments
}

function rig-goto-root {
    $root = Get-RigRoot

    if (-not $root) {
        Write-Host "rig is not installed on this machine. Run 'rig' for install instructions." -ForegroundColor Red
        return
    }

    Set-Location -LiteralPath $root
}
