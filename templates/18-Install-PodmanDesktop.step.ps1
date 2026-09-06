#Requires -Version 7.2

# 18-Install-PodmanDesktop.step.ps1
# Install Podman Desktop

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install Podman Desktop' -Order 18 `
    -Test {
        -not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Programs\podman-desktop\Podman Desktop.exe'))
    } `
    -Action {
        Install-ChocoPackage -Name 'podman-desktop'
    }
