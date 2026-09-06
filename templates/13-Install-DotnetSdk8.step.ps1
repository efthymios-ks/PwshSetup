#Requires -Version 7.2

# 13-Install-DotnetSdk8.step.ps1
# Install .NET SDK 8

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install .NET SDK 8' -Order 13 `
    -Test {
        -not ((Test-SetupCommand 'dotnet') -and ((dotnet --list-sdks) -match '^8\.0\.'))
    } `
    -Action {
        Install-ChocoPackage -Name 'dotnet-8.0-sdk'

        Sync-ChocoEnvironment
    }
