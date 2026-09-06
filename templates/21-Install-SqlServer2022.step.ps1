#Requires -Version 7.2

# 21-Install-SqlServer2022.step.ps1
# Install SQL Server 2022 Developer edition.
# The SA password is read from the SETUP_SQL_SA_PASSWORD environment variable — never
# written into the step, which is committed.

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

$instanceName = 'MSSQLSERVER'

New-SetupStep -Name 'Install SQL Server 2022' -Order 21 `
    -Test {
        -not (Get-Service -Name $instanceName -ErrorAction Ignore)
    } `
    -Action {
        $password = $env:SETUP_SQL_SA_PASSWORD

        if (-not $password) {
            throw 'Set SETUP_SQL_SA_PASSWORD before running this step.'
        }

        $parameters = "/INSTANCENAME=$instanceName /SAPWD=$password /SQLSYSADMINACCOUNTS=BUILTIN\ADMINISTRATORS /SECURITYMODE=SQL"

        Install-ChocoPackage -Name 'sql-server-2022' -AdditionalArgument @('--package-parameters', $parameters)
    } `
    -RequiresRestart
