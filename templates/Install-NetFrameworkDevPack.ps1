<#
.SYNOPSIS
    Installs the .NET Framework 4.8.1 Developer Pack, and the 4.8.1 runtime with it when missing.
#>
[CmdletBinding()]
param()

$referenceAssemblies = 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8.1'

$step = @{
    Name            = 'Install .NET Framework 4.8.1 Developer Pack'
    RequiresRestart = $true
    Test            = { Test-Path -LiteralPath (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath $referenceAssemblies) }
    Action          = { Install-ChocoPackage -Name 'netfx-4.8.1-devpack' }
}
New-SetupStep @step
