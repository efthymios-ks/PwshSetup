#Requires -Version 7.2

# 23-Install-Sqlcmd.step.ps1
# Install sqlcmd

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install sqlcmd' -Order 23 `
    -Test {
        -not (Test-SetupCommand 'sqlcmd')
    } `
    -Action {
        Install-ChocoPackage -Name 'sqlcmd'

        Sync-ChocoEnvironment
    }
