# Invoke-SetupSql, Invoke-SetupSqlScalar and Test-SetupSqlDatabase

The SQL Server calls a step needs.  
Values travel as parameters, never pasted into the statement.

```powershell
$connectionString = 'Server=.;Database=Shop;Integrated Security=True;TrustServerCertificate=True'

Test-SetupSqlDatabase -ConnectionString $connectionString
Invoke-SetupSqlScalar -ConnectionString $connectionString -Sql 'SELECT COUNT(*) FROM sys.tables'
Invoke-SetupSql -ConnectionString $connectionString -Sql 'DELETE FROM Cache WHERE Region = @region' -Parameter @{ '@region' = 'eu' }
```

## Synopsis

```powershell
Invoke-SetupSql -ConnectionString <string> -Sql <string> [-Parameter <hashtable>]
Invoke-SetupSqlScalar -ConnectionString <string> -Sql <string> [-Parameter <hashtable>]
Test-SetupSqlDatabase -ConnectionString <string>
```

| Function                | Returns                                                         |
| ----------------------- | --------------------------------------------------------------- |
| `Invoke-SetupSql`       | the rows the statement affected                                 |
| `Invoke-SetupSqlScalar` | the first column of the first row                               |
| `Test-SetupSqlDatabase` | `$true` when the database the connection string names exists   |

`Test-SetupSqlDatabase` connects to `master` on the same server, so it works before the database is there.  
That makes it the Test of a step that creates one, as the `New-SqlDatabase` template does.

## Credentials

Keep them out of step files, which are committed.  
`Integrated Security=True` signs in as the user running setup, who is the SQL Server administrator after the `Install-SqlServer2022` template.
