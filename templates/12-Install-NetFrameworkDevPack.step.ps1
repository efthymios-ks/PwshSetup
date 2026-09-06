#Requires -Version 7.2

# 12-Install-NetFrameworkDevPack.step.ps1
# Install .NET Framework 4.8.1 Developer Pack

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install .NET Framework 4.8.1 Developer Pack' -Order 12 `
    -Test {
        -not (Test-Path -LiteralPath (Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8.1'))
    } `
    -Action {
        Install-ChocoPackage -Name 'netfx-4.8.1-devpack'
    } `
    -RequiresRestart
