<#
.SYNOPSIS
    Installs Google Chrome.
.NOTES
    Google replaces the installer behind a fixed URL, so the package checksum often lags behind it; checksums are skipped.
#>
[CmdletBinding()]
param()

$step = @{
    Name   = 'Install Google Chrome'
    Test   = { Test-SetupProgram -Name 'Google Chrome' }
    Action = { Install-ChocoPackage -Name 'googlechrome' -AdditionalArgument '--ignore-checksums' }
}
New-SetupStep @step
