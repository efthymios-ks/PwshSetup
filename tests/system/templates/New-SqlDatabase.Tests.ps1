BeforeDiscovery {
    # Skip-on-absence probe is the SQL Server service, not the database itself: a failing SqlClient
    # connection or a missing login would otherwise silently look like 'db missing' and skip, hiding the
    # real error. If MSSQLSERVER exists we always run the assertion so any connection/auth problem shows.
    $script:detected = [bool](Get-Service -Name 'MSSQLSERVER' -ErrorAction Ignore)
}

Describe 'New-SqlDatabase' -Skip:(-not $script:detected) {
    It 'when created, should list PwshSetupTest on the local SQL Server' {
        $connection = [System.Data.SqlClient.SqlConnection]::new('Server=.;Integrated Security=True;TrustServerCertificate=True')
        $connection.Open()
        try
        {
            $command = $connection.CreateCommand()
            $command.CommandText = "SELECT COUNT(*) FROM sys.databases WHERE name = 'PwshSetupTest'"
            [int]$command.ExecuteScalar() | Should -BeGreaterThan 0
        }
        finally
        {
            $connection.Dispose()
        }
    }
}
