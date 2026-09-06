#Requires -Version 7.2

# 17-Install-PodmanCli.step.ps1
# Install Podman CLI

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install Podman CLI' -Order 17 `
    -Test {
        -not (Test-SetupCommand 'podman')
    } `
    -Action {
        Install-ChocoPackage -Name 'podman-cli'

        Sync-ChocoEnvironment
    }
