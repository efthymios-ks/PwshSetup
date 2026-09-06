<#
.SYNOPSIS
    Installs Postman for the user running setup.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install Postman'
    Test   = { Test-SetupProgram -Name 'Postman*' }
    Action = { Install-ChocoPackage -Name 'postman' }
}
New-SetupStep @step
