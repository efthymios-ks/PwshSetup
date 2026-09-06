#Requires -Version 7.2

# 14-Install-DotnetSdk9.step.ps1
# Install .NET SDK 9

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install .NET SDK 9' -Order 14 `
    -Test {
        -not ((Test-SetupCommand 'dotnet') -and ((dotnet --list-sdks) -match '^9\.0\.'))
    } `
    -Action {
        Install-ChocoPackage -Name 'dotnet-9.0-sdk'

        Sync-ChocoEnvironment
    }
