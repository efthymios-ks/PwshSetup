#Requires -Version 7.2

# 02-Install-Git.step.ps1
# Install Git

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install Git' -Order 2 `
    -Test {
        -not (Test-SetupCommand 'git')
    } `
    -Action {
        Install-ChocoPackage -Name 'git'

        Sync-ChocoEnvironment
    }
