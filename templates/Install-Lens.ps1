<#
.SYNOPSIS
    Installs Lens, the Kubernetes desktop, for every user of the machine.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install Lens'
    Test   = { Test-SetupProgram -Name 'Lens*' }
    Action = { Install-ChocoPackage -Name 'lens' }
}
New-SetupStep @step
