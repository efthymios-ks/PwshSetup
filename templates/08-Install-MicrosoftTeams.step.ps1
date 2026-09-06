#Requires -Version 7.2

# 08-Install-MicrosoftTeams.step.ps1
# Install Microsoft Teams

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install Microsoft Teams' -Order 8 `
    -Test {
        -not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\Teams\current\Teams.exe'))
    } `
    -Action {
        Install-ChocoPackage -Name 'microsoft-teams'
    }
