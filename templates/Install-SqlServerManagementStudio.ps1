<#
.SYNOPSIS
    Installs the latest SQL Server Management Studio.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install SQL Server Management Studio'
    Test   = { Test-SetupProgram -Name '*SQL Server Management Studio*' }
    Action = { Install-ChocoPackage -Name 'sql-server-management-studio' }
}
New-SetupStep @step
