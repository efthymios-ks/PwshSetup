<#
.SYNOPSIS
    Installs Visual Studio 2026 Community with the workloads given.
.PARAMETER Workload
    Workload names as Visual Studio calls them, such as NetWeb, ManagedDesktop, Azure, Data. Each one installs through
    its own Chocolatey package, visualstudio2026-workload-<name>.
.EXAMPLE
    Use-SetupTemplate -Name 'Install-VisualStudio2026' -Parameter @{ Workload = 'NetWeb', 'ManagedDesktop', 'Azure' }
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()] [string[]] $Workload = @('NetWeb', 'ManagedDesktop')
)

$packages = @($Workload | ForEach-Object -Process { 'visualstudio2026-workload-{0}' -f $_.ToLowerInvariant() })
$workloadIds = @($Workload | ForEach-Object -Process { 'Microsoft.VisualStudio.Workload.{0}' -f $_ })

$step = @{
    Name            = 'Install Visual Studio 2026 Community'
    RequiresRestart = $true
    Test            = {
        $vswhere = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (-not (Test-Path -LiteralPath $vswhere))
        {
            return $false
        }
        $found = & $vswhere -version '[18.0,19.0)' -products 'Microsoft.VisualStudio.Product.Community' `
            -requires $workloadIds -property 'installationPath'
        [bool]$found
    }
    Action          = {
        Install-ChocoPackage -Name 'visualstudio2026community'
        foreach ($package in $packages)
        {
            Install-ChocoPackage -Name $package
        }
    }
}
New-SetupStep @step
