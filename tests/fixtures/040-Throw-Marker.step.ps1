#Requires -Version 7.2

# 040-Throw-Marker.step.ps1
# Dummy step: fails, so the runner stops on it.

# Already loaded when the runner is under test; imported when the file is run on its own.
if (-not (Get-Command New-SetupStep -ErrorAction Ignore)) {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\Setup.Core.psm1') -Force -DisableNameChecking
}

New-SetupStep -Name 'Throw marker' -Order 40 `
    -Test {
        $true
    } `
    -Action {
        throw 'dummy step failed on purpose'
    }
