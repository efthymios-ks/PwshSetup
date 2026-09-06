<#
.SYNOPSIS
    Internal: restarts that resume.
.DESCRIPTION
    Before restarting, the run registers a scheduled task that starts its script again at the next sign-in of the same
    user, elevated and on that user's desktop. The resumed run removes the task first thing.
#>
#Requires -Version 7.2

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Core.psm1') -DisableNameChecking

$script:ResumeTaskName = 'Resume'
$script:ResumeTaskPath = '\PwshSetup\'
$script:RestartCountdownSeconds = 10

function Register-SetupResume
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ScriptPath,
        [Parameter(Mandatory)] [string] $ArgumentFile
    )

    $quote = { param($Text) "'" + ($Text -replace "'", "''") + "'" }
    $command = @(
        '$env:PWSHSETUP_RERUN = ''resume'''
        ('Set-Location -LiteralPath {0}' -f (& $quote (Split-Path -Path $ScriptPath -Parent)))
        ('$p = Import-Clixml -LiteralPath {0}' -f (& $quote $ArgumentFile))
        ('& {0} @p' -f (& $quote $ScriptPath))
        'exit $LASTEXITCODE'
    ) -join "`n"
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))

    $pwsh = (Get-Process -Id $PID).Path
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    $actionArguments = @{
        Execute  = $pwsh
        Argument = ('-NoProfile -ExecutionPolicy Bypass -EncodedCommand {0}' -f $encoded)
    }
    $settingsArguments = @{
        AllowStartIfOnBatteries    = $true
        DontStopIfGoingOnBatteries = $true
        ExecutionTimeLimit         = [TimeSpan]::Zero
        MultipleInstances          = 'IgnoreNew'
    }
    $taskArguments = @{
        TaskName    = $script:ResumeTaskName
        TaskPath    = $script:ResumeTaskPath
        Action      = New-ScheduledTaskAction @actionArguments
        Trigger     = New-ScheduledTaskTrigger -AtLogOn -User $user
        Principal   = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
        Settings    = New-ScheduledTaskSettingsSet @settingsArguments
        Force       = $true
        ErrorAction = 'Stop'
    }
    $null = Register-ScheduledTask @taskArguments

    Write-SetupLogFile -Message ('Registered the resume task for {0}.' -f $user)
}

function Unregister-SetupResume
{
    [CmdletBinding()]
    param()

    $task = Get-ScheduledTask -TaskName $script:ResumeTaskName -TaskPath $script:ResumeTaskPath -ErrorAction Ignore
    if ($task)
    {
        Unregister-ScheduledTask -TaskName $script:ResumeTaskName -TaskPath $script:ResumeTaskPath -Confirm:$false
    }
}

function Restart-SetupComputer
{
    # $true when the restart goes ahead, $false when Esc cancels it. With nobody at the keyboard the countdown runs out
    # and the restart goes ahead.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $StepName
    )

    $stepText = ConvertTo-SetupLiteral -Text $StepName
    $message = '[BrightYellow]{0} needs a restart.[/] [DarkGray]Setup carries on after the next sign-in.[/]' -f $stepText
    Format-AnsiText -Message $message | Out-AnsiHost

    if (Test-SetupInteractive)
    {
        $pauseArguments = @{
            Message        = 'Restarting. Any key restarts now, Esc cancels'
            TimeoutSeconds = $script:RestartCountdownSeconds
            ShowCountdown  = $true
            KeepMessage    = $true
            MessageColor   = 'BrightYellow'
        }
        $answer = Read-AnsiPause @pauseArguments
        if ($false -eq $answer)
        {
            Write-SetupLogFile -Message 'Restart cancelled.' -Level 'WARN'
            return $false
        }
    }

    Write-SetupLogFile -Message 'Restarting.'
    # shutdown.exe, not Restart-Computer: Restart-Computer goes through WMI, which can time out while the machine is
    # still starting its services. shutdown.exe asks the system directly and returns at once.
    & shutdown.exe /r /t 0 /f
    if ($LASTEXITCODE -ne 0)
    {
        throw ('shutdown.exe exited with code {0} while requesting restart.' -f $LASTEXITCODE)
    }
    return $true
}

Export-ModuleMember -Function Register-SetupResume, Unregister-SetupResume, Restart-SetupComputer
