<#
.SYNOPSIS
    Public: Update-SetupEnvironment, so a step sees what the step before it installed.
#>
#Requires -Version 7.2

function Update-SetupEnvironment
{
    <#
    .SYNOPSIS
        Reloads the machine and user environment variables into this session.
    .DESCRIPTION
        Installers write PATH and other variables to the registry, which a running session never rereads.
        This copies them in, machine first and user second, and joins both PATHs, so a command installed by one step
        resolves in the next. Install-ChocoPackage calls it after every install.
    .EXAMPLE
        Update-SetupEnvironment
    #>
    [CmdletBinding()]
    param()

    $machine = [Environment]::GetEnvironmentVariables('Machine')
    $user = [Environment]::GetEnvironmentVariables('User')

    foreach ($scope in $machine, $user)
    {
        foreach ($name in $scope.Keys)
        {
            if ($name -in 'Path', 'PSModulePath', 'USERNAME')
            {
                continue
            }
            [Environment]::SetEnvironmentVariable($name, [string]$scope[$name], 'Process')
        }
    }

    $paths = @([string]$machine['Path'], [string]$user['Path']) -split ';' | Where-Object -FilterScript { $_ }
    $env:Path = ($paths | Select-Object -Unique) -join ';'
}

Export-ModuleMember -Function Update-SetupEnvironment
