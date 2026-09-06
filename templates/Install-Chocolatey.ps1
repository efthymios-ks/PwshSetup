<#
.SYNOPSIS
    Installs Chocolatey, which every package step after it installs through.
.NOTES
    Turns on exitOnRebootDetected, so Chocolatey refuses to install over a pending restart and the run restarts first.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install Chocolatey'
    Test   = { Test-SetupCommand -Name 'choco' }
    Action = {
        $installer = Join-Path -Path $env:TEMP -ChildPath 'install-chocolatey.ps1'
        Invoke-WebRequest -Uri 'https://community.chocolatey.org/install.ps1' -OutFile $installer -UseBasicParsing
        & $installer *>&1
        Remove-Item -LiteralPath $installer -Force

        Update-SetupEnvironment
        $null = Invoke-ChocoCommand -ArgumentList 'feature', 'enable', '--name=exitOnRebootDetected'
    }
}
New-SetupStep @step
