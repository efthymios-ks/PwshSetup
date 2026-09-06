<#
.SYNOPSIS
    Builds a small ZIP for the Expand-Archive step to unpack. A step of this setup, not a published template.
#>
[CmdletBinding()]
param()

$archivePath = 'C:\TestArchive\test.zip'

$step = @{
    Name   = 'Build the Expand-Archive test ZIP'
    Test   = { Test-Path -LiteralPath $archivePath }
    Action = {
        $source = Join-Path -Path $env:TEMP -ChildPath 'pwshsetup-archive-src'
        $null = New-Item -ItemType Directory -Path $source -Force
        Set-Content -LiteralPath (Join-Path -Path $source -ChildPath 'hello.txt') -Value 'hello from the test archive' -Encoding utf8
        $null = New-Item -ItemType Directory -Path (Split-Path -Path $archivePath -Parent) -Force
        Compress-Archive -Path (Join-Path -Path $source -ChildPath '*') -DestinationPath $archivePath -Force
    }
}
New-SetupStep @step
