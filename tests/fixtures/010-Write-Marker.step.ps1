#Requires -Version 7.2

# 010-Write-Marker.step.ps1
# Dummy step: appends its name to the file named by $env:PWSHSETUP_TEST_LOG. Touches nothing else.

# Already loaded when the runner is under test; imported when the file is run on its own.
if (-not (Get-Command New-SetupStep -ErrorAction Ignore)) {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\Setup.Core.psm1') -Force -DisableNameChecking
}

New-SetupStep -Name 'Write marker' -Order 10 `
    -Test {
        $true
    } `
    -Action {
        if ($env:PWSHSETUP_TEST_LOG) {
            Add-Content -LiteralPath $env:PWSHSETUP_TEST_LOG -Value 'Write marker'
        }
    }
