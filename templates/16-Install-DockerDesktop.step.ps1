#Requires -Version 7.2

# 16-Install-DockerDesktop.step.ps1
# Install Docker Desktop

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install Docker Desktop' -Order 16 `
    -Test {
        -not (Test-SetupCommand 'docker')
    } `
    -Action {
        Install-ChocoPackage -Name 'docker-desktop'
    } `
    -RequiresRestart
