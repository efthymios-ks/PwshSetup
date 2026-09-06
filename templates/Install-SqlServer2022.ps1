<#
.SYNOPSIS
    Installs SQL Server 2022 Developer as the default instance, with Windows sign-in for the user running setup.
.NOTES
    For SQL sign-in as sa too, set a SETUP_SQL_SA_PASSWORD user environment variable before running setup:
    [Environment]::SetEnvironmentVariable('SETUP_SQL_SA_PASSWORD', '<password>', 'User')
    The password never goes in this file, which is committed. It must not contain spaces or quotes.
#>
[CmdletBinding()]
param()

$instanceName = 'MSSQLSERVER'

$step = @{
    Name            = 'Install SQL Server 2022 Developer'
    RequiresRestart = $true
    Test            = { [bool](Get-Service -Name $instanceName -ErrorAction Ignore) }
    Action          = {
        $password = [Environment]::GetEnvironmentVariable('SETUP_SQL_SA_PASSWORD', 'User')
        if (-not $password)
        {
            Install-ChocoPackage -Name 'sql-server-2022'
            return
        }
        $parameters = "'/SECURITYMODE:SQL /SAPWD:{0}'" -f $password
        Install-ChocoPackage -Name 'sql-server-2022' -AdditionalArgument '--params', $parameters
    }
}
New-SetupStep @step
