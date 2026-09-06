#Requires -Version 7.2

<#
.SYNOPSIS
    Runs the setup steps in the steps folder, elevating and resuming across reboots.

.DESCRIPTION
    Loads every *.step.ps1 under -StepPath in order, skips the ones that report
    nothing to do, runs the rest, and reboots where a step asks for it — registering
    itself with RunOnce first, so the machine comes back and carries on.

    Relaunches itself elevated when it is not already running as administrator.
    The whole run is transcribed to the logs folder.

.PARAMETER StepPath
    Folder holding the step files. Defaults to the steps folder beside this script.

.PARAMETER LogPath
    Folder the transcript is written to. Defaults to ./logs.

.PARAMETER SkipRestart
    Report a needed restart and carry on instead of rebooting.

.PARAMETER SkipElevation
    Do not relaunch elevated; fail instead when the session is not administrator.

.INPUTS
    None.

.OUTPUTS
    Setup.StepResult per step, and the verdict as the exit code.

.EXAMPLE
    ./Invoke-Setup.ps1

.EXAMPLE
    ./Invoke-Setup.ps1 -StepPath ./templates -SkipRestart -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$StepPath = (Join-Path -Path $PSScriptRoot -ChildPath 'steps'),

    [ValidateNotNullOrEmpty()]
    [string]$LogPath = (Join-Path -Path $PSScriptRoot -ChildPath 'logs'),

    [switch]$SkipRestart,

    [switch]$SkipElevation
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Import-Module (Join-Path $PSScriptRoot 'src\Setup.Core.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $PSScriptRoot 'src\Invoke-SetupPipeline.psm1') -Force -DisableNameChecking
}

process {
    if (-not (Test-SetupElevation)) {
        if ($SkipElevation) {
            Write-SetupLog 'Setup needs an elevated session.' -Level Error
            exit 1
        }

        Write-SetupLog 'Setup needs an elevated session — relaunching as administrator.' -Level Warning

        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-StepPath', $StepPath)

        if ($SkipRestart) {
            $arguments += '-SkipRestart'
        }

        Start-Process -FilePath 'pwsh.exe' -ArgumentList $arguments -Verb RunAs
        exit 0
    }

    if (-not (Test-Path -LiteralPath $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }

    $logFile = Join-Path $LogPath ('setup-{0}.log' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    Start-Transcript -Path $logFile | Out-Null

    try {
        $results = @(Invoke-SetupPipeline -StepPath $StepPath -ResumeScriptPath $PSCommandPath -SkipRestart:$SkipRestart)
        $results

        $failed = @($results | Where-Object { $_.Outcome -eq 'Failed' })

        if ($failed.Count -gt 0) {
            Write-SetupLog "$($failed.Count) step(s) failed. See $logFile." -Level Error
            exit 1
        }
    }
    finally {
        Stop-Transcript | Out-Null
    }

    exit 0
}
