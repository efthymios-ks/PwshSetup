<#
.SYNOPSIS
    Copies the local module builds and a setup folder into the test machine, and starts the setup there.
.DESCRIPTION
    Copies the newest local builds of PwshSetup and PwshAnsi to C:\Program Files\WindowsPowerShell\Modules in the
    machine, where Windows PowerShell and pwsh both find them, so versions not published yet can be tried.
    Copies the setup folder to C:\Setup.
    Zero-arg run: if the machine does not exist, New-SetupTestVm.ps1 creates it; the Clean checkpoint is restored; the
    builds and the setup folder are copied in; Setup.ps1 is started on the desktop from Windows PowerShell as on a fresh
    machine; the machine window is opened. The -No* switches opt out of each.
.PARAMETER VmName
    The machine. New-SetupTestVm.ps1 is called with the same name when it does not exist.
.PARAMETER SetupPath
    The folder copied to C:\Setup: a Setup.ps1 and its steps folder.
.PARAMETER ModulePath
    Module build folders, each <Name>\<Version>. Defaults to the newest builds in this repository's artifacts and in
    the PwshAnsi repository beside it.
.PARAMETER NoReset
    Keep the current state; do not revert to the Clean checkpoint.
.PARAMETER NoRun
    Do not start Setup.ps1 on the desktop.
.PARAMETER NoConnect
    Do not open the machine's window.
.EXAMPLE
    .\hyperv\Sync-SetupTestVm.ps1
.EXAMPLE
    .\hyperv\Sync-SetupTestVm.ps1 -NoRun -NoConnect
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9-]{1,40}$')] [string] $VmName = 'PwshSetup-Test',
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })] [string] $SetupPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Setup'),
    [string[]] $ModulePath,
    [switch] $NoReset,
    [switch] $NoRun,
    [switch] $NoConnect
)

if (-not (Get-Module -ListAvailable -Name PwshAnsi | Where-Object -FilterScript { $_.Version -ge [version]'0.1.9' }))
{
    Install-Module -Name PwshAnsi -Scope CurrentUser -MinimumVersion '0.1.9' -Force -AllowClobber
}
Import-Module -Name PwshAnsi -MinimumVersion '0.1.9'
Assert-PwshAnsi
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\Assert-SetupAdmin.psm1') -Force -DisableNameChecking
Assert-SetupAdmin

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestVm.psm1') -Force
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$GuestModuleRoot = 'C:\Program Files\WindowsPowerShell\Modules'
$GuestSetupPath = 'C:\Setup'
$StartTaskName = 'PwshSetup-Start'

function Find-ModuleBuild
{
    # Newest <Version> subfolder, or nothing when the root is absent.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $ArtifactRoot
    )

    if (-not (Test-Path -LiteralPath $ArtifactRoot))
    {
        return
    }
    $newest = Get-ChildItem -LiteralPath $ArtifactRoot -Directory |
        Where-Object -FilterScript { $_.Name -as [version] } |
        Sort-Object -Property { [version]$_.Name } -Descending |
        Select-Object -First 1
    if ($newest)
    {
        return $newest.FullName
    }
}

Assert-TestVmHost
if (-not (Get-VM -Name $VmName -ErrorAction Ignore))
{
    # This window is elevated already, so the call raises no UAC prompt. A script called with & that exits only sets
    # $LASTEXITCODE, so it is checked here; set to 0 first, since a script that never exits leaves it unset.
    $global:LASTEXITCODE = 0
    & (Join-Path -Path $PSScriptRoot -ChildPath 'New-SetupTestVm.ps1') -VmName $VmName
    if ($LASTEXITCODE -ne 0)
    {
        throw ('New-SetupTestVm.ps1 exited with code {0}. See the output above.' -f $LASTEXITCODE)
    }
    if (-not (Get-VM -Name $VmName -ErrorAction Ignore))
    {
        throw ('Could not create {0}. See the output above.' -f $VmName)
    }
}
$credential = Read-TestVmCredential -VmName $VmName

if (-not $ModulePath)
{
    $repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $ModulePath = @(
        Find-ModuleBuild -ArtifactRoot (Join-Path -Path $repositoryRoot -ChildPath 'artifacts\PwshSetup')
        Find-ModuleBuild -ArtifactRoot (Join-Path -Path (Split-Path -Path $repositoryRoot -Parent) -ChildPath 'PwshAnsi\artifacts\PwshAnsi')
    ) | Where-Object -FilterScript { $_ }
}
$builds = @(foreach ($path in @($ModulePath))
{
    # @($null) holds one $null item, so no builds would still count as one.
    if (-not $path)
    {
        continue
    }
    [pscustomobject]@{
        Name    = Split-Path -Path (Split-Path -Path $path -Parent) -Leaf
        Version = Split-Path -Path $path -Leaf
        Path    = $path
    }
})

Clear-Host
Format-AnsiRule -Title '[BrightWhite]PwshSetup test machine[/]' -Alignment Left -LineColor DarkGray | Out-AnsiHost
$moduleText = '[DarkGray]none, the machine installs from the PowerShell Gallery[/]'
if ($builds.Count -gt 0)
{
    $moduleText = ($builds | ForEach-Object -Process { '{0} {1}' -f $_.Name, $_.Version }) -join ', '
}
$header = @(
    , [string[]]@('[DarkGray]Machine[/]', $VmName)
    , [string[]]@('[DarkGray]Modules[/]', $moduleText)
    , [string[]]@('[DarkGray]Setup  [/]', ('{0} -> {1}' -f $SetupPath, $GuestSetupPath))
)
Format-AnsiGrid -Rows $header -Padding 3 | Out-AnsiHost
[Console]::WriteLine()

$remote = @{ Session = $null }
$resetMachine = {
    # A clearer message than Hyper-V's own when the checkpoint is missing, which means the machine was never finished.
    if (-not (Get-VMSnapshot -VMName $VmName -Name $CheckpointName -ErrorAction Ignore))
    {
        throw ('No {0} checkpoint on {1}. Run Remove-SetupTestVm.ps1, then this script again to rebuild it.' -f $CheckpointName, $VmName)
    }
    Restore-VMCheckpoint -VMName $VmName -Name $CheckpointName -Confirm:$false
}
$waitForWindows = {
    param($Task)

    Start-TestVm -VmName $VmName
    Wait-TestVmWindows -VmName $VmName -Credential $credential -Task $Task
    $remote.Session = New-PSSession -VMName $VmName -Credential $credential
}
$copyModules = {
    foreach ($build in $builds)
    {
        $target = Join-Path -Path $GuestModuleRoot -ChildPath ('{0}\{1}' -f $build.Name, $build.Version)
        Invoke-Command -Session $remote.Session -ArgumentList $target -ScriptBlock {
            param($Target)
            Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction Ignore
            $null = New-Item -ItemType Directory -Path $Target -Force
        }
        Copy-Item -Path (Join-Path -Path $build.Path -ChildPath '*') -Destination $target -ToSession $remote.Session -Recurse -Force
    }
}
$verifyBaseline = {
    # The Clean checkpoint holds PowerShell 7 and PwshAnsi. A missing one means the checkpoint is not what this
    # script expects, so it stops instead of installing them again on every run.
    Invoke-Command -Session $remote.Session -ScriptBlock {
        $pwshPath = Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\7\pwsh.exe'
        if (-not (Test-Path -LiteralPath $pwshPath))
        {
            throw 'PowerShell 7 not found on the test machine. Remove-SetupTestVm.ps1 and rebuild to re-bake the Clean checkpoint.'
        }
        if (-not (Get-Module -ListAvailable -Name PwshAnsi))
        {
            throw 'PwshAnsi not found on the test machine. Remove-SetupTestVm.ps1 and rebuild to re-bake the Clean checkpoint.'
        }
    }
}
$copySetup = {
    Invoke-Command -Session $remote.Session -ArgumentList $GuestSetupPath -ScriptBlock {
        param($Target)
        Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction Ignore
        $null = New-Item -ItemType Directory -Path $Target -Force
    }
    Copy-Item -Path (Join-Path -Path $SetupPath -ChildPath '*') -Destination $GuestSetupPath -ToSession $remote.Session -Recurse -Force
}
$startSetup = {
    Invoke-Command -Session $remote.Session -ArgumentList $credential.UserName, $StartTaskName, $GuestSetupPath -ScriptBlock {
        param($UserName, $TaskName, $SetupFolder)

        $user = '{0}\{1}' -f $env:COMPUTERNAME, $UserName
        $actionArguments = @{
            Execute          = 'powershell.exe'
            Argument         = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path -Path $SetupFolder -ChildPath 'Setup.ps1'))
            WorkingDirectory = $SetupFolder
        }
        $taskArguments = @{
            TaskName  = $TaskName
            Action    = New-ScheduledTaskAction @actionArguments
            Principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
            Force     = $true
        }
        $null = Register-ScheduledTask @taskArguments
        Start-ScheduledTask -TaskName $TaskName
    }
}

$tasks = [System.Collections.Generic.List[hashtable]]::new()
if (-not $NoReset)
{
    $tasks.Add(@{ Name = ('Go back to the {0} checkpoint' -f $CheckpointName); Script = $resetMachine })
}
$tasks.Add(@{ Name = 'Start Windows and wait for the sign-in'; Script = $waitForWindows })
if ($builds.Count -gt 0)
{
    $tasks.Add(@{ Name = 'Copy the module builds'; Script = $copyModules })
}
$tasks.Add(@{ Name = 'Verify the PowerShell baseline (pwsh, PwshAnsi)'; Script = $verifyBaseline })
$tasks.Add(@{ Name = ('Copy the setup folder to {0}' -f $GuestSetupPath); Script = $copySetup })
if (-not $NoRun)
{
    $tasks.Add(@{ Name = 'Start Setup.ps1 on the desktop'; Script = $startSetup })
}

try
{
    Invoke-AnsiTask -Task $tasks.ToArray() -Show Both -ProgressShow Percent
}
catch
{
    Format-AnsiException -Exception $_ | Out-AnsiHost
    exit 1
}
finally
{
    if ($remote.Session)
    {
        Remove-PSSession -Session $remote.Session
    }
}

if (-not $NoConnect)
{
    Start-Process -FilePath 'vmconnect.exe' -ArgumentList 'localhost', $VmName
}
[Console]::WriteLine()
Format-AnsiText -Message ('[BrightGreen]{0} is in sync.[/]' -f $VmName) | Out-AnsiHost
