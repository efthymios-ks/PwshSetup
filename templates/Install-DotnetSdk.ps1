<#
.SYNOPSIS
    Installs a .NET SDK, by major version.
.PARAMETER Version
    The major version, such as 8 or 10.
.EXAMPLE
    Use-SetupTemplate -Name 'Install-DotnetSdk'
.EXAMPLE
    Use-SetupTemplate -Name 'Install-DotnetSdk' -Parameter @{ Version = 8 }
#>
[CmdletBinding()]
param(
    [ValidateRange(5, 99)] [int] $Version = 10
)

$package = 'dotnet-{0}.0-sdk' -f $Version
$sdkPattern = '^{0}\.' -f $Version

$step = @{
    Name   = ('Install .NET SDK {0}' -f $Version)
    Test   = { (Test-SetupCommand -Name 'dotnet') -and [bool]((dotnet --list-sdks) -match $sdkPattern) }
    Action = { Install-ChocoPackage -Name $package }
}
New-SetupStep @step
