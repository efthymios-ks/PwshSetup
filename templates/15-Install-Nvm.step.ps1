#Requires -Version 7.2

# 15-Install-Nvm.step.ps1
# Install NVM for Windows

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install NVM for Windows' -Order 15 `
    -Test {
        -not (Test-SetupCommand 'nvm')
    } `
    -Action {
        Install-ChocoPackage -Name 'nvm' -AdditionalArgument @('--allow-downgrade')

        Sync-ChocoEnvironment
    }
