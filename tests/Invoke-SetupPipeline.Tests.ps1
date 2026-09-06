#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Invoke-SetupPipeline.Tests.ps1
# Pester 5 tests for the runner, driven by the dummy steps under tests/fixtures.
# Nothing on the machine is read or written: the steps only append to a file under
# TestDrive, and the two functions that would touch the machine — the pending-restart
# check and the restart itself — are replaced inside the module scope. Injection is
# used rather than Mock: the runner imports them from another module.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    $script:fixtures = Join-Path $PSScriptRoot 'fixtures'

    Import-Module (Join-Path $script:src 'Setup.Core.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Invoke-SetupPipeline.psm1') -Force -DisableNameChecking
    $script:PipelineModule = Get-Module Invoke-SetupPipeline

    & $script:PipelineModule {
        $script:TestRestartPending = $false
        $script:TestRestartCalls = [System.Collections.Generic.List[string]]::new()

        Set-Item function:script:Test-SetupRestartPending -Value {
            $script:TestRestartPending
        }

        Set-Item function:script:Restart-SetupHost -Value {
            param([string]$ScriptPath, [int]$DelaySeconds = 5)

            $script:TestRestartCalls.Add($ScriptPath)
        }
    }

    function Reset-PipelineState {
        param([bool]$RestartPending = $false)

        & $script:PipelineModule {
            param($restartPending)

            $script:TestRestartPending = $restartPending
            $script:TestRestartCalls.Clear()
        } $RestartPending
    }

    function Get-RestartCall {
        & $script:PipelineModule { $script:TestRestartCalls }
    }

    function New-StepFolder {
        param([AllowEmptyCollection()][string[]]$FileName = @())

        $path = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $path | Out-Null

        foreach ($name in $FileName) {
            Copy-Item -LiteralPath (Join-Path $script:fixtures $name) -Destination $path
        }

        $path
    }

    function Get-Marker {
        if (-not (Test-Path -LiteralPath $env:PWSHSETUP_TEST_LOG)) {
            return @()
        }

        @(Get-Content -LiteralPath $env:PWSHSETUP_TEST_LOG)
    }
}

Describe 'Invoke-SetupPipeline — running steps' {
    BeforeEach {
        Reset-PipelineState
        $env:PWSHSETUP_TEST_LOG = Join-Path $TestDrive ('markers-{0}.log' -f [guid]::NewGuid())
    }

    It 'runs a step whose test says there is work to do' {
        $path = New-StepFolder -FileName '010-Write-Marker.step.ps1'

        $results = Invoke-SetupPipeline -StepPath $path 6>&1 | Where-Object { $_.PSObject.TypeNames -contains 'Setup.StepResult' }

        Get-Marker | Should -Be @('Write marker')
        $results.Outcome | Should -Be 'Completed'
        $results.Name | Should -Be 'Write marker'
    }

    It 'skips a step whose test says it is already done' {
        $path = New-StepFolder -FileName '020-Skip-Marker.step.ps1'

        $results = Invoke-SetupPipeline -StepPath $path 6>&1 | Where-Object { $_.PSObject.TypeNames -contains 'Setup.StepResult' }

        Get-Marker | Should -BeNullOrEmpty
        $results.Outcome | Should -Be 'Skipped'
    }

    It 'runs the steps in order and reports one result each' {
        $path = New-StepFolder -FileName @('010-Write-Marker.step.ps1', '020-Skip-Marker.step.ps1')

        $results = @(Invoke-SetupPipeline -StepPath $path 6>&1 | Where-Object { $_.PSObject.TypeNames -contains 'Setup.StepResult' })

        $results.Count | Should -Be 2
        $results[0].Name | Should -Be 'Write marker'
        $results[1].Name | Should -Be 'Skip marker'
    }

    It 'runs nothing with -WhatIf' {
        $path = New-StepFolder -FileName '010-Write-Marker.step.ps1'

        Invoke-SetupPipeline -StepPath $path -WhatIf 6>&1 | Out-Null

        Get-Marker | Should -BeNullOrEmpty
    }

    It 'says so and returns when the folder holds no steps' {
        $path = New-StepFolder -FileName @()

        $output = Invoke-SetupPipeline -StepPath $path 6>&1

        "$output" | Should -Match 'No steps found'
    }

    It 'throws when the folder is missing' {
        { Invoke-SetupPipeline -StepPath (Join-Path $TestDrive 'nowhere') } | Should -Throw '*Step folder not found*'
    }
}

Describe 'Invoke-SetupPipeline — a step that fails' {
    BeforeEach {
        Reset-PipelineState
        $env:PWSHSETUP_TEST_LOG = Join-Path $TestDrive ('markers-{0}.log' -f [guid]::NewGuid())
    }

    It 'reports the failure and stops the run' {
        $path = New-StepFolder -FileName @('040-Throw-Marker.step.ps1', '010-Write-Marker.step.ps1')

        $results = @(Invoke-SetupPipeline -StepPath $path 6>&1 | Where-Object { $_.PSObject.TypeNames -contains 'Setup.StepResult' })

        $results.Count | Should -Be 2
        $results[0].Outcome | Should -Be 'Completed'
        $results[1].Outcome | Should -Be 'Failed'
        $results[1].Error | Should -Not -BeNullOrEmpty
    }

    It 'writes the failure to the log' {
        $path = New-StepFolder -FileName '040-Throw-Marker.step.ps1'

        $output = Invoke-SetupPipeline -StepPath $path 6>&1

        "$output" | Should -Match 'dummy step failed on purpose'
    }
}

Describe 'Invoke-SetupPipeline — restarts' {
    BeforeEach {
        Reset-PipelineState
        $env:PWSHSETUP_TEST_LOG = Join-Path $TestDrive ('markers-{0}.log' -f [guid]::NewGuid())
    }

    It 'restarts after a step that asks for one, and stops there' {
        $path = New-StepFolder -FileName @('030-Restart-Marker.step.ps1', '010-Write-Marker.step.ps1')

        Invoke-SetupPipeline -StepPath $path -ResumeScriptPath 'C:\resume.ps1' 6>&1 | Out-Null

        Get-RestartCall | Should -Be @('C:\resume.ps1')
        Get-Marker | Should -Be @('Write marker', 'Restart marker')
    }

    It 'carries on with -SkipRestart' {
        $path = New-StepFolder -FileName @('030-Restart-Marker.step.ps1', '010-Write-Marker.step.ps1')

        Invoke-SetupPipeline -StepPath $path -ResumeScriptPath 'C:\resume.ps1' -SkipRestart 6>&1 | Out-Null

        Get-RestartCall | Should -BeNullOrEmpty
        Get-Marker | Should -Be @('Write marker', 'Restart marker')
    }

    It 'carries on when no resume script was given, saying why' {
        $path = New-StepFolder -FileName @('030-Restart-Marker.step.ps1', '010-Write-Marker.step.ps1')

        $output = Invoke-SetupPipeline -StepPath $path 6>&1

        Get-RestartCall | Should -BeNullOrEmpty
        "$output" | Should -Match 'no resume script'
        Get-Marker | Should -Be @('Write marker', 'Restart marker')
    }

    It 'restarts before the first step when one is already pending' {
        Reset-PipelineState -RestartPending $true
        $path = New-StepFolder -FileName '010-Write-Marker.step.ps1'

        Invoke-SetupPipeline -StepPath $path -ResumeScriptPath 'C:\resume.ps1' 6>&1 | Out-Null

        Get-RestartCall | Should -Be @('C:\resume.ps1')
        Get-Marker | Should -BeNullOrEmpty
    }
}
