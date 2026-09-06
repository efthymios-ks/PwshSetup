<#
.SYNOPSIS
    Internal: turns a folder of step files into ordered step objects, runs a step's Test, and reads what a step installs.
.DESCRIPTION
    Every .ps1 in the folder is a step, ordered by the number its name starts with.
    Step files and templates each run in a module of their own, so the values they set at the top, or take as
    parameters, stay reachable from their Test and Action when those run later. Inside both, $ErrorActionPreference is
    Stop, and progress bars are off: they would draw over the run's own progress lines.
#>
#Requires -Version 7.2

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Core.psm1') -DisableNameChecking

# ── Loading ──────────────────────────────────────────────────────────────────

function Import-SetupStep
{
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Path
    )

    (Get-SetupContext).StepPath = $Path
    $files = Get-ChildItem -LiteralPath $Path -Filter '*.ps1' -File
    $steps = foreach ($file in $files)
    {
        Import-SetupStepFile -File $file
    }
    return @(@($steps) | Sort-Object -Property Order, Id)
}

function Import-SetupStepFile
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo] $File
    )

    try
    {
        $step = Import-SetupScript -Path $File.FullName
    }
    catch
    {
        throw ('Step file {0}: {1}' -f $File.Name, $_.Exception.Message)
    }

    $step.Id = $File.BaseName
    $step.Order = [int]::MaxValue
    if ($File.Name -match '^(?<order>\d+)')
    {
        $step.Order = [int]$Matches.order
    }
    $step.File = $File.FullName
    return $step
}

function Import-SetupScript
{
    # Runs a step file or a template in a module of its own and returns the one step it describes. A step that came
    # through Use-SetupTemplate keeps the template's module.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [hashtable] $Parameter = @{}
    )

    $loader = {
        param($SetupScriptPath, $SetupScriptParameter)

        $ErrorActionPreference = 'Stop'
        $ProgressPreference = 'SilentlyContinue'
        $script:SetupScriptOutput = @(. $SetupScriptPath @SetupScriptParameter)
        Export-ModuleMember
    }
    $moduleName = 'PwshSetup.Step.{0}' -f [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $module = New-Module -Name $moduleName -ScriptBlock $loader -ArgumentList $Path, $Parameter

    $output = @(& $module { $script:SetupScriptOutput })
    $found = @($output | Where-Object -FilterScript { $_ -is [psobject] -and $_.PSObject.TypeNames -contains 'PwshSetup.Step' })
    if ($found.Count -ne 1)
    {
        throw ('it returned {0} steps, and a step file returns exactly one New-SetupStep or Use-SetupTemplate.' -f $found.Count)
    }

    $step = $found[0]
    if (-not $step.Module)
    {
        $step.Module = $module
    }
    return $step
}

# ── Checks ───────────────────────────────────────────────────────────────────

function Test-SetupStepDone
{
    # The last thing the Test writes decides, by PowerShell truthiness, so a -match that finds nothing reads as not done.
    # A Test that throws counts as not done too, and Error says why: often it checks what an earlier step installs.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Step
    )

    if (-not $Step.Test)
    {
        return [pscustomobject]@{ Done = $false; Error = $null }
    }

    try
    {
        $output = @(& $Step.Test 3>$null 6>$null)
        $done = $output.Count -gt 0 -and [bool]$output[-1]
        return [pscustomobject]@{ Done = $done; Error = $null }
    }
    catch
    {
        return [pscustomobject]@{ Done = $false; Error = $_.Exception.Message }
    }
}

function Get-SetupStepPackage
{
    # The Chocolatey packages a step's Action names, read from its syntax tree without running it. A name in a variable
    # set at the top of the file, or passed to a template, is read from the step's module; one set inside the Action
    # cannot be known before it runs, and Unknown counts it.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Step
    )

    $isInstall = {
        param($Node)
        $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Install-ChocoPackage'
    }
    $names = [System.Collections.Generic.List[string]]::new()
    $unknown = 0
    foreach ($command in $Step.Action.Ast.FindAll($isInstall, $true))
    {
        $value = Get-SetupNameArgument -Command $command
        $name = $null
        if ($value -is [System.Management.Automation.Language.StringConstantExpressionAst])
        {
            $name = $value.Value
        }
        elseif ($value -is [System.Management.Automation.Language.VariableExpressionAst] -and $Step.Module)
        {
            $known = $Step.Module.SessionState.PSVariable.GetValue($value.VariablePath.UserPath)
            if ($known -is [string])
            {
                $name = $known
            }
        }

        if ($name)
        {
            $names.Add($name)
        }
        else
        {
            $unknown++
        }
    }

    return [pscustomobject]@{ Names = $names.ToArray(); Unknown = $unknown }
}

function Get-SetupNameArgument
{
    # The value given to -Name, or the first positional argument.
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Language.Ast])]
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Language.CommandAst] $Command
    )

    $elements = $Command.CommandElements
    for ($index = 1; $index -lt $elements.Count; $index++)
    {
        $element = $elements[$index]
        if ($element -isnot [System.Management.Automation.Language.CommandParameterAst])
        {
            return $element
        }
        if ($element.ParameterName -eq 'Name')
        {
            if ($element.Argument)
            {
                return $element.Argument
            }
            if ($index + 1 -lt $elements.Count)
            {
                return $elements[$index + 1]
            }
            return $null
        }
        if (-not $element.Argument -and $element.ParameterName -ne 'PassThru')
        {
            $index++
        }
    }
    return $null
}

Export-ModuleMember -Function Import-SetupStep, Import-SetupScript, Test-SetupStepDone, Get-SetupStepPackage
