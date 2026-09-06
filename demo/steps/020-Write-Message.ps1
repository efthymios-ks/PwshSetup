<#
.SYNOPSIS
    Demo: a step that writes lines under itself as it goes.
#>

$tables = @('Users', 'Orders', 'Invoices')

$step = @{
    Name   = 'Write messages under the step'
    Test   = { $false }
    Action = {
        foreach ($table in $tables)
        {
            Start-Sleep -Milliseconds 600
            Write-SetupLog -Message ('copied {0}' -f $table)
        }
        Write-SetupLog -Message 'one table was empty' -Level Warning
    }
}
New-SetupStep @step
