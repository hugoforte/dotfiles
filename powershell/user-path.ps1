# Puts a directory on the user PATH, so a program in it runs from any shell - including the
# Git Bash and -NoProfile PowerShell that agents use, which never load the profile.
#
# Add-PathEntry is the decision and a function of its arguments; Add-UserPathEntry applies it to
# the real user environment. A shell or app already open keeps the PATH it started with.

# The PATH list with $Entry on the end, or $null when it is already there. Entries compare
# case-insensitively, with %VAR% references expanded and a trailing backslash ignored, as Windows
# resolves them. The list comes back as written, its %VAR% references unexpanded.
function Add-PathEntry {
    param(
        [AllowEmptyString()][AllowNull()][string]$PathList,
        [Parameter(Mandatory)][string]$Entry
    )
    $normalise = { param($p) [Environment]::ExpandEnvironmentVariables($p.Trim()).TrimEnd('\') }
    $entries = @(($PathList -split ';') | Where-Object { $_.Trim() })
    foreach ($existing in $entries) {
        if ((& $normalise $existing) -ieq (& $normalise $Entry)) { return $null }
    }
    return (@($entries) + $Entry) -join ';'
}

# 'AlreadyPresent', 'Added', or with -Check 'Missing'.
function Add-UserPathEntry {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [switch]$Check
    )
    # Through the registry, not [Environment]::SetEnvironmentVariable: that reads the list
    # expanded and writes it back as a plain string, turning every %VAR% entry into a fixed path.
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $current = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $updated = Add-PathEntry -PathList $current -Entry $Directory
        if ($null -eq $updated) { return 'AlreadyPresent' }
        if ($Check) { return 'Missing' }
        $key.SetValue('Path', $updated, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } finally {
        $key.Close()
    }
    # A no-op set that broadcasts WM_SETTINGCHANGE, so Explorer - and what it starts - sees the change.
    [Environment]::SetEnvironmentVariable('DotfilesPathRefresh', $null, 'User')
    return 'Added'
}
