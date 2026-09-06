<#
.SYNOPSIS
    Detection helpers the template system tests share, so every test checks the same way.
.DESCRIPTION
    Each *.Tests.ps1 dot-sources this file in BeforeDiscovery. The helpers need no PwshSetup, so discovery works on a
    machine without it. They are global, so BeforeDiscovery, BeforeAll and It all see them.
#>

function global:Test-SystemCommand
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Name
    )
    return [bool](Get-Command -Name $Name -ErrorAction Ignore)
}

function global:Test-InstalledApp
{
    # The uninstall entries Test-SetupProgram reads, with one difference: a name without a wildcard gets a trailing
    # one, so 'Notepad++' also matches 'Notepad++ (64-bit x64)'.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $DisplayName
    )
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $pattern = $DisplayName
    if ($DisplayName -notmatch '[\*\?\[]')
    {
        $pattern = '{0}*' -f $DisplayName
    }
    $hit = Get-ItemProperty -Path $keys -ErrorAction Ignore |
        Where-Object -FilterScript { $_.DisplayName -like $pattern } |
        Select-Object -First 1
    return [bool]$hit
}

function global:Test-WindowsFeature
{
    # Get-WindowsOptionalFeature needs elevation. Without it the feature counts as not found, instead of failing
    # discovery for the whole file.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $FeatureName
    )
    try
    {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop
        return $feature.State -eq 'Enabled'
    }
    catch
    {
        return $false
    }
}
