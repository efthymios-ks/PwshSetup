#Requires -Version 7.2

# 03-Install-GoogleChrome.step.ps1
# Install Google Chrome

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install Google Chrome' -Order 3 `
    -Test {
        -not (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'))
    } `
    -Action {
        Install-ChocoPackage -Name 'googlechrome' -AdditionalArgument @('--ignore-checksums')
    }
