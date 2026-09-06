#Requires -Version 7.2

# Invoke-SetupPipeline.psm1
# Runs the steps in order: skip what is already done, do what is not, reboot when a step
# asks for it and resume afterwards. One step failing stops the run.

Import-Module (Join-Path $PSScriptRoot 'Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Restart-SetupHost.psm1') -Force -DisableNameChecking

function Invoke-SetupPipeline {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('Setup.StepResult')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$StepPath,

        [ValidateNotNullOrEmpty()]
        [string]$ResumeScriptPath,

        [switch]$SkipRestart
    )

    $steps = @(Get-SetupStep -Path $StepPath)

    if ($steps.Count -eq 0) {
        Write-SetupLog "No steps found under $StepPath." -Level Warning
        return
    }

    $index = 0

    foreach ($step in $steps) {
        $index++

        Write-SetupLog ('[{0}/{1}] {2}' -f $index, $steps.Count, $step.Name) -Level Info

        if (Test-SetupRestartPending) {
            Write-SetupLog 'A restart is already pending; the machine has to come back before this step runs.' -Level Warning

            if (Invoke-SetupRestart -ResumeScriptPath $ResumeScriptPath -SkipRestart:$SkipRestart) {
                return
            }
        }

        if ($step.Test -and -not (& $step.Test)) {
            Write-SetupLog 'Already done, skipping.' -Level None

            [PSCustomObject]@{
                PSTypeName = 'Setup.StepResult'
                Name       = $step.Name
                Outcome    = 'Skipped'
                Error      = $null
            }

            continue
        }

        if (-not $PSCmdlet.ShouldProcess($step.Name, 'Run setup step')) {
            continue
        }

        try {
            & $step.Action

            Write-SetupLog 'Done.' -Level Success

            [PSCustomObject]@{
                PSTypeName = 'Setup.StepResult'
                Name       = $step.Name
                Outcome    = 'Completed'
                Error      = $null
            }
        }
        catch {
            Write-SetupLog "Failed: $($_.Exception.Message)" -Level Error

            [PSCustomObject]@{
                PSTypeName = 'Setup.StepResult'
                Name       = $step.Name
                Outcome    = 'Failed'
                Error      = $_
            }

            return
        }

        if ($step.RequiresRestart -and (Invoke-SetupRestart -ResumeScriptPath $ResumeScriptPath -SkipRestart:$SkipRestart)) {
            return
        }
    }

    Write-SetupLog 'Setup finished.' -Level Success
}

function Invoke-SetupRestart {
    <#
        Reboots and reports whether the run should stop here. Without a resume script
        there is nothing to come back to, so the restart is reported and skipped.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$ResumeScriptPath,

        [switch]$SkipRestart
    )

    if ($SkipRestart) {
        Write-SetupLog 'A restart is needed; skipping it as asked.' -Level Warning
        return $false
    }

    if (-not $ResumeScriptPath) {
        Write-SetupLog 'A restart is needed, but no resume script was given — restart and rerun by hand.' -Level Warning
        return $false
    }

    Restart-SetupHost -ScriptPath $ResumeScriptPath

    $true
}

Export-ModuleMember -Function Invoke-SetupPipeline
