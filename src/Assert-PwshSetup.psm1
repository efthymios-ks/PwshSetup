<#
.SYNOPSIS
    Public: Assert-PwshSetup, which runs the calling script on pwsh 7.2+ with the latest PwshSetup.
.DESCRIPTION
    Stays Windows PowerShell 5.1 syntax and plain ASCII throughout: the build merges this file into the module's loader,
    and the loader is what Windows PowerShell imports.
    Internal helpers carry a SetupBoot prefix, so they stay clear of every other PwshSetup function.
#>
#Requires -Version 5.1

$script:SetupBootMinPwsh = [version]'7.2'
$script:SetupBootRerunVariable = 'PWSHSETUP_RERUN'
$script:SetupBootBuildInfoUri = 'https://aka.ms/pwsh-buildinfo-stable'
$script:SetupBootReleaseUri = 'https://github.com/PowerShell/PowerShell/releases/download/v{0}/{1}'
$script:SetupBootTimeoutSeconds = 10
$script:SetupBootMsiSuccessCodes = @(0, 3010)
$script:SetupBootMsiRestartCode = 3010

function Write-SetupBootLog
{
    # Yellow: an action that changes the system. DarkYellow: its outcome, or a skip.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Runs before PwshAnsi can draw, possibly on Windows PowerShell.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message,
        [switch] $Outcome
    )

    $color = 'Yellow'
    if ($Outcome)
    {
        $color = 'DarkYellow'
    }
    Write-Host -Object ('[PwshSetup] {0}' -f $Message) -ForegroundColor $color
}

function ConvertTo-SetupBootEncodedCommand
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Command
    )

    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
}

function ConvertTo-SetupBootVersion
{
    # The first three numbers of a version string, or $null.
    [CmdletBinding()]
    [OutputType([version])]
    param(
        [AllowNull()] [AllowEmptyString()] [string] $Value
    )

    if (-not $Value)
    {
        return $null
    }
    $match = [regex]::Match($Value, '^v?(\d+)\.(\d+)\.(\d+)')
    if (-not $match.Success)
    {
        return $null
    }
    return [version]('{0}.{1}.{2}' -f $match.Groups[1].Value, $match.Groups[2].Value, $match.Groups[3].Value)
}

function Enable-SetupBootTls12
{
    [CmdletBinding()]
    param()

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

function Test-SetupBootElevated
{
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object -TypeName 'Security.Principal.WindowsPrincipal' -ArgumentList $identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SetupBootPwshVersion
{
    # The file version first, which starts no process; a probe run only when that is missing.
    [CmdletBinding()]
    [OutputType([version])]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path))
    {
        return $null
    }
    $version = $null
    try
    {
        $version = ConvertTo-SetupBootVersion -Value (Get-Item -LiteralPath $Path).VersionInfo.FileVersion
    }
    catch
    {
        $version = $null
    }
    if ($version)
    {
        return $version
    }

    $probe = ConvertTo-SetupBootEncodedCommand -Command '[string]$PSVersionTable.PSVersion'
    try
    {
        $output = & $Path -NoProfile -NonInteractive -EncodedCommand $probe 2>$null | Select-Object -Last 1
        return (ConvertTo-SetupBootVersion -Value $output)
    }
    catch
    {
        return $null
    }
}

function Find-SetupBootPwsh
{
    # The newest pwsh on this machine at or above the minimum, as Path and Version, or $null.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $candidates = @(Get-Command -Name 'pwsh' -CommandType Application -All -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Source)
    if ($env:ProgramFiles)
    {
        $candidates += Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\7\pwsh.exe'
    }
    if ($env:LOCALAPPDATA)
    {
        $candidates += Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\pwsh.exe'
    }

    $best = $null
    foreach ($path in ($candidates | Select-Object -Unique))
    {
        $version = Get-SetupBootPwshVersion -Path $path
        if (-not $version -or $version -lt $script:SetupBootMinPwsh)
        {
            continue
        }
        if ($best -and $version -le $best.Version)
        {
            continue
        }
        $best = [pscustomobject]@{
            Path    = $path
            Version = $version
        }
    }
    return $best
}

function Get-SetupBootLatestPwshVersion
{
    # The latest stable pwsh release. Throws when it cannot be checked.
    [CmdletBinding()]
    [OutputType([version])]
    param()

    Enable-SetupBootTls12
    $requestArguments = @{
        Uri             = $script:SetupBootBuildInfoUri
        UseBasicParsing = $true
        TimeoutSec      = $script:SetupBootTimeoutSeconds
        ErrorAction     = 'Stop'
    }
    $info = Invoke-RestMethod @requestArguments
    return [version]([string]$info.ReleaseTag).TrimStart('v')
}

function Get-SetupBootArchitecture
{
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $architecture = $env:PROCESSOR_ARCHITEW6432
    if (-not $architecture)
    {
        $architecture = $env:PROCESSOR_ARCHITECTURE
    }
    switch ($architecture)
    {
        'ARM64'
        {
            return 'arm64'
        }
        'x86'
        {
            return 'x86'
        }
        default
        {
            return 'x64'
        }
    }
}

function Install-SetupBootPwsh
{
    # The official MSI: Program Files, PATH, Start menu and Microsoft Update. Only msiexec is elevated, one UAC prompt,
    # never the script. Restart Manager stays on: other open pwsh windows close gracefully, the PC never restarts.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [version] $Version
    )

    $name = 'PowerShell-{0}-win-{1}.msi' -f $Version, (Get-SetupBootArchitecture)
    $uri = $script:SetupBootReleaseUri -f $Version, $name
    $msi = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath $name
    $msiArguments = @(
        '/i'
        ('"{0}"' -f $msi)
        '/quiet'
        '/norestart'
        'ADD_PATH=1'
        'USE_MU=1'
        'ENABLE_MU=1'
    )

    Enable-SetupBootTls12
    try
    {
        Write-SetupBootLog -Message ('Downloading {0}...' -f $name)
        Invoke-WebRequest -Uri $uri -OutFile $msi -UseBasicParsing -ErrorAction Stop

        $startArguments = @{
            FilePath     = 'msiexec.exe'
            ArgumentList = $msiArguments
            Wait         = $true
            PassThru     = $true
            ErrorAction  = 'Stop'
        }
        if (Test-SetupBootElevated)
        {
            Write-SetupBootLog -Message ('Running the PowerShell {0} installer...' -f $Version)
        }
        else
        {
            Write-SetupBootLog -Message ('Requesting administrator rights to install PowerShell {0} (UAC)...' -f $Version)
            $startArguments.Verb = 'RunAs'
        }

        $process = Start-Process @startArguments
        if ($process.ExitCode -notin $script:SetupBootMsiSuccessCodes)
        {
            throw ('msiexec exited with {0}.' -f $process.ExitCode)
        }
        if ($process.ExitCode -eq $script:SetupBootMsiRestartCode)
        {
            Write-SetupBootLog -Message ('PowerShell {0} installed; a restart finishes it.' -f $Version) -Outcome
        }
        else
        {
            Write-SetupBootLog -Message ('PowerShell {0} installed.' -f $Version) -Outcome
        }
    }
    finally
    {
        Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
    }
}

function Test-SetupBootRerunStage
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Stage
    )

    $done = (Get-Item -Path ('env:{0}' -f $script:SetupBootRerunVariable) -ErrorAction SilentlyContinue).Value
    if (-not $done)
    {
        return $false
    }
    return (($done -split ',') -contains $Stage)
}

function Get-SetupBootModuleStage
{
    # Windows PowerShell and pwsh each load their own copy of PwshSetup, so the update stage is marked per edition:
    # an update in one must not stop the other from updating its own copy.
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return ('module-{0}' -f $PSVersionTable.PSEdition)
}

function ConvertTo-SetupBootPortableArgument
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

function Test-SetupBootClassicConsole
{
    # An interactive window that is neither Windows Terminal nor an editor's terminal. A rerun inside it keeps its
    # font, which lacks the glyphs PwshAnsi draws with.
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($env:WT_SESSION -or $env:TERM_PROGRAM)
    {
        return $false
    }
    try
    {
        return (-not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected))
    }
    catch
    {
        return $false
    }
}

function Find-SetupBootTerminal
{
    # wt.exe on the PATH, or at the per-user WindowsApps alias, or $null. The alias is checked by path because a
    # Windows Terminal installed by this session is not on the PATH this session read at its start.
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

function Install-SetupBootWindowsTerminal
{
    # Per user through winget: app packages install without administrator rights, so no UAC prompt. Throws when
    # winget is missing or fails.
    [CmdletBinding()]
    param()

    $winget = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $winget)
    {
        throw 'winget is not available on this machine.'
    }

    $wingetArguments = @(
        'install'
        '--id'
        'Microsoft.WindowsTerminal'
        '--silent'
        '--accept-source-agreements'
        '--accept-package-agreements'
        '--scope'
        'user'
    )
    Write-SetupBootLog -Message 'Installing Windows Terminal through winget...'
    $process = Start-Process -FilePath $winget.Source -ArgumentList $wingetArguments -Wait -PassThru -NoNewWindow -ErrorAction Stop
    if ($process.ExitCode -ne 0)
    {
        throw ('winget exited with {0}.' -f $process.ExitCode)
    }
    Write-SetupBootLog -Message 'Windows Terminal installed.' -Outcome
}

function Get-SetupBootTerminalTabArgument
{
    # A new tab in the most recent Windows Terminal window, started in the current folder. Windows Terminal splits its
    # commands at semicolons, and a trailing backslash would escape the closing quote, so both are escaped.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Pwsh,
        [Parameter(Mandatory)] [string] $EncodedCommand
    )

    $tab = @('-w', '0', 'new-tab')
    if ($PWD.Provider.Name -eq 'FileSystem')
    {
        $directory = $PWD.ProviderPath.Replace(';', '\;') -replace '\\$', '\\'
        $tab += @('-d', ('"{0}"' -f $directory))
    }
    $tab += @(('"{0}"' -f $Pwsh), '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $EncodedCommand)
    return ($tab -join ' ')
}

function Get-SetupBootRerunCommand
{
    # The stage marker travels inside the command: a Windows Terminal tab is started by the terminal, not by this
    # process, so it does not inherit this environment.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $ScriptPath,
        [Parameter(Mandatory)] [string] $ArgumentFile,
        [Parameter(Mandatory)] [string] $Marker
    )

    $quote = { param($Text) "'" + ($Text -replace "'", "''") + "'" }
    $lines = @(
        ('$env:{0} = {1}' -f $script:SetupBootRerunVariable, (& $quote $Marker))
        ('$p = Import-Clixml -LiteralPath {0}' -f (& $quote $ArgumentFile))
        ('Remove-Item -LiteralPath {0} -Force' -f (& $quote $ArgumentFile))
        ('& {0} @p' -f (& $quote $ScriptPath))
        'exit $LASTEXITCODE'
    )
    return ($lines -join "`n")
}

function Invoke-SetupBootRerun
{
    # Reruns the script and ends this process. Moving to pwsh from a classic console opens a Windows Terminal tab
    # instead, installing Windows Terminal on first use, so the script draws with a font that has the glyphs.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Pwsh,
        [Parameter(Mandatory)] [string] $ScriptPath,
        [Parameter(Mandatory)] [string] $Stage,
        [hashtable] $Arguments = @{}
    )

    $argumentFile = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ('PwshSetup-{0}.clixml' -f [guid]::NewGuid())
    ConvertTo-SetupBootPortableArgument -Arguments $Arguments | Export-Clixml -LiteralPath $argumentFile

    $done = (Get-Item -Path ('env:{0}' -f $script:SetupBootRerunVariable) -ErrorAction SilentlyContinue).Value
    $marker = (@($done, $Stage) | Where-Object -FilterScript { $_ }) -join ','
    $command = Get-SetupBootRerunCommand -ScriptPath $ScriptPath -ArgumentFile $argumentFile -Marker $marker
    $encoded = ConvertTo-SetupBootEncodedCommand -Command $command

    $terminal = $null
    if ($Stage -eq 'pwsh' -and (Test-SetupBootClassicConsole))
    {
        $terminal = Find-SetupBootTerminal
        if (-not $terminal)
        {
            try
            {
                Install-SetupBootWindowsTerminal
                $terminal = Find-SetupBootTerminal
            }
            catch
            {
                Write-SetupBootLog -Message ('Windows Terminal unavailable, staying in this window: {0}' -f $_.Exception.Message)
            }
        }
    }
    if ($terminal)
    {
        Write-SetupBootLog -Message ('Restarting the script in a Windows Terminal tab with {0}...' -f $Pwsh) -Outcome
        Start-Process -FilePath $terminal -ArgumentList (Get-SetupBootTerminalTabArgument -Pwsh $Pwsh -EncodedCommand $encoded)
        exit 0
    }

    $reason = 'to load the new PwshSetup'
    if ($Stage -eq 'pwsh')
    {
        $reason = 'in {0}' -f $Pwsh
    }
    Write-SetupBootLog -Message ('Restarting the script {0}...' -f $reason) -Outcome

    Set-Item -Path ('env:{0}' -f $script:SetupBootRerunVariable) -Value $marker
    & $Pwsh -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded
    exit $LASTEXITCODE
}

function Update-SetupBootPwsh
{
    # The pwsh 7.2+ to rerun under, or $null when this host already qualifies. Installs only when no pwsh 7.2+ is
    # found at all; never updates an existing one.
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($PSVersionTable.PSVersion -ge $script:SetupBootMinPwsh)
    {
        return $null
    }

    $current = Find-SetupBootPwsh
    if ($current)
    {
        return $current.Path
    }

    try
    {
        $latest = Get-SetupBootLatestPwshVersion
        Write-SetupBootLog -Message ('PowerShell {0}+ not found. Installing PowerShell {1}...' -f $script:SetupBootMinPwsh, $latest)
        Install-SetupBootPwsh -Version $latest
        $installed = Find-SetupBootPwsh
        if (-not $installed)
        {
            throw ('PowerShell {0} was installed but cannot be found.' -f $latest)
        }
        return $installed.Path
    }
    catch
    {
        throw ('PowerShell {0}+ is missing and could not be installed: {1}' -f $script:SetupBootMinPwsh, $_.Exception.Message)
    }
}

function Update-SetupBootModule
{
    # $true when a newer PwshSetup was installed and the script must rerun to load it. A failed check or install logs
    # a warning and returns $false; it never throws.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [version] $Current
    )

    if (Test-SetupBootRerunStage -Stage (Get-SetupBootModuleStage))
    {
        return $false
    }

    $latest = $null
    try
    {
        $latest = [version](Find-Module -Name 'PwshSetup' -ErrorAction Stop).Version
        if ($latest -le $Current)
        {
            return $false
        }

        Write-SetupBootLog -Message ('Updating PwshSetup {0} -> {1}...' -f $Current, $latest)
        Install-Module -Name 'PwshSetup' -RequiredVersion $latest -Scope CurrentUser -Force -ErrorAction Stop
        Write-SetupBootLog -Message ('PwshSetup {0} installed.' -f $latest) -Outcome
        return $true
    }
    catch
    {
        if ($latest -and $latest -gt $Current)
        {
            Write-SetupBootLog -Message ('Failed to update PwshSetup: {0} Carrying on with {1}.' -f $_.Exception.Message, $Current)
        }
        return $false
    }
}

function Assert-PwshSetup
{
    <#
    .SYNOPSIS
        Ensures the calling script runs on pwsh 7.2+ with the latest PwshSetup.
    .DESCRIPTION
        1. Unless -SkipUpdate, checks the gallery for a newer PwshSetup and reruns the script to load it when one is
           found. Windows PowerShell and pwsh keep separate copies, so each edition updates its own.
        2. On Windows PowerShell, reruns the script on pwsh 7.2+, installing pwsh first when none is present.
        Already on pwsh 7.2+ with the latest PwshSetup, or -SkipUpdate: returns at once.
        A failed gallery check or update logs a warning and carries on.
    .PARAMETER Arguments
        Parameters to pass to the rerun. Defaults to the bound parameters of the calling script.
    .PARAMETER ScriptPath
        Script to rerun. Defaults to the calling script.
    .PARAMETER SkipUpdate
        Skip the gallery check.
    .EXAMPLE
        Assert-PwshSetup
    .EXAMPLE
        Assert-PwshSetup -SkipUpdate
    #>
    [CmdletBinding()]
    param(
        [hashtable] $Arguments,
        [string] $ScriptPath = $MyInvocation.PSCommandPath,
        [switch] $SkipUpdate
    )

    if (-not $ScriptPath)
    {
        throw 'Assert-PwshSetup: call it from a script file, or pass -ScriptPath.'
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

    # The update comes first: on Windows PowerShell the move to pwsh ends this process, and the pwsh run only ever
    # sees its own copy, so this is the one chance to update this edition's.
    if (-not $SkipUpdate -and (Update-SetupBootModule -Current $MyInvocation.MyCommand.Module.Version))
    {
        $rerunArguments = @{
            Pwsh       = (Get-Process -Id $PID).Path
            ScriptPath = $ScriptPath
            Stage      = Get-SetupBootModuleStage
            Arguments  = $Arguments
        }
        Invoke-SetupBootRerun @rerunArguments
    }

    $pwsh = Update-SetupBootPwsh
    if ($pwsh)
    {
        Invoke-SetupBootRerun -Pwsh $pwsh -ScriptPath $ScriptPath -Stage 'pwsh' -Arguments $Arguments
    }
}

Export-ModuleMember -Function Assert-PwshSetup
