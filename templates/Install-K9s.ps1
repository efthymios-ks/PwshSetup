<#
.SYNOPSIS
    Installs k9s, the Kubernetes terminal UI.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install k9s'
    Test   = { Test-SetupCommand -Name 'k9s' }
    Action = { Install-ChocoPackage -Name 'k9s' }
}
New-SetupStep @step
