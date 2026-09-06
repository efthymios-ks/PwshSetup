#Requires -Version 7.2

# 24-Install-SqlPackage.step.ps1
# Install SqlPackage

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install SqlPackage' -Order 24 `
    -Test {
        -not (Test-SetupCommand 'sqlpackage')
    } `
    -Action {
        Install-ChocoPackage -Name 'sqlpackage'

        Sync-ChocoEnvironment
    }
