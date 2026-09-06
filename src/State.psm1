<#
.SYNOPSIS
    Internal: what a run remembers across restarts.
.DESCRIPTION
    One JSON file per step folder under %ProgramData%\PwshSetup\State, and beside it the script parameters the resume
    task passes back. Written through a temp file, so a restart mid-write cannot leave half a file behind.
#>
#Requires -Version 7.2

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Core.psm1') -DisableNameChecking

# ── Files ────────────────────────────────────────────────────────────────────

function Get-SetupStateFile
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $StepPath,
        [ValidateSet('State', 'Arguments')] [string] $Kind = 'State'
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($StepPath.ToLowerInvariant())
    $hash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).Substring(0, 16).ToLowerInvariant()
    $extension = 'json'
    if ($Kind -eq 'Arguments')
    {
        $extension = 'args.clixml'
    }
    return (Join-Path -Path (Get-SetupDataPath -Name 'State') -ChildPath ('{0}.{1}' -f $hash, $extension))
}

function New-SetupFolder
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path))
    {
        $null = New-Item -ItemType Directory -Path $Path -Force
    }
}

# ── State ────────────────────────────────────────────────────────────────────

function New-SetupState
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string] $StepPath,
        [AllowEmptyString()] [string] $ScriptPath = '',
        [Parameter(Mandatory)] [string] $LogFile,
        [Parameter(Mandatory)] [string[]] $Selected
    )

    return @{
        StepPath     = $StepPath
        ScriptPath   = $ScriptPath
        LogFile      = $LogFile
        StartedAt    = (Get-Date).ToUniversalTime().ToString('o')
        Selected     = @($Selected)
        Results      = @{}
        Retries      = @{}
        Restarts     = 0
        RestartingAt = $null
    }
}

function Read-SetupState
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string] $StepPath
    )

    $file = Get-SetupStateFile -StepPath $StepPath
    if (-not (Test-Path -LiteralPath $file))
    {
        return $null
    }

    try
    {
        $state = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable
    }
    catch
    {
        return $null
    }
    if (-not $state -or $state.StepPath -ne $StepPath)
    {
        return $null
    }

    $state.Selected = @($state.Selected)
    if ($null -eq $state.Results)
    {
        $state.Results = @{}
    }
    if ($null -eq $state.Retries)
    {
        $state.Retries = @{}
    }
    return $state
}

function Save-SetupState
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $State
    )

    $file = Get-SetupStateFile -StepPath $State.StepPath
    New-SetupFolder -Path (Split-Path -Path $file -Parent)

    $temp = '{0}.tmp' -f $file
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temp -Encoding utf8NoBOM
    Move-Item -LiteralPath $temp -Destination $file -Force
}

function Remove-SetupState
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $StepPath
    )

    foreach ($kind in 'State', 'Arguments')
    {
        Remove-Item -LiteralPath (Get-SetupStateFile -StepPath $StepPath -Kind $kind) -Force -ErrorAction Ignore
    }
}

function Save-SetupArgument
{
    # Switches become booleans: a SwitchParameter does not come back from Import-Clixml as one.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $StepPath,
        [AllowNull()] [hashtable] $Arguments
    )

    $portable = @{}
    if ($Arguments)
    {
        foreach ($key in $Arguments.Keys)
        {
            $value = $Arguments[$key]
            if ($value -is [System.Management.Automation.SwitchParameter])
            {
                $value = $value.IsPresent
            }
            $portable[$key] = $value
        }
    }

    $file = Get-SetupStateFile -StepPath $StepPath -Kind 'Arguments'
    New-SetupFolder -Path (Split-Path -Path $file -Parent)
    $portable | Export-Clixml -LiteralPath $file
    return $file
}

function Set-SetupStepResult
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $State,
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [ValidateSet('Done', 'Skipped', 'Failed', 'Retry')] [string] $Status,
        [TimeSpan] $Duration = [TimeSpan]::Zero,
        [AllowEmptyString()] [string] $Reason = ''
    )

    $State.Results[$Id] = @{
        Status  = $Status
        Seconds = [Math]::Round($Duration.TotalSeconds, 1)
        Reason  = $Reason
    }
}

# ── Restarts ─────────────────────────────────────────────────────────────────

function ConvertTo-SetupUtc
{
    # ConvertFrom-Json hands ISO dates back as DateTime; a string is parsed the same way.
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory)] [object] $Value
    )

    if ($Value -is [datetime])
    {
        return $Value.ToUniversalTime()
    }
    $styles = [System.Globalization.DateTimeStyles]::RoundtripKind
    return [datetime]::Parse([string]$Value, [cultureinfo]::InvariantCulture, $styles).ToUniversalTime()
}

function Test-SetupRestartedSince
{
    # The run asked for a restart, and the machine has booted since.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [hashtable] $State
    )

    if (-not $State.RestartingAt)
    {
        return $false
    }

    $restartingAt = ConvertTo-SetupUtc -Value $State.RestartingAt
    $bootedAt = (Get-CimInstance -ClassName 'Win32_OperatingSystem').LastBootUpTime.ToUniversalTime()
    return ($bootedAt -gt $restartingAt)
}

Export-ModuleMember -Function Get-SetupStateFile, New-SetupState, Read-SetupState, Save-SetupState, Remove-SetupState,
Save-SetupArgument, Set-SetupStepResult, ConvertTo-SetupUtc, Test-SetupRestartedSince
