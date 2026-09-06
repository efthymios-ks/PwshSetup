<#
.SYNOPSIS
    Public: Invoke-PwshSetup, runs a folder of setup steps and carries on across restarts.
#>
#Requires -Version 7.2

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Assert-SetupAdmin.psm1') -DisableNameChecking
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Core.psm1') -DisableNameChecking
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Steps.psm1') -DisableNameChecking
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'State.psm1') -DisableNameChecking
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Restart.psm1') -DisableNameChecking
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Shell.psm1') -DisableNameChecking

$script:AppTitle = 'PwshSetup'

function Invoke-PwshSetup
{
    <#
    .SYNOPSIS
        Runs the steps in a folder, in order, and carries on across restarts on its own.
    .DESCRIPTION
        Lists the folder's steps. F6 runs them and F7 dry-runs them, each after a y/n confirm; Esc quits.
        A run checks each step right before it and skips what is done.
        A step that needs a restart gets one: the run registers itself to start again at the next sign-in, counts down
        ten seconds (Esc cancels), restarts, and carries on with the next step without asking.
        A step that fails stops the run; the next run asks to carry on from it.
        Needs an elevated session, except with -WhatIf. Call Assert-SetupAdmin first.
        Logs go to %ProgramData%\PwshSetup\Logs, one file per run.
    .PARAMETER Path
        The steps folder. Every .ps1 in it is a step, run in the order of the number its name starts with.
    .PARAMETER LogPath
        Folder for the log files.
    .PARAMETER Unattended
        Run without the list and the confirm.
    .PARAMETER SkipRestart
        Note a needed restart and carry on without one.
    .PARAMETER ScriptPath
        Script the resume task starts after a restart. Defaults to the calling script.
    .PARAMETER Arguments
        Parameters the resume task passes to that script. Defaults to the calling script's bound parameters.
    .PARAMETER PassThru
        Return the outcome: Status (Finished, Failed, Restarting, Cancelled, DryRun), LogFile and Duration.
    .EXAMPLE
        Invoke-PwshSetup -Path (Join-Path -Path $PSScriptRoot -ChildPath 'steps')
    .EXAMPLE
        Invoke-PwshSetup -Path 'C:\Setup\steps' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Path,
        [ValidateNotNullOrEmpty()] [string] $LogPath = (Get-SetupDataPath -Name 'Logs'),
        [switch] $Unattended,
        [switch] $SkipRestart,
        [AllowEmptyString()] [string] $ScriptPath = $MyInvocation.PSCommandPath,
        [hashtable] $Arguments,
        [switch] $PassThru
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container))
    {
        throw ('Step folder not found: {0}' -f $Path)
    }
    $dryRun = [bool]$WhatIfPreference
    if (-not $dryRun -and -not (Test-SetupAdmin))
    {
        throw 'Invoke-PwshSetup needs an elevated session. Call Assert-SetupAdmin before it.'
    }
    if (-not $dryRun -and -not $Unattended -and -not (Test-SetupInteractive))
    {
        throw 'No console to show the list in. Pass -Unattended to run without it.'
    }

    if ($null -eq $Arguments)
    {
        $Arguments = @{}
        $caller = Get-PSCallStack | Select-Object -Skip 1 -First 1
        if ($caller)
        {
            foreach ($key in $caller.InvocationInfo.BoundParameters.Keys)
            {
                $Arguments[$key] = $caller.InvocationInfo.BoundParameters[$key]
            }
        }
    }

    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $runArguments = @{
        StepPath    = (Resolve-Path -LiteralPath $Path).ProviderPath
        LogPath     = $LogPath
        Unattended  = [bool]$Unattended
        SkipRestart = [bool]$SkipRestart
        DryRun      = $dryRun
        ScriptPath  = $ScriptPath
        Arguments   = $Arguments
    }
    try
    {
        $outcome = Invoke-SetupRun @runArguments
    }
    finally
    {
        Reset-SetupContext
    }

    if ($PassThru)
    {
        return $outcome
    }
}

# ── Run ──────────────────────────────────────────────────────────────────────

function Invoke-SetupRun
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $StepPath,
        [Parameter(Mandatory)] [string] $LogPath,
        [Parameter(Mandatory)] [bool] $Unattended,
        [Parameter(Mandatory)] [bool] $SkipRestart,
        [Parameter(Mandatory)] [bool] $DryRun,
        [AllowEmptyString()] [string] $ScriptPath,
        [hashtable] $Arguments
    )

    $rerun = @(([string]$env:PWSHSETUP_RERUN) -split ',' | Where-Object -FilterScript { $_ })
    if (-not $DryRun -and $rerun -contains 'resume')
    {
        Unregister-SetupResume
    }

    $header = @(
        , @('Steps', (ConvertTo-SetupLiteral -Text $StepPath))
        , @('Machine', ('{0}  [DarkGray]{1}[/]' -f $env:COMPUTERNAME, (ConvertTo-SetupLiteral -Text $env:USERNAME)))
    )

    Clear-SetupScreen
    try
    {
        $steps = @(Import-SetupStep -Path $StepPath)
    }
    catch
    {
        Write-SetupHeader -Item $header
        Write-SetupFailure -ErrorRecord $_
        Wait-SetupClose -Unattended:$Unattended
        return (New-SetupOutcome -Status 'Failed')
    }
    if ($steps.Count -eq 0)
    {
        Write-SetupHeader -Item $header
        Write-SetupNote -Text 'No step files in the folder.' -Color 'BrightYellow'
        return (New-SetupOutcome -Status 'Finished')
    }

    if ($DryRun)
    {
        Write-SetupHeader -Item $header
        Write-SetupPlan -Plan (Get-SetupPlan -Steps $steps)
        return (New-SetupOutcome -Status 'DryRun')
    }

    # ── Resume, or the list ──────────────────────────────────────────────────

    $state = Read-SetupState -StepPath $StepPath
    $resumed = $false
    if ($state)
    {
        if ((Test-SetupRestartedSince -State $state) -or $Unattended -or $rerun -contains 'resume')
        {
            $resumed = $true
        }
        else
        {
            Write-SetupHeader -Item $header
            $startedAt = (ConvertTo-SetupUtc -Value $state.StartedAt).ToLocalTime()
            $startedText = $startedAt.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)
            $prompt = 'Carry on with the unfinished run from {0}?' -f $startedText
            $answer = Read-AnsiConfirm -Prompt $prompt -Default $true
            if ($null -eq $answer)
            {
                return (New-SetupOutcome -Status 'Cancelled')
            }
            $resumed = [bool]$answer
            if (-not $resumed)
            {
                Remove-SetupState -StepPath $StepPath
                $state = $null
            }
        }
    }

    if (-not $resumed)
    {
        if (-not $Unattended -and -not (Wait-SetupGo -Steps $steps -Header $header))
        {
            Write-SetupNote -Text 'Nothing ran.' -Color 'DarkGray'
            return (New-SetupOutcome -Status 'Cancelled')
        }
        if (-not (Test-Path -LiteralPath $LogPath))
        {
            $null = New-Item -ItemType Directory -Path $LogPath -Force
        }
        $stateArguments = @{
            StepPath   = $StepPath
            ScriptPath = $ScriptPath
            LogFile    = Join-Path -Path $LogPath -ChildPath ('PwshSetup-{0}.log' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
            Selected   = @($steps | ForEach-Object -Process { $_.Id })
        }
        $state = New-SetupState @stateArguments
    }

    Clear-SetupScreen
    $runKind = 'started'
    $runText = 'started'
    if ($resumed)
    {
        $runKind = 'resumed'
        $runText = 'resumed  [DarkGray]{0} restart(s) so far[/]' -f $state.Restarts
    }
    $header += , @('Run', $runText)
    $header += , @('Log', (ConvertTo-SetupLiteral -Text $state.LogFile))
    Write-SetupHeader -Item $header

    $state.RestartingAt = $null
    Save-SetupState -State $state
    $argumentFile = Save-SetupArgument -StepPath $StepPath -Arguments $Arguments

    $context = Get-SetupContext
    $context.LogFile = $state.LogFile
    Write-SetupLogFile -Message ('Run {0} on {1} as {2}, steps in {3}.' -f $runKind, $env:COMPUTERNAME, $env:USERNAME, $StepPath)

    # ── Steps ────────────────────────────────────────────────────────────────

    $byId = @{}
    foreach ($step in $steps)
    {
        $byId[$step.Id] = $step
    }
    foreach ($id in @($state.Selected | Where-Object -FilterScript { -not $byId.ContainsKey($_) }))
    {
        Write-SetupLogFile -Message ('Step {0} has no file any more; left out.' -f $id) -Level 'WARN'
    }
    $runSteps = @($state.Selected | Where-Object -FilterScript { $byId.ContainsKey($_) } | ForEach-Object -Process { $byId[$_] })
    $remaining = @($runSteps | Where-Object -FilterScript {
            $result = $state.Results[$_.Id]
            -not $result -or $result.Status -notin 'Done', 'Skipped'
        })

    $run = [pscustomobject]@{
        Steps       = $remaining
        State       = $state
        SkipRestart = $SkipRestart
        RestartStep = $null
    }
    $stepScript = {
        param($Task)
        Invoke-SetupStepTask -Task $Task -Run $run
    }
    $tasks = foreach ($step in $remaining)
    {
        @{ Name = $step.Name; Script = $stepScript }
    }

    $failure = $null
    $null = Start-AnsiTitleAnimation -Text $script:AppTitle
    try
    {
        if (@($tasks).Count -gt 0)
        {
            Invoke-AnsiTask -Task @($tasks) -Show Both -ProgressShow Percent
        }
    }
    catch
    {
        $failure = $_
    }
    finally
    {
        Stop-AnsiTitleAnimation -Title $script:AppTitle
    }

    # ── Outcome ──────────────────────────────────────────────────────────────

    if ($failure)
    {
        Write-SetupLogFile -Message 'Run failed.' -Level 'ERROR'
        Write-SetupSummary -Steps $runSteps -State $state
        Write-SetupFailure -ErrorRecord $failure -LogFile $state.LogFile
        Write-SetupNote -Text 'Fix it and run setup again: it carries on from the failed step.' -Color 'DarkGray'
        Wait-SetupClose -Unattended:$Unattended
        return (New-SetupOutcome -Status 'Failed' -LogFile $state.LogFile -Duration (Get-SetupRunDuration -State $state))
    }

    if ($run.RestartStep)
    {
        Write-SetupBlankLine
        if (-not $state.ScriptPath)
        {
            Save-SetupState -State $state
            Write-SetupNote -Text 'Restart the machine, then run setup again to carry on.' -Color 'BrightYellow'
            return (New-SetupOutcome -Status 'Cancelled' -LogFile $state.LogFile -Duration (Get-SetupRunDuration -State $state))
        }

        $state.Restarts++
        $state.RestartingAt = (Get-Date).ToUniversalTime().ToString('o')
        Save-SetupState -State $state
        Register-SetupResume -ScriptPath $state.ScriptPath -ArgumentFile $argumentFile
        if (Restart-SetupComputer -StepName $run.RestartStep.Name)
        {
            return (New-SetupOutcome -Status 'Restarting' -LogFile $state.LogFile -Duration (Get-SetupRunDuration -State $state))
        }

        Unregister-SetupResume
        $state.Restarts--
        $state.RestartingAt = $null
        Save-SetupState -State $state
        Write-SetupNote -Text 'Restart cancelled. Restart the machine, then run setup again to carry on.' -Color 'BrightYellow'
        Wait-SetupClose -Unattended:$Unattended
        return (New-SetupOutcome -Status 'Cancelled' -LogFile $state.LogFile -Duration (Get-SetupRunDuration -State $state))
    }

    $duration = Get-SetupRunDuration -State $state
    $elapsed = Format-SetupDuration -Duration $duration
    Write-SetupLogFile -Message 'Run finished.'
    Write-SetupSummary -Steps $runSteps -State $state
    Remove-SetupState -StepPath $StepPath
    Write-SetupBlankLine
    Write-SetupNote -Text ('Setup finished in {0}, with {1} restart(s).' -f $elapsed, $state.Restarts) -Color 'BrightGreen'
    Format-AnsiText -Message ('[DarkGray]Log[/]  {0}' -f (ConvertTo-SetupLiteral -Text $state.LogFile)) | Out-AnsiHost
    Wait-SetupClose -Unattended:$Unattended
    return (New-SetupOutcome -Status 'Finished' -LogFile $state.LogFile -Duration $duration)
}

function Wait-SetupGo
{
    # The list screen: F6 runs and F7 dry-runs, each after a y/n; Esc quits. $true once a run is confirmed.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [object[]] $Steps,
        [Parameter(Mandatory)] [object[]] $Header
    )

    while ($true)
    {
        Clear-SetupScreen
        Write-SetupHeader -Item $Header
        Write-SetupKeyLine -Key @('F6 Run', 'F7 Dry run', 'Esc Quit')
        Write-SetupList -Steps $Steps

        $entered = Read-SetupKey -Key @('F6', 'F7')
        if ($entered.Action -eq 'Back')
        {
            return $false
        }
        if ($entered.Action -ne 'Key')
        {
            continue
        }

        Write-SetupBlankLine
        if ($entered.Key -eq 'F6')
        {
            if (Read-SetupConfirm -Prompt ('Run {0} steps?' -f $Steps.Count))
            {
                return $true
            }
            continue
        }

        if (Read-SetupConfirm -Prompt ('Dry run {0} steps?' -f $Steps.Count))
        {
            Write-SetupBlankLine
            Write-SetupPlan -Plan (Get-SetupPlan -Steps $Steps)
            Write-SetupBlankLine
            $null = Read-AnsiPause -Message 'Press any key to go back to the list'
        }
    }
}

function New-SetupOutcome
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateSet('Finished', 'Failed', 'Restarting', 'Cancelled', 'DryRun')] [string] $Status,
        [AllowEmptyString()] [string] $LogFile = '',
        [TimeSpan] $Duration = [TimeSpan]::Zero
    )

    return [pscustomobject]@{
        PSTypeName = 'PwshSetup.Outcome'
        Status     = $Status
        LogFile    = $LogFile
        Duration   = $Duration
    }
}

function Get-SetupRunDuration
{
    # From the run's first start, so the time spent across its restarts counts too.
    [CmdletBinding()]
    [OutputType([TimeSpan])]
    param(
        [Parameter(Mandatory)] [hashtable] $State
    )

    return ((Get-Date).ToUniversalTime() - (ConvertTo-SetupUtc -Value $State.StartedAt))
}

# ── Step ─────────────────────────────────────────────────────────────────────

function Invoke-SetupStepTask
{
    # One step inside Invoke-AnsiTask: checks it, since an earlier step may have done its work, runs it, records the
    # result, and stops the run when it needs a restart.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Task,
        [Parameter(Mandatory)] [pscustomobject] $Run
    )

    $step = $Run.Steps[$Task.Index]
    $state = $Run.State
    $context = Get-SetupContext
    $context.Task = $Task
    $context.StepId = $step.Id
    $context.RestartRequest = $null
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-SetupLogFile -Message ('Started: {0}' -f $step.Name)

    try
    {
        $check = Test-SetupStepDone -Step $step
        if ($check.Error)
        {
            Write-SetupLogFile -Message ('Check failed, so the step runs: {0}' -f $check.Error) -Level 'WARN'
        }
        if ($check.Done)
        {
            Set-SetupStepResult -State $state -Id $step.Id -Status 'Skipped' -Duration $watch.Elapsed
            Write-SetupLogFile -Message 'Already done, skipped.'
            $Task.Skip('already done')
            return
        }

        Invoke-SetupStepAction -Step $step
        $request = $context.RestartRequest

        if ($request -eq 'Retry')
        {
            $tries = 1
            if ($state.Retries.ContainsKey($step.Id))
            {
                $tries = [int]$state.Retries[$step.Id] + 1
            }
            if ($tries -gt 1)
            {
                throw ('{0} still waits for a restart after one. Restart the machine and run setup again.' -f $step.Name)
            }
            $state.Retries[$step.Id] = $tries
            Set-SetupStepResult -State $state -Id $step.Id -Status 'Retry' -Duration $watch.Elapsed
            if ($Run.SkipRestart)
            {
                $Task.Skip('needs a restart first')
                return
            }
            $Run.RestartStep = $step
            $Task.Stop('restart, then again')
            return
        }

        Set-SetupStepResult -State $state -Id $step.Id -Status 'Done' -Duration $watch.Elapsed
        Write-SetupLogFile -Message ('Done in {0}.' -f (Format-SetupDuration -Duration $watch.Elapsed))
        if ($step.RequiresRestart -or $request -eq 'After')
        {
            if ($Run.SkipRestart)
            {
                $Task.Write('restart skipped')
                Write-SetupLogFile -Message 'Restart skipped.' -Level 'WARN'
                return
            }
            $Run.RestartStep = $step
            $Task.Stop('restart')
        }
    }
    catch
    {
        Set-SetupStepResult -State $state -Id $step.Id -Status 'Failed' -Duration $watch.Elapsed -Reason $_.Exception.Message
        Write-SetupLogFile -Message ($_ | Out-String) -Level 'ERROR'
        throw
    }
    finally
    {
        Save-SetupState -State $state
        $context.Task = $null
        $context.StepId = $null
    }
}

function Invoke-SetupStepAction
{
    # Output, errors and warnings of the Action go to the log, never between the progress lines.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Step
    )

    & $Step.Action 2>&1 3>&1 | ForEach-Object -Process { Write-SetupStepOutput -Record $_ }
}

function Write-SetupStepOutput
{
    # Native commands write progress to stderr, so their error records are output, not errors.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] [object] $Record
    )

    if ($null -eq $Record)
    {
        return
    }
    if ($Record -is [System.Management.Automation.WarningRecord])
    {
        Write-SetupLogFile -Message $Record.Message -Level 'WARN'
        return
    }
    if ($Record -is [System.Management.Automation.ErrorRecord])
    {
        $level = 'ERROR'
        if ($Record.FullyQualifiedErrorId -like 'NativeCommandError*')
        {
            $level = 'OUTPUT'
        }
        Write-SetupLogFile -Message $Record.ToString() -Level $level
        return
    }
    Write-SetupLogFile -Message ($Record | Out-String -Width 200) -Level 'OUTPUT'
}

Export-ModuleMember -Function Invoke-PwshSetup
