<#
.SYNOPSIS
    Installs WinRAR.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install WinRAR'
    Test   = { Test-SetupProgram -Name 'WinRAR*' }
    Action = { Install-ChocoPackage -Name 'winrar' }
}
New-SetupStep @step
