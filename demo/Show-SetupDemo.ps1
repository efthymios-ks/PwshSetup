<#
.SYNOPSIS
    Runs the demo steps from the source tree, to see a run without installing anything.
.DESCRIPTION
    The steps only wait, write log lines, ask for a restart and fail on request. Restarts are skipped.
    Needs administrator rights like any run: Assert-SetupAdmin reruns it elevated.
.PARAMETER Fail
    Make the last step fail, to see the failure screen and the carry-on prompt on the next run.
.PARAMETER DryRun
    The dry run only, the same as Invoke-PwshSetup -WhatIf.
.EXAMPLE
    .\demo\Show-SetupDemo.ps1
.EXAMPLE
    .\demo\Show-SetupDemo.ps1 -Fail
.EXAMPLE
    .\demo\Show-SetupDemo.ps1 -DryRun
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch] $Fail,
    [switch] $DryRun
)

if (-not (Get-Module -ListAvailable -Name PwshAnsi))
{
    Install-Module -Name PwshAnsi -Scope CurrentUser -Force
}
Import-Module -Name PwshAnsi
Assert-PwshAnsi

$sourceRoot = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src'
Import-Module -Name (Join-Path -Path $sourceRoot -ChildPath 'Assert-SetupAdmin.psm1') -DisableNameChecking
if (-not $DryRun)
{
    Assert-SetupAdmin
}

$publicModules = @('New-SetupStep', 'Use-SetupTemplate', 'Write-SetupLog', 'Request-SetupRestart', 'Test-SetupCommand', 'Invoke-PwshSetup')
foreach ($name in $publicModules)
{
    Import-Module -Name (Join-Path -Path $sourceRoot -ChildPath ('{0}.psm1' -f $name)) -DisableNameChecking
}

if ($Fail)
{
    $env:PWSHSETUP_DEMO_FAIL = '1'
}
else
{
    Remove-Item -Path 'env:PWSHSETUP_DEMO_FAIL' -ErrorAction Ignore
}

Invoke-PwshSetup -Path (Join-Path -Path $PSScriptRoot -ChildPath 'steps') -SkipRestart -WhatIf:$DryRun
