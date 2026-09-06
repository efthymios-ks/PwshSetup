<#
.SYNOPSIS
    Adds host entries, and leaves the file alone when they are all there.
.PARAMETER Entries
    The lines to have in the hosts file, such as '127.0.0.1 shop.local'.
.EXAMPLE
    Use-SetupTemplate -Name 'Edit-HostsFile' -Parameter @{ Entries = '127.0.0.1 shop.local', '127.0.0.1 api.shop.local' }
#>
[CmdletBinding()]
param(
    [string[]] $Entries
)

if (-not $Entries)
{
    throw 'Pass the lines to add: -Parameter @{ Entries = ''127.0.0.1 shop.local'' }.'
}
$hostsPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\drivers\etc\hosts'

$step = @{
    Name   = 'Edit hosts file'
    Test   = {
        $current = @(Get-Content -LiteralPath $hostsPath | ForEach-Object -Process { $_.Trim() })
        @($Entries | Where-Object -FilterScript { $current -notcontains $_ }).Count -eq 0
    }
    Action = {
        $kept = @(Get-Content -LiteralPath $hostsPath | Where-Object -FilterScript { $Entries -notcontains $_.Trim() })
        Set-Content -LiteralPath $hostsPath -Value ($kept + $Entries) -Encoding ascii
        Write-SetupLog -Message ('{0} entries in {1}.' -f $Entries.Count, $hostsPath)
    }
}
New-SetupStep @step
