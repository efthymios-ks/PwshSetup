#Requires -Version 7.2

# 11-Install-VisualStudio2022.step.ps1
# Install Visual Studio 2022 Community

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install Visual Studio 2022 Community' -Order 11 `
    -Test {
        -not (Test-Path -LiteralPath (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022\Community'))
    } `
    -Action {
        Install-ChocoPackage -Name 'visualstudio2022community' -AdditionalArgument @('--package-parameters', '--add Microsoft.VisualStudio.Workload.NetWeb --add Microsoft.VisualStudio.Workload.ManagedDesktop --includeRecommended')
    } `
    -RequiresRestart
