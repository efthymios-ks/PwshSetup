#Requires -Version 7.2

# 09-Install-RemoteDesktopManager.step.ps1
# Install Remote Desktop Manager

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install Remote Desktop Manager' -Order 9 `
    -Test {
        -not (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Devolutions\Remote Desktop Manager\RemoteDesktopManager.exe'))
    } `
    -Action {
        Install-ChocoPackage -Name 'rdm'
    }
