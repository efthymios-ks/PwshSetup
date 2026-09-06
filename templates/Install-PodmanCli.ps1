<#
.SYNOPSIS
    Installs the Podman CLI.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install Podman CLI'
    Test   = { Test-SetupCommand -Name 'podman' }
    Action = { Install-ChocoPackage -Name 'podman-cli' }
}
New-SetupStep @step
