<#
.SYNOPSIS
    Installs Notepad++.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install Notepad++'
    Test   = { Test-SetupProgram -Name 'Notepad++*' }
    Action = { Install-ChocoPackage -Name 'notepadplusplus' }
}
New-SetupStep @step
