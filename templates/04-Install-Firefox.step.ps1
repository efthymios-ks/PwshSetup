#Requires -Version 7.2

# 04-Install-Firefox.step.ps1
# Install Firefox

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install Firefox' -Order 4 `
    -Test {
        -not (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Mozilla Firefox\firefox.exe'))
    } `
    -Action {
        Install-ChocoPackage -Name 'firefox'
    }
