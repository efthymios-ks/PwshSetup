<#
.SYNOPSIS
    Installs the new Microsoft Teams for every user of the machine.
.NOTES
    Teams ships as an app package provisioned for all users, so it is not listed with the classic programs.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install Microsoft Teams'
    Test   = {
        $provisioned = Get-AppxProvisionedPackage -Online | Where-Object -FilterScript { $_.DisplayName -eq 'MSTeams' }
        [bool]$provisioned
    }
    Action = { Install-ChocoPackage -Name 'microsoft-teams-new-bootstrapper' }
}
New-SetupStep @step
