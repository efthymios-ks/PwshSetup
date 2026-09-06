<#
.SYNOPSIS
    Installs Docker Desktop. Put the WSL step before it.
#>
[CmdletBinding()]
param()

$step = @{
    Name            = 'Install Docker Desktop'
    RequiresRestart = $true
    Test            = { Test-SetupProgram -Name 'Docker Desktop' }
    Action          = { Install-ChocoPackage -Name 'docker-desktop' }
}
New-SetupStep @step
