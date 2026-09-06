<#
.SYNOPSIS
    Installs NVM for Windows, to install and switch Node.js versions.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install NVM for Windows'
    Test   = { Test-SetupCommand -Name 'nvm' }
    Action = { Install-ChocoPackage -Name 'nvm' }
}
New-SetupStep @step
