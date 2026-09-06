<#
.SYNOPSIS
    Makes sure SQL Server starts with Windows, runs, and takes connections. A step of this setup, not a published
    template.
.DESCRIPTION
    A restart can leave the service stopped, and a service that just started reports Running before the database
    engine takes connections. The step sets the service to start with Windows, starts it, and waits for a connection,
    so the database step after it does not race the engine.
#>
[CmdletBinding()]
param()

$serviceName = 'MSSQLSERVER'
$connectionString = 'Server=.;Integrated Security=True;TrustServerCertificate=True;Database=master;Connect Timeout=3'
$waitMinutes = 5
$retrySeconds = 2

$step = @{
    Name   = 'Wait for SQL Server to start and take connections'
    Test   = {
        $service = Get-Service -Name $serviceName -ErrorAction Ignore
        if (-not $service -or $service.StartType -ne 'Automatic' -or $service.Status -ne 'Running')
        {
            return $false
        }
        try
        {
            $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
            $connection.Open()
            $connection.Dispose()
            return $true
        }
        catch
        {
            return $false
        }
    }
    Action = {
        if ((Get-Service -Name $serviceName).StartType -ne 'Automatic')
        {
            Set-Service -Name $serviceName -StartupType Automatic
        }
        if ((Get-Service -Name $serviceName).Status -ne 'Running')
        {
            Start-Service -Name $serviceName
        }

        $deadline = (Get-Date).AddMinutes($waitMinutes)
        while ((Get-Date) -lt $deadline)
        {
            try
            {
                $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
                $connection.Open()
                $connection.Dispose()
                return
            }
            catch
            {
                Start-Sleep -Seconds $retrySeconds
            }
        }
        throw ('{0} runs but took no connection within {1} minutes.' -f $serviceName, $waitMinutes)
    }
}
New-SetupStep @step
