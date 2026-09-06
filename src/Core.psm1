<#
.SYNOPSIS
    Internal: the context a run shares across its parts, the data folders, the log file, markup escaping and durations.
#>
#Requires -Version 7.2

$script:SetupDataRoot = Join-Path -Path $env:ProgramData -ChildPath 'PwshSetup'

# StepPath is the steps folder being loaded, so Use-SetupTemplate finds the templates beside it.
# Task is the Invoke-AnsiTask control of the running step, so Write-SetupLog can print under it.
# RestartRequest is 'After' or 'Retry', set by Request-SetupRestart while a step runs.
$script:SetupContext = [pscustomobject]@{
    StepPath       = $null
    LogFile        = $null
    Task           = $null
    StepId         = $null
    RestartRequest = $null
}

# ── Context ──────────────────────────────────────────────────────────────────

function Get-SetupContext
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    return $script:SetupContext
}

function Reset-SetupContext
{
    [CmdletBinding()]
    param()

    $script:SetupContext.StepPath = $null
    $script:SetupContext.LogFile = $null
    $script:SetupContext.Task = $null
    $script:SetupContext.StepId = $null
    $script:SetupContext.RestartRequest = $null
}

function Test-SetupInteractive
{
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try
    {
        return -not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)
    }
    catch
    {
        return $false
    }
}

# ── Paths ────────────────────────────────────────────────────────────────────

function Get-SetupDataPath
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateSet('Logs', 'State')] [string] $Name
    )

    return (Join-Path -Path $script:SetupDataRoot -ChildPath $Name)
}

# The built module keeps the templates in Templates beside it; the source tree keeps them in templates beside src.
function Get-SetupTemplateRoot
{
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $candidates = @(
        (Join-Path -Path $PSScriptRoot -ChildPath 'Templates')
        (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'templates')
    )
    foreach ($candidate in $candidates)
    {
        if (Test-Path -LiteralPath $candidate -PathType Container)
        {
            return $candidate
        }
    }

    throw ('No templates folder found beside {0}.' -f $PSScriptRoot)
}

function Get-SetupOwnTemplateRoot
{
    # Your own templates: the templates folder beside the steps folder, or nothing when there is none.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $StepPath = $script:SetupContext.StepPath
    )

    if (-not $StepPath)
    {
        return $null
    }
    $root = Join-Path -Path (Split-Path -Path $StepPath -Parent) -ChildPath 'templates'
    if (Test-Path -LiteralPath $root -PathType Container)
    {
        return $root
    }
    return $null
}

# ── Log ──────────────────────────────────────────────────────────────────────

function Write-SetupLogFile
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OUTPUT')] [string] $Level = 'INFO'
    )

    $file = $script:SetupContext.LogFile
    if (-not $file)
    {
        return
    }

    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)
    $step = '-'
    if ($script:SetupContext.StepId)
    {
        $step = $script:SetupContext.StepId
    }

    $lines = foreach ($line in ($Message.TrimEnd() -split '\r?\n'))
    {
        '{0}  {1,-6}  {2}  {3}' -f $stamp, $Level, $step, $line
    }
    [System.IO.File]::AppendAllLines($file, [string[]]@($lines))
}

# ── Text ─────────────────────────────────────────────────────────────────────

function ConvertTo-SetupLiteral
{
    # Brackets doubled, so PwshAnsi markup prints the text as typed.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [AllowNull()] [string] $Text
    )

    return (([string]$Text -replace '\[', '[[') -replace '\]', ']]')
}

function Format-SetupDuration
{
    # 0.4s, 2.1s, 1m 05s, 1h 05m, the same on every culture.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [TimeSpan] $Duration
    )

    $culture = [cultureinfo]::InvariantCulture
    if ($Duration.TotalSeconds -lt 60)
    {
        return [string]::Format($culture, '{0:0.0}s', $Duration.TotalSeconds)
    }
    if ($Duration.TotalMinutes -lt 60)
    {
        return [string]::Format($culture, '{0}m {1:00}s', [Math]::Floor($Duration.TotalMinutes), $Duration.Seconds)
    }
    return [string]::Format($culture, '{0}h {1:00}m', [Math]::Floor($Duration.TotalHours), $Duration.Minutes)
}

Export-ModuleMember -Function Get-SetupContext, Reset-SetupContext, Test-SetupInteractive, Get-SetupDataPath,
Get-SetupTemplateRoot, Get-SetupOwnTemplateRoot, Write-SetupLogFile, ConvertTo-SetupLiteral, Format-SetupDuration
