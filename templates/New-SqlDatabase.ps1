<#
.SYNOPSIS
    Creates a SQL Server database when it is missing. Put a SQL Server step before it.
.PARAMETER ConnectionString
    Names the server and the database. Keep credentials out of it: Integrated Security signs in as the user running
    setup.
.EXAMPLE
    Use-SetupTemplate -Name 'New-SqlDatabase' -Parameter @{ ConnectionString = 'Server=.;Database=Shop;Integrated Security=True;TrustServerCertificate=True' }
#>
[CmdletBinding()]
param(
    [string] $ConnectionString
)

if (-not $ConnectionString)
{
    throw 'Pass the database: -Parameter @{ ConnectionString = ''Server=.;Database=...;Integrated Security=True'' }.'
}
$database = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($ConnectionString).InitialCatalog

$step = @{
    Name   = ('Create database {0}' -f $database)
    Test   = { Test-SetupSqlDatabase -ConnectionString $ConnectionString }
    Action = {
        # The 'Initial Catalog' key, not the InitialCatalog setter, which throws "Keyword not supported" in this client.
        $builder =[System.Data.SqlClient.SqlConnectionStringBuilder]::new($ConnectionString)
        $builder['Initial Catalog'] = 'master'
        $sqlArguments = @{
            ConnectionString = $builder.ConnectionString
            Sql              = 'DECLARE @sql nvarchar(max) = N''CREATE DATABASE '' + QUOTENAME(@name); EXEC (@sql);'
            Parameter        = @{ '@name' = $database }
        }
        $null = Invoke-SetupSql @sqlArguments
        Write-SetupLog -Message ('Created {0}.' -f $database)
    }
}
New-SetupStep @step
