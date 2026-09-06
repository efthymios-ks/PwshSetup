<#
.SYNOPSIS
    Public: Test-SetupCommand and Test-SetupProgram, the two checks most step Tests need.
#>
#Requires -Version 7.2

$script:UninstallKeys = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

function Test-SetupCommand
{
    <#
    .SYNOPSIS
        $true when a command, such as git or dotnet, resolves in this session.
    .PARAMETER Name
        The command.
    .EXAMPLE
        Test-SetupCommand -Name 'git'
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Name
    )

    return [bool](Get-Command -Name $Name -ErrorAction Ignore)
}

function Test-SetupProgram
{
    <#
    .SYNOPSIS
        $true when Windows lists a program under Installed apps, by display name.
    .DESCRIPTION
        Reads the machine and current user uninstall entries, the list Settings shows.
        Wildcards are allowed, so 'Mozilla Firefox*' matches every edition and language.
    .PARAMETER Name
        The display name, wildcards allowed.
    .EXAMPLE
        Test-SetupProgram -Name 'Google Chrome'
    .EXAMPLE
        Test-SetupProgram -Name 'SQL Server Management Studio*'
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Name
    )

    foreach ($key in $script:UninstallKeys)
    {
        $match = Get-ItemProperty -Path $key -ErrorAction Ignore |
            Where-Object -FilterScript { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like $Name } |
            Select-Object -First 1
        if ($match)
        {
            return $true
        }
    }
    return $false
}

Export-ModuleMember -Function Test-SetupCommand, Test-SetupProgram
