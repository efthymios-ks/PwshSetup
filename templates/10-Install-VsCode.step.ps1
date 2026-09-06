#Requires -Version 7.2

# 10-Install-VsCode.step.ps1
# Install Visual Studio Code

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install Visual Studio Code' -Order 10 `
    -Test {
        -not (Test-SetupCommand 'code')
    } `
    -Action {
        Install-ChocoPackage -Name 'vscode'

        Sync-ChocoEnvironment
    }
