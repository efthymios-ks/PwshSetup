<#
.SYNOPSIS
    Installs Visual Studio Code for every user of the machine.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install Visual Studio Code'
    Test   = { Test-SetupCommand -Name 'code' }
    Action = { Install-ChocoPackage -Name 'vscode' }
}
New-SetupStep @step
