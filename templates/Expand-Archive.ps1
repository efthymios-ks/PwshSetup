<#
.SYNOPSIS
    Unpacks an archive into a folder, once.
.PARAMETER ArchivePath
    The .zip to unpack. A path relative to your step file needs $PSScriptRoot in front of it.
.PARAMETER DestinationPath
    The folder to unpack into. The step counts as done once it exists.
.EXAMPLE
    Use-SetupTemplate -Name 'Expand-Archive' -Parameter @{ ArchivePath = (Join-Path -Path $PSScriptRoot -ChildPath '..\assets\Tools.zip'); DestinationPath = 'C:\Tools' }
#>
[CmdletBinding()]
param(
    [string] $ArchivePath,
    [string] $DestinationPath
)

if (-not $ArchivePath -or -not $DestinationPath)
{
    throw 'Pass both values: -Parameter @{ ArchivePath = ''...zip''; DestinationPath = ''C:\...'' }.'
}

$step = @{
    Name   = ('Expand {0}' -f (Split-Path -Path $ArchivePath -Leaf))
    Test   = { Test-Path -LiteralPath $DestinationPath -PathType Container }
    Action = {
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $DestinationPath -Force
        Write-SetupLog -Message ('Extracted into {0}.' -f $DestinationPath)
    }
}
New-SetupStep @step
