<#
.SYNOPSIS
    Installs Devolutions Remote Desktop Manager.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install Remote Desktop Manager'
    Test   = { Test-SetupProgram -Name 'Remote Desktop Manager*' }
    Action = { Install-ChocoPackage -Name 'rdm' }
}
New-SetupStep @step
