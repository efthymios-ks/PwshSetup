<#
.SYNOPSIS
    Public: Use-SetupTemplate, a step file that is one line naming a template.
#>
#Requires -Version 7.2

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Core.psm1') -DisableNameChecking
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Steps.psm1') -DisableNameChecking

function Use-SetupTemplate
{
    <#
    .SYNOPSIS
        Returns the step a template describes, for a step file to return as its own.
    .DESCRIPTION
        Looks for the template in the templates folder beside the steps folder first, where your own live, then among
        the templates published with the module. Your own template of the same name wins.
        The template runs in a module of its own, with -Parameter as its parameters.
    .PARAMETER Name
        The template, by file name without .ps1, such as Install-Git.
    .PARAMETER Parameter
        Values for the template's parameters, such as @{ Entries = '127.0.0.1 shop.local' }.
    .EXAMPLE
        Use-SetupTemplate -Name 'Install-Git'
    .EXAMPLE
        Use-SetupTemplate -Name 'Install-DotnetSdk' -Parameter @{ Version = 8 }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z0-9-]+$')] [string] $Name,
        [hashtable] $Parameter = @{}
    )

    $path = Find-SetupTemplate -Name $Name
    try
    {
        $step = Import-SetupScript -Path $path -Parameter $Parameter
    }
    catch
    {
        throw ('Template {0}: {1}' -f $Name, $_.Exception.Message)
    }
    $step.Template = $Name
    return $step
}

function Find-SetupTemplate
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Name
    )

    $fileName = '{0}.ps1' -f $Name
    $roots = @(Get-SetupOwnTemplateRoot) + @(Get-SetupTemplateRoot) | Where-Object -FilterScript { $_ }
    foreach ($root in $roots)
    {
        $path = Join-Path -Path $root -ChildPath $fileName
        if (Test-Path -LiteralPath $path -PathType Leaf)
        {
            return $path
        }
    }
    throw ('No template named {0}. Get-SetupTemplate lists them; your own go in a templates folder beside the steps folder.' -f $Name)
}

Export-ModuleMember -Function Use-SetupTemplate
