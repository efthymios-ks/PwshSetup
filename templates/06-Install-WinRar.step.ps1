#Requires -Version 7.2

# 06-Install-WinRar.step.ps1
# Install WinRAR

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install WinRAR' -Order 6 `
    -Test {
        -not (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'WinRAR\WinRAR.exe'))
    } `
    -Action {
        Install-ChocoPackage -Name 'winrar'
    }
