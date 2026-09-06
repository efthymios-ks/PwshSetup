#Requires -Version 7.2

# 030-Restart-Marker.step.ps1
# Dummy step: asks for a restart once its action has run.

# Already loaded when the runner is under test; imported when the file is run on its own.
if (-not (Get-Command New-SetupStep -ErrorAction Ignore)) {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\Setup.Core.psm1') -Force -DisableNameChecking
}

New-SetupStep -Name 'Restart marker' -Order 30 `
    -Test {
        $true
    } `
    -Action {
        if ($env:PWSHSETUP_TEST_LOG) {
            Add-Content -LiteralPath $env:PWSHSETUP_TEST_LOG -Value 'Restart marker'
        }
    } `
    -RequiresRestart
