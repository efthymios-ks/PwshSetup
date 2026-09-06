<#
.SYNOPSIS
    Public: Write-SetupLog, a line in the run log that also shows under the running step.
#>
#Requires -Version 7.2

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Core.psm1') -DisableNameChecking

function Write-SetupLog
{
    <#
    .SYNOPSIS
        Writes a line to the run log, and shows it under the running step.
    .DESCRIPTION
        Inside a step the line goes to the log file and appears dimmed under the step on screen.
        Outside a run it only goes to the screen.
    .PARAMETER Message
        The line.
    .PARAMETER Level
        Info, Warning or Error. Warnings show yellow and errors red.
    .EXAMPLE
        Write-SetupLog -Message 'Hosts file updated.'
    .EXAMPLE
        Write-SetupLog -Message 'Nothing to copy.' -Level Warning
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [AllowEmptyString()] [string] $Message,
        [ValidateSet('Info', 'Warning', 'Error')] [string] $Level = 'Info'
    )

    process
    {
        $fileLevel = 'INFO'
        $color = $null
        if ($Level -eq 'Warning')
        {
            $fileLevel = 'WARN'
            $color = 'BrightYellow'
        }
        elseif ($Level -eq 'Error')
        {
            $fileLevel = 'ERROR'
            $color = 'BrightRed'
        }
        Write-SetupLogFile -Message $Message -Level $fileLevel

        $text = ConvertTo-SetupLiteral -Text $Message
        if ($color)
        {
            $text = '[{0}]{1}[/]' -f $color, $text
        }

        $task = (Get-SetupContext).Task
        if ($task)
        {
            $task.Write($text)
            return
        }
        Format-AnsiText -Message $text | Out-AnsiHost
    }
}

Export-ModuleMember -Function Write-SetupLog
