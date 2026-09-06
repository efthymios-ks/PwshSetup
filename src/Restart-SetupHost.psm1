#Requires -Version 7.2

# Restart-SetupHost.psm1
# Reboots that resume: the pipeline registers itself with RunOnce before restarting,
# so the machine comes back and carries on where it stopped.

Import-Module (Join-Path $PSScriptRoot 'Setup.Core.psm1') -Force -DisableNameChecking

$script:SetupRunOncePath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
$script:SetupRunOnceName = 'PwshSetup'

$script:SetupRestartPendingKeys = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'
)

function Test-SetupRestartPending {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    foreach ($key in $script:SetupRestartPendingKeys) {
        if (Test-Path -LiteralPath $key) {
            return $true
        }
    }

    $sessionManager = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    $pendingRenames = Get-ItemProperty -LiteralPath $sessionManager -Name 'PendingFileRenameOperations' -ErrorAction Ignore

    [bool]$pendingRenames
}

function Register-SetupRestart {
    <#
        Writes the RunOnce entry that relaunches the pipeline after the reboot.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Script to resume was not found: $ScriptPath"
    }

    $command = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Resolve-Path -LiteralPath $ScriptPath).Path

    if ($PSCmdlet.ShouldProcess($script:SetupRunOncePath, "Register $script:SetupRunOnceName")) {
        Set-ItemProperty -LiteralPath $script:SetupRunOncePath -Name $script:SetupRunOnceName -Value $command
    }
}

function Unregister-SetupRestart {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param()

    if ($PSCmdlet.ShouldProcess($script:SetupRunOncePath, "Remove $script:SetupRunOnceName")) {
        Remove-ItemProperty -LiteralPath $script:SetupRunOncePath -Name $script:SetupRunOnceName -ErrorAction Ignore
    }
}

function Restart-SetupHost {
    <#
        Registers the resume entry, then reboots. Nothing after this call runs.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath,

        [ValidateRange(0, 3600)]
        [int]$DelaySeconds = 5
    )

    Register-SetupRestart -ScriptPath $ScriptPath

    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Restart')) {
        return
    }

    Write-SetupLog "Restarting in $DelaySeconds seconds..." -Level Warning
    Start-Sleep -Seconds $DelaySeconds
    Restart-Computer -Force
}

Export-ModuleMember -Function Test-SetupRestartPending, Register-SetupRestart, Unregister-SetupRestart, Restart-SetupHost
