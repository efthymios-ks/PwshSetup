<#
.SYNOPSIS
    Installs Podman Desktop.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install Podman Desktop'
    Test   = { Test-SetupProgram -Name 'Podman Desktop*' }
    Action = { Install-ChocoPackage -Name 'podman-desktop' }
}
New-SetupStep @step
