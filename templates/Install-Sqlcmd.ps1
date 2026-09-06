<#
.SYNOPSIS
    Installs sqlcmd, the cross-platform SQL Server command line.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install sqlcmd'
    Test   = { Test-SetupCommand -Name 'sqlcmd' }
    Action = { Install-ChocoPackage -Name 'sqlcmd' }
}
New-SetupStep @step
