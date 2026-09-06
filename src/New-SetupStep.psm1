<#
.SYNOPSIS
    Public: New-SetupStep, the object every step file returns.
#>
#Requires -Version 7.2

function New-SetupStep
{
    <#
    .SYNOPSIS
        Describes one setup step. A step file returns exactly one.
    .DESCRIPTION
        Test says whether the step is already done: $true skips it. Omit it and the step always runs.
        Action does the work. Throwing fails the step and stops the run.
        RequiresRestart restarts the machine once Action is done, and the run carries on with the next step after the
        next sign-in.
        The run order comes from the number the file name starts with.
    .PARAMETER Name
        What the screen and the log call the step.
    .PARAMETER Action
        The work.
    .PARAMETER Test
        $true when the work is already done.
    .PARAMETER RequiresRestart
        Restart once Action is done.
    .EXAMPLE
        New-SetupStep -Name 'Install Git' -Test { Test-SetupCommand -Name 'git' } -Action { Install-ChocoPackage -Name 'git' }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Name,
        [Parameter(Mandatory)] [ValidateNotNull()] [scriptblock] $Action,
        [ValidateNotNull()] [scriptblock] $Test,
        [switch] $RequiresRestart
    )

    return [pscustomobject]@{
        PSTypeName      = 'PwshSetup.Step'
        Id              = $null
        Order           = [int]::MaxValue
        Name            = $Name
        Test            = $Test
        Action          = $Action
        RequiresRestart = [bool]$RequiresRestart
        File            = $null
        Template        = $null
        Module          = $null
    }
}

Export-ModuleMember -Function New-SetupStep
