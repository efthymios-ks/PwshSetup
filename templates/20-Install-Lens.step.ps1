#Requires -Version 7.2

# 20-Install-Lens.step.ps1
# Install Lens

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install Lens' -Order 20 `
    -Test {
        -not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Programs\Lens\Lens.exe'))
    } `
    -Action {
        Install-ChocoPackage -Name 'lens'
    }
