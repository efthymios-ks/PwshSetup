#Requires -Version 7.2

# 26-Copy-Repository.step.ps1
# Clones one repository. Edit $repositoryUrl and $destinationPath before copying this into steps/.

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking

$repositoryUrl = 'https://github.com/efthymios-ks/PwshSetup.git'
$destinationPath = 'C:\Repos\PwshSetup'

New-SetupStep -Name 'Clone repository' -Order 26 `
    -Test {
        -not (Test-Path -LiteralPath $destinationPath)
    } `
    -Action {
        if (-not (Test-SetupCommand 'git')) {
            throw 'git is not installed; put the git step before this one.'
        }

        git clone $repositoryUrl $destinationPath

        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed with exit code $LASTEXITCODE."
        }

        Write-SetupLog "Cloned into $destinationPath" -Level Success
    }
