<#
.SYNOPSIS
    Removes the test machine with its disks, checkpoints and stored password.
.DESCRIPTION
    Turns the machine off, removes it from Hyper-V, deletes every disk in its chain and the password that
    New-SetupTestVm.ps1 stored. Does not prompt; -WhatIf shows what it would remove.
.PARAMETER VmName
    The machine, as New-SetupTestVm.ps1 created it.
.EXAMPLE
    .\hyperv\Remove-SetupTestVm.ps1
.EXAMPLE
    .\hyperv\Remove-SetupTestVm.ps1 -VmName 'PwshSetup-Win10'
.EXAMPLE
    .\hyperv\Remove-SetupTestVm.ps1 -WhatIf
#>
#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidatePattern('^[A-Za-z0-9-]{1,40}$')] [string] $VmName = 'PwshSetup-Test'
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
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Assert-TestVmHost
$vm = Get-VM -Name $VmName -ErrorAction Ignore
if (-not $vm)
{
    Format-AnsiText -Message ('[DarkGray]No machine named {0}.[/]' -f $VmName) | Out-AnsiHost
    Remove-TestVmCredential -VmName $VmName
    return
}

if (-not $PSCmdlet.ShouldProcess($VmName, 'Remove the machine, its disks and its stored password'))
{
    return
}

# Every disk from the current one down to the base, so checkpoint disks go too.
$disks = [System.Collections.Generic.List[string]]::new()
foreach ($drive in (Get-VMHardDiskDrive -VMName $VmName))
{
    $path = $drive.Path
    while ($path)
    {
        $disks.Add($path)
        $path = (Get-VHD -Path $path).ParentPath
    }
}

if ($vm.State -ne 'Off')
{
    Stop-VM -Name $VmName -TurnOff -Force
}
Remove-VM -Name $VmName -Force
foreach ($disk in $disks)
{
    Remove-Item -LiteralPath $disk -Force -ErrorAction Ignore
}
Remove-TestVmCredential -VmName $VmName

Format-AnsiText -Message ('[BrightGreen]✔[/] {0} removed, with {1} disk file(s).' -f $VmName, $disks.Count) | Out-AnsiHost
