#Requires -Version 7.2

# 19-Install-K9s.step.ps1
# Install k9s

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install k9s' -Order 19 `
    -Test {
        -not (Test-SetupCommand 'k9s')
    } `
    -Action {
        Install-ChocoPackage -Name 'k9s'

        Sync-ChocoEnvironment
    }
