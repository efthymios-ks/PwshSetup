#Requires -Version 7.2

# 020-Skip-Marker.step.ps1
# Dummy step: reports it has nothing to do, so the runner skips it.

# Already loaded when the runner is under test; imported when the file is run on its own.
if (-not (Get-Command New-SetupStep -ErrorAction Ignore)) {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\Setup.Core.psm1') -Force -DisableNameChecking
}

New-SetupStep -Name 'Skip marker' -Order 20 `
    -Test {
        $false
    } `
    -Action {
        if ($env:PWSHSETUP_TEST_LOG) {
            Add-Content -LiteralPath $env:PWSHSETUP_TEST_LOG -Value 'Skip marker'
        }
    }
