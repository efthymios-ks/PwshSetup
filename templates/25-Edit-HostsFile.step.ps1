#Requires -Version 7.2

# 25-Edit-HostsFile.step.ps1
# Adds host entries, and leaves the file alone when they are all already there.
# Edit $entries before copying this into steps/.

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking

$hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'

$entries = @(
    '127.0.0.1 example1.local'
    '127.0.0.1 example2.local'
)

New-SetupStep -Name 'Edit hosts file' -Order 25 `
    -Test {
        $current = @(Get-Content -LiteralPath $hostsPath)

        [bool]($entries | Where-Object { $current -notcontains $_ })
    } `
    -Action {
        $current = @(Get-Content -LiteralPath $hostsPath) | Where-Object { $entries -notcontains $_.Trim() }
        $updated = @($current) + @($entries | Sort-Object -Unique)

        Set-Content -LiteralPath $hostsPath -Value $updated

        Write-SetupLog "Hosts file updated: $hostsPath"
    }
