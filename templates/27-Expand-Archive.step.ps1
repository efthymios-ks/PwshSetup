#Requires -Version 7.2

# 27-Expand-Archive.step.ps1
# Unpacks an archive over a folder, adding and overwriting but never deleting.
# Edit $archivePath and $destinationPath before copying this into steps/.

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking

$archivePath = Join-Path $PSScriptRoot '..\assets\Example.zip'
$destinationPath = Join-Path $env:USERPROFILE 'Desktop\Example'

New-SetupStep -Name 'Expand archive' -Order 27 `
    -Test {
        Test-Path -LiteralPath $archivePath -PathType Leaf
    } `
    -Action {
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
        }

        Expand-Archive -LiteralPath $archivePath -DestinationPath $destinationPath -Force

        Write-SetupLog "Extracted $archivePath into $destinationPath"
    }
