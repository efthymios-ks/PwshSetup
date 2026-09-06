<#
.SYNOPSIS
    Clones one Git repository. Put a Git step before it.
.PARAMETER RepositoryUrl
    The repository to clone.
.PARAMETER DestinationPath
    The folder to clone into. The step counts as done once it holds a .git folder.
.EXAMPLE
    Use-SetupTemplate -Name 'Copy-Repository' -Parameter @{ RepositoryUrl = 'https://github.com/efthymios-ks/PwshSetup.git'; DestinationPath = 'C:\Repos\PwshSetup' }
#>
[CmdletBinding()]
param(
    [string] $RepositoryUrl,
    [string] $DestinationPath
)

if (-not $RepositoryUrl -or -not $DestinationPath)
{
    throw 'Pass both values: -Parameter @{ RepositoryUrl = ''https://...''; DestinationPath = ''C:\Repos\...'' }.'
}

$step = @{
    Name   = ('Clone {0}' -f (Split-Path -Path $DestinationPath -Leaf))
    Test   = { Test-Path -LiteralPath (Join-Path -Path $DestinationPath -ChildPath '.git') }
    Action = {
        git clone $RepositoryUrl $DestinationPath *>&1
        if ($LASTEXITCODE -ne 0)
        {
            throw ('git clone failed with exit code {0}.' -f $LASTEXITCODE)
        }
        Write-SetupLog -Message ('Cloned into {0}.' -f $DestinationPath)
    }
}
New-SetupStep @step
