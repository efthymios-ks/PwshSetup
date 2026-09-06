<#
.SYNOPSIS
    Public: Assert-SetupAdmin and Test-SetupAdmin.
.DESCRIPTION
    Stays Windows PowerShell 5.1 syntax and plain ASCII throughout: the build makes this file the module's loader, and
    the loader is what Windows PowerShell imports.
#>
#Requires -Version 5.1

$script:RerunVariable = 'PWSHSETUP_RERUN'

function Test-SetupAdmin
{
    <#
    .SYNOPSIS
        $true when the session runs as administrator.
    .EXAMPLE
        if (-not (Test-SetupAdmin)) { 'Not elevated' }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object -TypeName 'Security.Principal.WindowsPrincipal' -ArgumentList $identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-SetupBootstrapLog
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Runs before PwshAnsi can draw, possibly on Windows PowerShell.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message
    )

    Write-Host -Object ('[PwshSetup] {0}' -f $Message) -ForegroundColor Yellow
}

function ConvertTo-SetupPortableArgument
{
    # Switches become booleans: a SwitchParameter does not come back from Import-Clixml as one.
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [hashtable] $Arguments = @{}
    )

    $bound = @{}
    foreach ($key in $Arguments.Keys)
    {
        $value = $Arguments[$key]
        if ($value -is [System.Management.Automation.SwitchParameter])
        {
            $value = $value.IsPresent
        }
        $bound[$key] = $value
    }
    return $bound
}

function Find-SetupTerminal
{
    # wt.exe on the PATH, or at the per-user WindowsApps alias, or $null.
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $terminal = Get-Command -Name 'wt.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($terminal)
    {
        return $terminal.Source
    }
    if ($env:LOCALAPPDATA)
    {
        $alias = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\wt.exe'
        if (Test-Path -LiteralPath $alias)
        {
            return $alias
        }
    }
    return $null
}

function Get-SetupTerminalArgument
{
    # Windows Terminal splits its commands at semicolons, and a trailing backslash would escape the closing quote.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Pwsh,
        [Parameter(Mandatory)] [string] $EncodedCommand
    )

    $arguments = @()
    if ($PWD.Provider.Name -eq 'FileSystem')
    {
        $directory = $PWD.ProviderPath.Replace(';', '\;') -replace '\\$', '\\'
        $arguments += @('-d', ('"{0}"' -f $directory))
    }
    $arguments += @(('"{0}"' -f $Pwsh), '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $EncodedCommand)
    return ($arguments -join ' ')
}

function Get-SetupRerunCommand
{
    # The command the elevated window runs: marks the rerun, restores the folder and the parameters, and keeps the
    # window open on a failure that ends the script early.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $ScriptPath,
        [Parameter(Mandatory)] [string] $ArgumentFile,
        [Parameter(Mandatory)] [string] $Marker
    )

    $quote = { param($Text) "'" + ($Text -replace "'", "''") + "'" }
    $lines = @(('$env:{0} = {1}' -f $script:RerunVariable, (& $quote $Marker)))
    if ($PWD.Provider.Name -eq 'FileSystem')
    {
        $lines += ('Set-Location -LiteralPath {0}' -f (& $quote $PWD.ProviderPath))
    }
    $lines += @(
        ('$p = Import-Clixml -LiteralPath {0}' -f (& $quote $ArgumentFile))
        ('Remove-Item -LiteralPath {0} -Force' -f (& $quote $ArgumentFile))
        'try'
        '{'
        ('    & {0} @p' -f (& $quote $ScriptPath))
        '}'
        'catch'
        '{'
        '    Write-Host -Object ($_ | Out-String) -ForegroundColor Red'
        '    $null = Read-Host -Prompt ''Press Enter to close'''
        '    exit 1'
        '}'
        'exit $LASTEXITCODE'
    )
    return ($lines -join "`n")
}

function Assert-SetupAdmin
{
    <#
    .SYNOPSIS
        Ensures the calling script runs as administrator.
    .DESCRIPTION
        Already elevated: returns at once.
        Otherwise reruns the calling script elevated, with its parameters, after one UAC prompt: in a new Windows
        Terminal window when wt.exe is found, in a new console window when not. This window ends there.
        Call it after Assert-PwshAnsi, so the elevated run starts on pwsh.
    .PARAMETER Arguments
        Parameters to pass to the rerun. Defaults to the bound parameters of the calling script.
    .PARAMETER ScriptPath
        Script to rerun. Defaults to the calling script.
    .EXAMPLE
        Assert-SetupAdmin
    #>
    [CmdletBinding()]
    param(
        [hashtable] $Arguments,
        [string] $ScriptPath = $MyInvocation.PSCommandPath
    )

    if (Test-SetupAdmin)
    {
        return
    }
    if (-not $ScriptPath)
    {
        throw 'Assert-SetupAdmin: call it from a script file, or pass -ScriptPath.'
    }

    $done = (Get-Item -Path ('env:{0}' -f $script:RerunVariable) -ErrorAction SilentlyContinue).Value
    if ($done -and (($done -split ',') -contains 'admin'))
    {
        throw 'Assert-SetupAdmin: the elevated rerun is still not running as administrator.'
    }

    if ($null -eq $Arguments)
    {
        $Arguments = @{}
        $caller = Get-PSCallStack | Select-Object -Skip 1 -First 1
        if ($caller)
        {
            $bound = $caller.InvocationInfo.BoundParameters
            foreach ($key in $bound.Keys)
            {
                $Arguments[$key] = $bound[$key]
            }
        }
    }

    $argumentFile = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ('PwshSetup-{0}.clixml' -f [guid]::NewGuid())
    ConvertTo-SetupPortableArgument -Arguments $Arguments | Export-Clixml -LiteralPath $argumentFile

    $marker = (@($done, 'admin') | Where-Object -FilterScript { $_ }) -join ','
    $command = Get-SetupRerunCommand -ScriptPath $ScriptPath -ArgumentFile $argumentFile -Marker $marker
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $pwsh = (Get-Process -Id $PID).Path

    Write-SetupBootstrapLog -Message 'Restarting the script as administrator (UAC)...'
    try
    {
        # Not $arguments: variable names ignore case, so it would be the typed [hashtable] $Arguments parameter.
        $terminal = Find-SetupTerminal
        if ($terminal)
        {
            $terminalArguments = Get-SetupTerminalArgument -Pwsh $pwsh -EncodedCommand $encoded
            Start-Process -FilePath $terminal -ArgumentList $terminalArguments -Verb RunAs -ErrorAction Stop
        }
        else
        {
            $pwshArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded)
            Start-Process -FilePath $pwsh -ArgumentList $pwshArguments -Verb RunAs -ErrorAction Stop
        }
    }
    catch
    {
        Remove-Item -LiteralPath $argumentFile -Force -ErrorAction SilentlyContinue
        throw ('Assert-SetupAdmin: setup needs administrator rights, and elevation was not granted. {0}' -f $_.Exception.Message)
    }

    Write-SetupBootstrapLog -Message 'Carrying on in the elevated window.'
    exit 0
}

Export-ModuleMember -Function Assert-SetupAdmin, Test-SetupAdmin
