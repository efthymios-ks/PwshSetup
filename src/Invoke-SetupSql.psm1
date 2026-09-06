<#
.SYNOPSIS
    Public: Invoke-SetupSql, Invoke-SetupSqlScalar and Test-SetupSqlDatabase, the SQL Server calls a step needs.
.DESCRIPTION
    Values travel as parameters, never concatenated into the statement.
#>
#Requires -Version 7.2

function New-SetupSqlCommand
{
    # Callers dispose the connection.
    [CmdletBinding()]
    [OutputType([System.Data.SqlClient.SqlCommand])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ConnectionString,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Sql,
        [hashtable] $Parameter = @{}
    )

    $connection = [System.Data.SqlClient.SqlConnection]::new($ConnectionString)
    $command = $connection.CreateCommand()
    $command.CommandText = $Sql
    foreach ($entry in $Parameter.GetEnumerator())
    {
        $null = $command.Parameters.AddWithValue($entry.Key, $entry.Value)
    }
    return $command
}

function Invoke-SetupSql
{
    <#
    .SYNOPSIS
        Runs a statement and returns the rows it affected.
    .PARAMETER ConnectionString
        Where to run it.
    .PARAMETER Sql
        The statement, with @name placeholders for values.
    .PARAMETER Parameter
        The values, keyed by placeholder.
    .EXAMPLE
        Invoke-SetupSql -ConnectionString $connectionString -Sql 'DELETE FROM Cache WHERE Region = @region' -Parameter @{ '@region' = 'eu' }
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ConnectionString,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Sql,
        [hashtable] $Parameter = @{}
    )

    $command = New-SetupSqlCommand -ConnectionString $ConnectionString -Sql $Sql -Parameter $Parameter
    try
    {
        $command.Connection.Open()
        return $command.ExecuteNonQuery()
    }
    finally
    {
        $command.Connection.Dispose()
    }
}

function Invoke-SetupSqlScalar
{
    <#
    .SYNOPSIS
        Runs a query and returns the first column of its first row.
    .PARAMETER ConnectionString
        Where to run it.
    .PARAMETER Sql
        The query, with @name placeholders for values.
    .PARAMETER Parameter
        The values, keyed by placeholder.
    .EXAMPLE
        Invoke-SetupSqlScalar -ConnectionString $connectionString -Sql 'SELECT COUNT(*) FROM sys.tables'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ConnectionString,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Sql,
        [hashtable] $Parameter = @{}
    )

    $command = New-SetupSqlCommand -ConnectionString $ConnectionString -Sql $Sql -Parameter $Parameter
    try
    {
        $command.Connection.Open()
        return $command.ExecuteScalar()
    }
    finally
    {
        $command.Connection.Dispose()
    }
}

function Test-SetupSqlDatabase
{
    <#
    .SYNOPSIS
        $true when the database a connection string names exists on its server.
    .DESCRIPTION
        Connects to master on the same server, so it works before the database is created.
    .PARAMETER ConnectionString
        A connection string with Database or Initial Catalog.
    .EXAMPLE
        Test-SetupSqlDatabase -ConnectionString 'Server=.;Database=Shop;Integrated Security=True;TrustServerCertificate=True'
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ConnectionString
    )

    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($ConnectionString)
    $database = $builder.InitialCatalog
    if (-not $database)
    {
        throw 'The connection string names no Database or Initial Catalog.'
    }
    # The 'Initial Catalog' key, not the InitialCatalog setter, which throws "Keyword not supported" in this client.
    $builder['Initial Catalog'] = 'master'

    $scalarArguments = @{
        ConnectionString = $builder.ConnectionString
        Sql              = 'SELECT COUNT(*) FROM sys.databases WHERE name = @name'
        Parameter        = @{ '@name' = $database }
    }
    return ([int](Invoke-SetupSqlScalar @scalarArguments) -gt 0)
}

Export-ModuleMember -Function Invoke-SetupSql, Invoke-SetupSqlScalar, Test-SetupSqlDatabase
