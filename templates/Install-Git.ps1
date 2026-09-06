<#
.SYNOPSIS
    Installs Git.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install Git'
    Test   = { Test-SetupCommand -Name 'git' }
    Action = { Install-ChocoPackage -Name 'git' }
}
New-SetupStep @step
