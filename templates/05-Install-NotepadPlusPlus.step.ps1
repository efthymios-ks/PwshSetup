#Requires -Version 7.2

# 05-Install-NotepadPlusPlus.step.ps1
# Install Notepad++

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install Notepad++' -Order 5 `
    -Test {
        -not (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Notepad++\notepad++.exe'))
    } `
    -Action {
        Install-ChocoPackage -Name 'notepadplusplus'
    }
