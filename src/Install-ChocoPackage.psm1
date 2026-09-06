<#
.SYNOPSIS
    Public: Install-ChocoPackage and Invoke-ChocoCommand, Chocolatey for steps.
.DESCRIPTION
    Success is decided by Chocolatey's exit code, never by searching its output.
    A package that asks for a restart gets one after its step, and a package Chocolatey refuses because a restart is
    pending runs again after that restart.
#>
#Requires -Version 7.2

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Core.psm1') -DisableNameChecking
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Request-SetupRestart.psm1') -DisableNameChecking
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Update-SetupEnvironment.psm1') -DisableNameChecking
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Write-SetupLog.psm1') -DisableNameChecking

# Chocolatey's own contract: 1641 and 3010 installed and want a restart, 350 and 1604 did nothing because one is pending.
$script:ChocoRestartExitCodes = @(1641, 3010)
$script:ChocoPendingExitCodes = @(350, 1604)
$script:ChocoTailLines = 15

function Invoke-ChocoCommand
{
    <#
    .SYNOPSIS
        Runs choco with the arguments given, and returns its exit code and output.
    .DESCRIPTION
        The output goes to the run log in full; the screen shows the command line only.
        Throws when Chocolatey is not installed.
    .PARAMETER ArgumentList
        The arguments, one per item.
    .EXAMPLE
        Invoke-ChocoCommand -ArgumentList 'feature', 'enable', '--name=exitOnRebootDetected'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string[]] $ArgumentList
    )

    $choco = Get-Command -Name 'choco' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if (-not $choco)
    {
        throw 'Chocolatey is not installed. Put the Chocolatey step before this one.'
    }

    Write-SetupLog -Message ('choco {0}' -f ($ArgumentList -join ' '))
    $output = & $choco.Source @ArgumentList 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    Write-SetupLogFile -Message $output -Level 'OUTPUT'

    return [pscustomobject]@{
        PSTypeName = 'PwshSetup.ChocoResult'
        ExitCode   = $exitCode
        Output     = $output.TrimEnd()
    }
}

function Install-ChocoPackage
{
    <#
    .SYNOPSIS
        Installs one Chocolatey package, and throws when it fails.
    .DESCRIPTION
        Exit 0 is done. 1641 and 3010 are done and ask for a restart after the step.
        350 and 1604 mean Chocolatey saw a pending restart and installed nothing: the step runs again after a restart.
        Anything else throws with the last lines of Chocolatey's output.
        The session environment is reloaded after an install, so the next step finds the new commands.
    .PARAMETER Name
        The package id.
    .PARAMETER Version
        A version to pin. The latest when omitted.
    .PARAMETER AdditionalArgument
        More choco arguments, one per item, such as '--params', '/NoDesktopShortcut'.
    .PARAMETER PassThru
        Return the result object.
    .EXAMPLE
        Install-ChocoPackage -Name 'git'
    .EXAMPLE
        Install-ChocoPackage -Name 'googlechrome' -AdditionalArgument '--ignore-checksums'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Name,
        [ValidateNotNullOrEmpty()] [string] $Version,
        [string[]] $AdditionalArgument = @(),
        [switch] $PassThru
    )

    $arguments = @('install', $Name, '--yes', '--no-progress')
    if ($Version)
    {
        $arguments += @('--version', $Version)
    }
    $arguments += $AdditionalArgument

    $result = Invoke-ChocoCommand -ArgumentList $arguments
    if ($result.ExitCode -in $script:ChocoPendingExitCodes)
    {
        Write-SetupLog -Message ('Chocolatey sees a pending restart; {0} installs after it.' -f $Name) -Level Warning
        Request-SetupRestart -Retry
    }
    elseif ($result.ExitCode -in $script:ChocoRestartExitCodes)
    {
        Write-SetupLog -Message ('{0} installed, and asks for a restart.' -f $Name)
        Request-SetupRestart
        Update-SetupEnvironment
    }
    elseif ($result.ExitCode -eq 0)
    {
        Write-SetupLog -Message ('{0} installed.' -f $Name)
        Update-SetupEnvironment
    }
    else
    {
        $tail = ($result.Output -split '\r?\n' | Select-Object -Last $script:ChocoTailLines) -join [Environment]::NewLine
        throw ('choco install {0} failed with exit code {1}.{2}{3}' -f $Name, $result.ExitCode, [Environment]::NewLine, $tail)
    }

    if ($PassThru)
    {
        return $result
    }
}

Export-ModuleMember -Function Invoke-ChocoCommand, Install-ChocoPackage
