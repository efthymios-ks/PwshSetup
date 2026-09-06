<#
.SYNOPSIS
    Internal: the screens of a run, drawn with PwshAnsi. Header, key line and keys, the step list, the dry run, the
    summary, the failure.
#>
#Requires -Version 7.2

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Core.psm1') -DisableNameChecking
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Steps.psm1') -DisableNameChecking

$script:ResultLabel = @{
    Done    = '[BrightGreen]Done[/]'
    Skipped = '[DarkGray]Already done[/]'
    Failed  = '[BrightRed]Failed[/]'
    Retry   = '[BrightYellow]After restart[/]'
    NotRun  = '[DarkGray]Not run[/]'
}
$script:ReasonLength = 60
$script:ResizeSettleMilliseconds = 150
$script:KeyPollMilliseconds = 40
$script:TableArguments = @{
    Border            = 'Rounded'
    BorderColor       = 'DarkGray'
    HeaderColor       = 'BrightCyan'
    ShowRowSeparators = $true
}

# ── Screen ───────────────────────────────────────────────────────────────────

function Clear-SetupScreen
{
    [CmdletBinding()]
    param()

    if (-not (Test-SetupInteractive))
    {
        return
    }
    Clear-Host
    [Console]::Write(('{0}[3J' -f [char]27))
}

function Write-SetupBlankLine
{
    [CmdletBinding()]
    param()

    [Console]::WriteLine()
}

function Write-SetupHeader
{
    # Label and value pairs, one to a row. Values may carry markup.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Item
    )

    Format-AnsiRule -Title '[BrightWhite]PwshSetup[/]' -Alignment Left -LineColor DarkGray | Out-AnsiHost
    if ($Item.Count -gt 0)
    {
        $width = ($Item | ForEach-Object -Process { ([string]$_[0]).Length } | Measure-Object -Maximum).Maximum
        $rows = [System.Collections.Generic.List[object]]::new()
        foreach ($pair in $Item)
        {
            $rows.Add([string[]]@(('[DarkGray]{0}[/]' -f ([string]$pair[0]).PadRight($width)), [string]$pair[1]))
        }
        Format-AnsiGrid -Rows $rows.ToArray() -Padding 3 | Out-AnsiHost
    }
    Write-SetupBlankLine
}

function Write-SetupNote
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [string] $Color
    )

    $message = ConvertTo-SetupLiteral -Text $Text
    if ($Color)
    {
        $message = '[{0}]{1}[/]' -f $Color, $message
    }
    Format-AnsiText -Message $message | Out-AnsiHost
}

# ── Keys ─────────────────────────────────────────────────────────────────────

function Write-SetupKeyLine
{
    # Every entry is "<key> <label>", e.g. "F6 Run".
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Key
    )

    $parts = foreach ($entry in $Key)
    {
        $split = $entry -split ' ', 2
        '[BrightCyan]{0}[/] {1}' -f $split[0], (ConvertTo-SetupLiteral -Text $split[1])
    }
    Format-AnsiText -Message ($parts -join ' [DarkGray]·[/] ') | Out-AnsiHost
}

function Read-SetupKey
{
    # Waits under a screen: a listed key or Esc acts at once, and a resize returns once the window keeps one size, so
    # the caller redraws. Action is Key, Back or Resize.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string[]] $Key
    )

    $Host.UI.RawUI.FlushInputBuffer()
    $width = [Console]::WindowWidth
    $height = [Console]::WindowHeight
    $resizedAt = $null

    while ($true)
    {
        if (-not [Console]::KeyAvailable)
        {
            if ([Console]::WindowWidth -ne $width -or [Console]::WindowHeight -ne $height)
            {
                $width = [Console]::WindowWidth
                $height = [Console]::WindowHeight
                $resizedAt = [datetime]::UtcNow
            }
            elseif ($resizedAt -and ([datetime]::UtcNow - $resizedAt).TotalMilliseconds -ge $script:ResizeSettleMilliseconds)
            {
                return [pscustomobject]@{ Action = 'Resize'; Key = '' }
            }
            Start-Sleep -Milliseconds $script:KeyPollMilliseconds
            continue
        }

        $name = [string][Console]::ReadKey($true).Key
        if ($name -eq 'Escape')
        {
            return [pscustomobject]@{ Action = 'Back'; Key = $name }
        }
        if ($Key -contains $name)
        {
            return [pscustomobject]@{ Action = 'Key'; Key = $name }
        }
    }
}

function Read-SetupConfirm
{
    # No is the default: Enter alone never starts anything.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Prompt
    )

    $Host.UI.RawUI.FlushInputBuffer()
    return [bool](Read-AnsiConfirm -Prompt $Prompt -Default $false)
}

# ── Steps ────────────────────────────────────────────────────────────────────

function Format-SetupOrder
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Step
    )

    if ($Step.Order -eq [int]::MaxValue)
    {
        return ''
    }
    return ('{0:000}' -f $Step.Order)
}

function Format-SetupStepAction
{
    # What a step does, read from its code: install the packages it names, or run; then restart when it says so.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Step
    )

    $packages = Get-SetupStepPackage -Step $Step
    $action = 'run'
    if ($packages.Names.Count -gt 0)
    {
        $action = 'install {0}' -f ($packages.Names -join ', ')
        if ($packages.Unknown -gt 0)
        {
            $action += ' and more'
        }
    }
    elseif ($packages.Unknown -gt 0)
    {
        $action = 'install packages'
    }

    $text = '[BrightCyan]{0}[/]' -f (ConvertTo-SetupLiteral -Text $action)
    if ($Step.RequiresRestart)
    {
        $text += ', [BrightYellow]then restart[/]'
    }
    return $text
}

function Write-SetupList
{
    # The steps folder as it stands, in run order, read without running any of it.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Steps
    )

    $rows = foreach ($step in $Steps)
    {
        $from = '[DarkGray]own[/]'
        if ($step.Template)
        {
            $from = ConvertTo-SetupLiteral -Text $step.Template
        }
        [pscustomobject]@{
            '#'  = Format-SetupOrder -Step $step
            Step = ConvertTo-SetupLiteral -Text $step.Name
            From = $from
            Does = Format-SetupStepAction -Step $step
        }
    }
    $tableArguments = $script:TableArguments
    Format-AnsiTable -Data @($rows) @tableArguments | Out-AnsiHost
}

# ── Dry run ──────────────────────────────────────────────────────────────────

function Get-SetupPlan
{
    # What each step's Test reports, behind one progress line. Tests only look, so this changes nothing.
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [object[]] $Steps
    )

    $plan = [System.Collections.Generic.List[object]]::new()
    $check = {
        param($Task)

        for ($index = 0; $index -lt $Steps.Count; $index++)
        {
            $result = Test-SetupStepDone -Step $Steps[$index]
            $plan.Add([pscustomobject]@{ Step = $Steps[$index]; Done = $result.Done; Error = $result.Error })
            $Task.Update($index + 1, $Steps.Count)
        }
    }
    Invoke-AnsiTask -Name ('Checking {0} steps' -f $Steps.Count) -ScriptBlock $check -ProgressShow Percent
    return $plan.ToArray()
}

function Write-SetupPlan
{
    # The dry run: what each step would do, from its Test and its code, and a line that sums it up.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Plan
    )

    $rows = foreach ($row in $Plan)
    {
        $would = '[DarkGray]skip, already done[/]'
        if (-not $row.Done)
        {
            $would = Format-SetupStepAction -Step $row.Step
        }
        if ($row.Error)
        {
            $reason = $row.Error
            if ($reason.Length -gt $script:ReasonLength)
            {
                $reason = '{0}...' -f $reason.Substring(0, $script:ReasonLength)
            }
            $would += ' [DarkGray](check failed: {0})[/]' -f (ConvertTo-SetupLiteral -Text $reason)
        }
        [pscustomobject]@{
            '#'   = Format-SetupOrder -Step $row.Step
            Step  = ConvertTo-SetupLiteral -Text $row.Step.Name
            Would = $would
        }
    }
    $tableArguments = $script:TableArguments
    Format-AnsiTable -Data @($rows) @tableArguments | Out-AnsiHost

    $pending = @($Plan | Where-Object -FilterScript { -not $_.Done })
    $restarts = @($pending | Where-Object -FilterScript { $_.Step.RequiresRestart }).Count
    $summary = 'Dry run: {0} of {1} steps would run, and {2} would restart the machine. Nothing ran.' -f
    $pending.Count, $Plan.Count, $restarts
    Write-SetupNote -Text $summary -Color 'BrightCyan'
}

# ── Results ──────────────────────────────────────────────────────────────────

function Write-SetupSummary
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Steps,
        [Parameter(Mandatory)] [hashtable] $State
    )

    if ($Steps.Count -eq 0)
    {
        return
    }

    $rows = foreach ($step in $Steps)
    {
        $result = $State.Results[$step.Id]
        $status = 'NotRun'
        $time = ''
        if ($result)
        {
            $status = $result.Status
            if ($result.Seconds -gt 0 -and $status -ne 'Skipped')
            {
                $time = Format-SetupDuration -Duration ([TimeSpan]::FromSeconds($result.Seconds))
            }
        }

        [pscustomobject]@{
            '#'    = Format-SetupOrder -Step $step
            Step   = ConvertTo-SetupLiteral -Text $step.Name
            Result = $script:ResultLabel[$status]
            Time   = $time
        }
    }
    Write-SetupBlankLine
    $tableArguments = $script:TableArguments
    Format-AnsiTable -Data @($rows) @tableArguments | Out-AnsiHost
}

function Write-SetupFailure
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $ErrorRecord,
        [AllowEmptyString()] [AllowNull()] [string] $LogFile
    )

    Write-SetupBlankLine
    Format-AnsiRule -Title '[BrightRed]Failed[/]' -Alignment Left -LineColor DarkGray | Out-AnsiHost
    Format-AnsiException -Exception $ErrorRecord | Out-AnsiHost
    if ($LogFile)
    {
        Format-AnsiText -Message ('[DarkGray]Log[/]  {0}' -f (ConvertTo-SetupLiteral -Text $LogFile)) | Out-AnsiHost
    }
}

function Wait-SetupClose
{
    # A window this run opened itself, elevated or resumed, stays open until a key is pressed, so its last screen
    # can be read. Unattended runs never wait for a key.
    [CmdletBinding()]
    param(
        [switch] $Unattended
    )

    if ($Unattended -or -not $env:PWSHSETUP_RERUN -or -not (Test-SetupInteractive))
    {
        return
    }
    Write-SetupBlankLine
    $null = Read-AnsiPause -Message 'Press any key to close'
}

Export-ModuleMember -Function Clear-SetupScreen, Write-SetupBlankLine, Write-SetupHeader, Write-SetupNote,
Write-SetupKeyLine, Read-SetupKey, Read-SetupConfirm, Write-SetupList, Get-SetupPlan, Write-SetupPlan,
Write-SetupSummary, Write-SetupFailure, Wait-SetupClose
