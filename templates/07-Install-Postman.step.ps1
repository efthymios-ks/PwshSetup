#Requires -Version 7.2

# 07-Install-Postman.step.ps1
# Install Postman

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install Postman' -Order 7 `
    -Test {
        -not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Postman\Postman.exe'))
    } `
    -Action {
        Install-ChocoPackage -Name 'postman'
    }
