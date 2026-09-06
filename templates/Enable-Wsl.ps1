<#
.SYNOPSIS
    Turns on the Windows Subsystem for Linux and the Virtual Machine Platform, without a distribution.
.NOTES
    Docker Desktop and Podman run on it. Inside a Hyper-V machine it needs nested virtualization on the host side.
#>
[CmdletBinding()]
param()

$features = @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')

$step = @{
    Name            = 'Enable WSL'
    RequiresRestart = $true
    Test            = {
        $disabled = $features | Where-Object -FilterScript {
            (Get-WindowsOptionalFeature -Online -FeatureName $_).State -ne 'Enabled'
        }
        @($disabled).Count -eq 0
    }
    Action          = {
        wsl.exe --install --no-distribution *>&1
        if ($LASTEXITCODE -ne 0)
        {
            throw ('wsl --install failed with exit code {0}.' -f $LASTEXITCODE)
        }
    }
}
New-SetupStep @step
