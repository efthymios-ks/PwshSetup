<#
.SYNOPSIS
    Public: Request-SetupRestart, a restart a step asks for while it runs.
#>
#Requires -Version 7.2

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Core.psm1') -DisableNameChecking

function Request-SetupRestart
{
    <#
    .SYNOPSIS
        Asks for a restart once the running step ends.
    .DESCRIPTION
        Without -Retry the step counts as done, and the run carries on with the next step after the restart.
        With -Retry the step could not do its work yet and runs again after the restart. A step that asks for a retry
        twice in a row fails.
        Outside a run it does nothing.
    .PARAMETER Retry
        Run this step again after the restart.
    .EXAMPLE
        if ($process.ExitCode -eq 3010) { Request-SetupRestart }
    .EXAMPLE
        Request-SetupRestart -Retry
    #>
    [CmdletBinding()]
    param(
        [switch] $Retry
    )

    $context = Get-SetupContext
    if ($Retry)
    {
        $context.RestartRequest = 'Retry'
        Write-SetupLogFile -Message 'Restart requested; this step runs again after it.'
        return
    }

    if ($context.RestartRequest -ne 'Retry')
    {
        $context.RestartRequest = 'After'
    }
    Write-SetupLogFile -Message 'Restart requested after this step.'
}

Export-ModuleMember -Function Request-SetupRestart
