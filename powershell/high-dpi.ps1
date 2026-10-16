# Has Windows run a program that does not declare itself DPI-aware as if it did, so on a scaled
# display it draws at the display's own resolution instead of at a fraction of it, stretched. This
# is the per-user compatibility flag HIGHDPIAWARE, what a program's Properties > Compatibility >
# "Change high DPI settings" > "Override high DPI scaling behavior", scaling performed by
# Application, writes: a string under HKCU\...\AppCompatFlags\Layers named for the program's full path.
#
# Add-HighDpiAwareLayer is the decision and a function of its arguments; Set-HighDpiAware applies
# it to the real user registry. A program already running keeps the scaling it started with.

# The Layers data with HIGHDPIAWARE in it, or $null when it already has it. Windows writes the flags
# space-separated after a leading ~, and an empty value starts with one. Every other flag stays where
# it was, except the two other answers to "scaling performed by" - DPIUNAWARE (System) and
# GDIDPISCALING (System, Enhanced) - which HIGHDPIAWARE replaces.
function Add-HighDpiAwareLayer {
    param([AllowEmptyString()][AllowNull()][string]$Layers)

    $flags = @(($Layers -split '\s+') | Where-Object { $_ })
    $kept = @($flags | Where-Object { @('DPIUNAWARE', 'GDIDPISCALING') -notcontains $_ })
    if ($kept -contains 'HIGHDPIAWARE') {
        if ($kept.Count -eq $flags.Count) { return $null }
        return $kept -join ' '
    }
    if ($kept.Count -eq 0) { $kept = @('~') }
    return (@($kept) + 'HIGHDPIAWARE') -join ' '
}

# 'AlreadySet', 'Set', or with -Check 'Missing'. Path is the executable's full path, which names the
# value; registry value names match whatever their case.
function Set-HighDpiAware {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Check
    )
    $subKey = 'Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    $key = if ($Check) {
        [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKey)
    } else {
        [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($subKey)
    }
    try {
        $current = if ($key) { $key.GetValue($Path) }
        $updated = Add-HighDpiAwareLayer -Layers $current
        if ($null -eq $updated) { return 'AlreadySet' }
        if ($Check) { return 'Missing' }
        $key.SetValue($Path, $updated, [Microsoft.Win32.RegistryValueKind]::String)
        return 'Set'
    } finally {
        if ($key) { $key.Close() }
    }
}
