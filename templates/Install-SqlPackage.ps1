<#
.SYNOPSIS
    Installs SqlPackage, to deploy and export SQL Server databases.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install SqlPackage'
    Test   = { Test-SetupCommand -Name 'sqlpackage' }
    Action = { Install-ChocoPackage -Name 'sqlpackage' }
}
New-SetupStep @step
