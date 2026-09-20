# Shared reporting for the dotfiles scripts: one vocabulary, and a result a caller can read.
#
#   . (Join-Path $PSScriptRoot "output.ps1")
#   $result = New-ScriptResult -Name "install-tools.ps1" -Quiet:$Quiet -PassThru:$PassThru
#   Say "Reading tools.psd1" Cyan
#   Ok "git"
#   Exit-WithResult $result 0
#
# Ok / Change / Warn / Todo / Fail both print (the console adapter) and record on the open
# result, so a caller reads outcomes instead of scraping the console. Say only prints: it is
# chatter, not an outcome.
#
# Why a result at all: Write-Host writes to the information stream, which Windows PowerShell 5.1
# does not capture through `| Out-String` - a caller piping a child script gets an empty string.
# Exit-WithResult writes the result to the success stream when the script was called with
# -PassThru, and that does cross the call boundary.
#
# The result is plain data - counts and messages, no methods. A script scope dies with the
# script, so a method added here would fail the moment the caller called it; formatting lives in
# Get-ResultSummary and Get-ResultLines instead.
#
# Prefixes match ai/helpers/output.sh so both languages report the same way. They are ASCII on
# purpose: sync.log and the Windows console are not reliably UTF-8, and a check mark arrives
# there mangled.

$script:OutcomeStyles = [ordered]@{
    Ok     = @{ Prefix = "[OK]"; Color = "Green";   Count = "Ok" }
    Change = @{ Prefix = "[..]"; Color = "Cyan";    Count = "Changed" }
    Warn   = @{ Prefix = "[!!]"; Color = "Yellow";  Count = "Warned" }
    Todo   = @{ Prefix = "[->]"; Color = "Magenta"; Count = "Todo" }
    Error  = @{ Prefix = "[XX]"; Color = "Red";     Count = "Errors" }
}

function Get-OutcomeStyle {
    param([Parameter(Mandatory)][string]$Kind)
    $style = $script:OutcomeStyles[$Kind]
    if (-not $style) { throw "Unknown outcome kind '$Kind'. Known kinds: $($script:OutcomeStyles.Keys -join ', ')" }
    return $style
}

# --- The result ---------------------------------------------------------------------------------

function New-ScriptResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Quiet,
        [switch]$PassThru
    )

    $script:ScriptResult = [pscustomobject]@{
        Name     = $Name
        Quiet    = [bool]$Quiet
        PassThru = [bool]$PassThru
        Ok       = 0
        Changed  = 0
        Warned   = 0
        Todo     = 0
        Errors   = 0
        Messages = @()
    }
    return $script:ScriptResult
}

function Get-ScriptResult {
    if (-not $script:ScriptResult) {
        throw "No script result is open: call New-ScriptResult before reporting."
    }
    return $script:ScriptResult
}

# One line per message, prefixed as the console would have printed it. Pass -Kinds to keep only
# the ones a log cares about: Get-ResultLines $result -Kinds Warn, Error, Todo
function Get-ResultLines {
    param(
        [Parameter(Mandatory)][psobject]$Result,
        [string[]]$Kinds
    )
    $wanted = @($Result.Messages)
    if ($Kinds) { $wanted = @($wanted | Where-Object { $Kinds -contains $_.Kind }) }
    return @($wanted | ForEach-Object { "$((Get-OutcomeStyle $_.Kind).Prefix) $($_.Message)" })
}

function Get-ResultSummary {
    param([Parameter(Mandatory)][psobject]$Result)
    $parts = @()
    if ($Result.Ok)      { $parts += "$($Result.Ok) ok" }
    if ($Result.Changed) { $parts += "$($Result.Changed) changed" }
    if ($Result.Warned)  { $parts += "$($Result.Warned) warning(s)" }
    if ($Result.Todo)    { $parts += "$($Result.Todo) to do" }
    if ($Result.Errors)  { $parts += "$($Result.Errors) error(s)" }
    if ($parts.Count -eq 0) { $parts = @("nothing to report") }
    return "$($Result.Name): $($parts -join ', ')"
}

# --- The console adapter ------------------------------------------------------------------------

function Say {
    param([string]$Message, [string]$Color = "Gray")
    if (-not (Get-ScriptResult).Quiet) { Write-Host $Message -ForegroundColor $Color }
}

function Write-Outcome {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message
    )
    $result = Get-ScriptResult
    $style = Get-OutcomeStyle $Kind
    $result.Messages += [pscustomobject]@{ Kind = $Kind; Message = $Message }
    $countName = $style.Count
    $result.$countName = $result.$countName + 1
    # Quiet is for unattended callers; a problem is still worth a console line when one watches.
    if (-not $result.Quiet -or $Kind -in @("Warn", "Error")) {
        Write-Host "$($style.Prefix) $Message" -ForegroundColor $style.Color
    }
}

function Ok     { param([string]$Message) Write-Outcome "Ok"     $Message }
function Change { param([string]$Message) Write-Outcome "Change" $Message }
function Warn   { param([string]$Message) Write-Outcome "Warn"   $Message }
function Todo   { param([string]$Message) Write-Outcome "Todo"   $Message }
function Fail   { param([string]$Message) Write-Outcome "Error"  $Message }

# --- The exit-code adapter ----------------------------------------------------------------------

# Ends the calling script, handing the result to the caller when it asked for one.
function Exit-WithResult {
    param(
        [Parameter(Mandatory)][psobject]$Result,
        [int]$Code = 0
    )
    if ($Result.PassThru) { $Result }
    exit $Code
}

# --- The log-file adapter -----------------------------------------------------------------------

# Console colour is ANSI escapes once captured; a log file wants the text only.
function Remove-AnsiEscape {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    return [regex]::Replace($Text, "$([char]27)\[[0-9;?]*[ -/]*[@-~]", "")
}
