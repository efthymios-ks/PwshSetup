<#
.SYNOPSIS
    Installs Firefox.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install Firefox'
    Test   = { Test-SetupProgram -Name 'Mozilla Firefox*' }
    Action = { Install-ChocoPackage -Name 'firefox' }
}
New-SetupStep @step
