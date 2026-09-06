<#
.SYNOPSIS
    Public: Get-SetupTemplate, the templates a step file can name with Use-SetupTemplate.
#>
#Requires -Version 7.2

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Core.psm1') -DisableNameChecking

function Get-SetupTemplate
{
    <#
    .SYNOPSIS
        Lists the templates a step file can name with Use-SetupTemplate.
    .DESCRIPTION
        The templates published with the module, and with -StepPath your own from the templates folder beside that
        steps folder. One object per template: Id, the step's Name, its Parameters, its Source (Own or Module) and Path.
        Reading a template never runs it.
    .PARAMETER Id
        Template ids to return, wildcards allowed. All of them when omitted.
    .PARAMETER StepPath
        A steps folder, to list your own templates beside it too.
    .EXAMPLE
        Get-SetupTemplate
    .EXAMPLE
        Get-SetupTemplate -Id '*Sql*' -StepPath 'C:\Setup\steps'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateNotNullOrEmpty()] [string[]] $Id = @('*'),
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })] [string] $StepPath
    )

    $sources = [System.Collections.Generic.List[object]]::new()
    if ($StepPath)
    {
        $ownRoot = Get-SetupOwnTemplateRoot -StepPath $StepPath
        if ($ownRoot)
        {
            $sources.Add([pscustomobject]@{ Source = 'Own'; Root = $ownRoot })
        }
    }
    $sources.Add([pscustomobject]@{ Source = 'Module'; Root = (Get-SetupTemplateRoot) })

    foreach ($source in $sources)
    {
        $files = Get-ChildItem -LiteralPath $source.Root -Filter '*.ps1' -File | Sort-Object -Property Name
        foreach ($file in $files)
        {
            $templateId = $file.BaseName
            if (@($Id | Where-Object -FilterScript { $templateId -like $_ }).Count -eq 0)
            {
                continue
            }

            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            [pscustomobject]@{
                PSTypeName = 'PwshSetup.Template'
                Id         = $templateId
                Name       = Get-SetupTemplateName -Ast $ast -Default $templateId
                Parameters = @(Get-SetupTemplateParameter -Ast $ast)
                Source     = $source.Source
                Path       = $file.FullName
            }
        }
    }
}

function Get-SetupTemplateParameter
{
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Language.ScriptBlockAst] $Ast
    )

    if (-not $Ast.ParamBlock)
    {
        return @()
    }
    return @($Ast.ParamBlock.Parameters | ForEach-Object -Process { $_.Name.VariablePath.UserPath })
}

function Get-SetupTemplateName
{
    # The step's name as a literal, read from the syntax tree: New-SetupStep -Name, or the Name key of the hashtable
    # splatted into it. The default when the name is built at run time.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Language.ScriptBlockAst] $Ast,
        [Parameter(Mandatory)] [string] $Default
    )

    $isCommand = {
        param($Node)
        $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'New-SetupStep'
    }
    $command = $Ast.Find($isCommand, $true)
    if ($command)
    {
        $elements = $command.CommandElements
        for ($index = 0; $index -lt $elements.Count - 1; $index++)
        {
            $element = $elements[$index]
            $isName = $element -is [System.Management.Automation.Language.CommandParameterAst] -and $element.ParameterName -eq 'Name'
            if ($isName -and $elements[$index + 1] -is [System.Management.Automation.Language.StringConstantExpressionAst])
            {
                return $elements[$index + 1].Value
            }
        }
    }

    $hashtables = $Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.HashtableAst] }, $true)
    foreach ($hashtable in $hashtables)
    {
        foreach ($pair in $hashtable.KeyValuePairs)
        {
            if ($pair.Item1 -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or $pair.Item1.Value -ne 'Name')
            {
                continue
            }
            $value = $pair.Item2
            if ($value -is [System.Management.Automation.Language.PipelineAst] -and $value.PipelineElements.Count -eq 1)
            {
                $expression = $value.PipelineElements[0].Expression
                if ($expression -is [System.Management.Automation.Language.StringConstantExpressionAst])
                {
                    return $expression.Value
                }
            }
        }
    }
    return $Default
}

Export-ModuleMember -Function Get-SetupTemplate
