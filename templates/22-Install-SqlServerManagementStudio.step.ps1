#Requires -Version 7.2

# 22-Install-SqlServerManagementStudio.step.ps1
# Install SQL Server Management Studio

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install SQL Server Management Studio' -Order 22 `
    -Test {
        -not (Test-Path -LiteralPath (Join-Path ${env:ProgramFiles(x86)} 'Microsoft SQL Server Management Studio 19'))
    } `
    -Action {
        Install-ChocoPackage -Name 'sql-server-management-studio'
    }
