#Requires -Version 7.2

# Invoke-SetupSql.psm1
# The SQL Server calls a setup step needs: run a statement, read one value,
# and answer whether a database is already there.
# Values are passed as parameters — a database name concatenated into a statement
# is an injection waiting for a machine name with a quote in it.

Import-Module (Join-Path $PSScriptRoot '..\..\src\Setup.Core.psm1') -Force -DisableNameChecking

$script:SetupSqlDatabaseKeyPattern = '(?i)(?:Initial Catalog|Database)\s*=\s*(?<name>[^;]+)'

function New-SetupSqlCommand {
    <#
        Builds a connection and its command. Callers dispose the connection.
    #>
    [CmdletBinding()]
    [OutputType([System.Data.SqlClient.SqlCommand])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ConnectionString,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Sql,

        [hashtable]$Parameter = @{}
    )

    $connection = [System.Data.SqlClient.SqlConnection]::new($ConnectionString)
    $command = $connection.CreateCommand()
    $command.CommandText = $Sql

    foreach ($entry in $Parameter.GetEnumerator()) {
        [void]$command.Parameters.AddWithValue($entry.Key, $entry.Value)
    }

    $command
}

function Invoke-SetupSql {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ConnectionString,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Sql,

        [hashtable]$Parameter = @{}
    )

    $command = New-SetupSqlCommand -ConnectionString $ConnectionString -Sql $Sql -Parameter $Parameter

    try {
        $command.Connection.Open()
        $command.ExecuteNonQuery()
    }
    finally {
        $command.Connection.Dispose()
    }
}

function Invoke-SetupSqlScalar {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ConnectionString,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Sql,

        [hashtable]$Parameter = @{}
    )

    $command = New-SetupSqlCommand -ConnectionString $ConnectionString -Sql $Sql -Parameter $Parameter

    try {
        $command.Connection.Open()
        $command.ExecuteScalar()
    }
    finally {
        $command.Connection.Dispose()
    }
}

function Get-SetupSqlDatabaseName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ConnectionString
    )

    if ($ConnectionString -match $script:SetupSqlDatabaseKeyPattern) {
        return $Matches.name.Trim()
    }

    throw "Connection string carries no 'Initial Catalog' or 'Database'."
}

function Remove-SetupSqlDatabaseName {
    <#
        The same connection string pointed at the server rather than at one database,
        which is what a "does this database exist" question has to connect to.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ConnectionString
    )

    $withoutDatabase = $ConnectionString -replace ';?\s*(?i)(?:Initial Catalog|Database)\s*=\s*[^;]+', ''

    $withoutDatabase.Trim().Trim(';')
}

function Test-SetupSqlDatabase {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ConnectionString
    )

    $databaseName = Get-SetupSqlDatabaseName -ConnectionString $ConnectionString
    $serverConnectionString = Remove-SetupSqlDatabaseName -ConnectionString $ConnectionString

    $count = Invoke-SetupSqlScalar `
        -ConnectionString $serverConnectionString `
        -Sql 'SELECT COUNT(*) FROM sys.databases WHERE name = @name' `
        -Parameter @{ '@name' = $databaseName }

    [int]$count -gt 0
}

Export-ModuleMember -Function New-SetupSqlCommand, Invoke-SetupSql, Invoke-SetupSqlScalar,
Get-SetupSqlDatabaseName, Remove-SetupSqlDatabaseName, Test-SetupSqlDatabase
