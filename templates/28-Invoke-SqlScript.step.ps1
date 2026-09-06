#Requires -Version 7.2

# 28-Invoke-SqlScript.step.ps1
# Runs one statement against SQL Server. Edit $connectionString and $sql before copying
# this into steps/; keep credentials in the environment, not in the file.

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-SetupSql.psm1') -Force -DisableNameChecking

$connectionString = 'Server=.;Database=master;Integrated Security=True;TrustServerCertificate=True'
$sql = 'SELECT 1'

New-SetupStep -Name 'Run SQL script' -Order 28 `
    -Test {
        $true
    } `
    -Action {
        Invoke-SetupSql -ConnectionString $connectionString -Sql $sql | Out-Null

        Write-SetupLog 'SQL script executed.' -Level Success
    }
