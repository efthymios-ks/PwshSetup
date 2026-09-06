#Requires -Version 7.2

# 01-Install-Chocolatey.step.ps1
# Install Chocolatey — everything downstream installs through it, so it goes first.

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot '..	emplates\modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install Chocolatey' -Order 1 `
    -Test {
        -not (Test-ChocoInstalled)
    } `
    -Action {
        $installer = Join-Path $env:TEMP 'install-chocolatey.ps1'

        Invoke-WebRequest -Uri 'https://community.chocolatey.org/install.ps1' -OutFile $installer -UseBasicParsing
        & $installer

        Sync-ChocoEnvironment

        # Chocolatey stops the run when a package asks for a reboot, so the pipeline
        # can restart and resume instead of installing on top of a half-applied machine.
        Invoke-ChocoCommand 'feature' 'enable' '--name=exitOnRebootDetected' | Out-Null
    }
