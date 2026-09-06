#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Setup.Core.Tests.ps1
# Pester 5 tests for the shared building blocks. Log output is captured off the
# Information stream (Write-Host redirect 6>&1); step discovery runs against files
# written into TestDrive.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Setup.Core.psm1') -Force -DisableNameChecking

    function New-StepFile {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Name,
            [int]$Order = 0
        )

        $orderArgument = if ($Order -gt 0) { "-Order $Order" } else { '' }

        Set-Content -LiteralPath $Path -Value @"
Import-Module '$($script:src -replace "'", "''")\Setup.Core.psm1' -Force -DisableNameChecking
New-SetupStep -Name '$Name' $orderArgument -Action { '$Name' }
"@
    }
}

Describe 'Write-SetupLog' {
    It 'writes the message as given' {
        $output = Write-SetupLog 'hello' 6>&1

        "$output" | Should -Be 'hello'
    }

    It 'prefixes the level and the time with -Timestamp' {
        $output = Write-SetupLog 'hello' -Level Warning -Timestamp 6>&1

        "$output" | Should -Match '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[WARNING\] hello$'
    }

    It 'accepts <Level>' -ForEach @(
        @{ Level = 'Info' }
        @{ Level = 'Warning' }
        @{ Level = 'Error' }
        @{ Level = 'Success' }
        @{ Level = 'None' }
    ) {
        { Write-SetupLog 'hello' -Level $Level 6>&1 } | Should -Not -Throw
    }

    It 'rejects an unknown level' {
        { Write-SetupLog 'hello' -Level 'Chatty' } | Should -Throw
    }

    It 'takes the message from the pipeline' {
        $output = 'piped' | Write-SetupLog 6>&1

        "$output" | Should -Be 'piped'
    }
}

Describe 'New-SetupStep' {
    It 'carries the name, the order and the blocks it was given' {
        $step = New-SetupStep -Name 'Install thing' -Order 20 -Test { $true } -Action { 'ran' }

        $step.Name | Should -Be 'Install thing'
        $step.Order | Should -Be 20
        & $step.Test | Should -BeTrue
        & $step.Action | Should -Be 'ran'
    }

    It 'is a Setup.Step' {
        $step = New-SetupStep -Name 'Install thing' -Action { }

        $step.PSObject.TypeNames | Should -Contain 'Setup.Step'
    }

    It 'defaults the order to 0, the test to nothing and no restart' {
        $step = New-SetupStep -Name 'Install thing' -Action { }

        $step.Order | Should -Be 0
        $step.Test | Should -BeNullOrEmpty
        $step.RequiresRestart | Should -BeFalse
        $step.Path | Should -BeNullOrEmpty
    }

    It 'records -RequiresRestart' {
        $step = New-SetupStep -Name 'Install thing' -Action { } -RequiresRestart

        $step.RequiresRestart | Should -BeTrue
    }

    It 'rejects an empty name' {
        { New-SetupStep -Name '' -Action { } } | Should -Throw
    }

    It 'rejects a missing action' {
        { New-SetupStep -Name 'Install thing' } | Should -Throw
    }

    It 'rejects a negative order' {
        { New-SetupStep -Name 'Install thing' -Action { } -Order -1 } | Should -Throw
    }
}

Describe 'Get-SetupStep' {
    BeforeEach {
        $script:stepPath = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:stepPath | Out-Null
    }

    It 'returns every step file in the folder' {
        New-StepFile -Path (Join-Path $script:stepPath '010-First.step.ps1') -Name 'First'
        New-StepFile -Path (Join-Path $script:stepPath '020-Second.step.ps1') -Name 'Second'

        $steps = Get-SetupStep -Path $script:stepPath

        $steps.Count | Should -Be 2
    }

    It 'takes the order from the leading number in the file name' {
        New-StepFile -Path (Join-Path $script:stepPath '030-Third.step.ps1') -Name 'Third'
        New-StepFile -Path (Join-Path $script:stepPath '010-First.step.ps1') -Name 'First'

        $steps = Get-SetupStep -Path $script:stepPath

        $steps[0].Name | Should -Be 'First'
        $steps[0].Order | Should -Be 10
        $steps[1].Order | Should -Be 30
    }

    It 'keeps an order the step states itself' {
        New-StepFile -Path (Join-Path $script:stepPath '010-First.step.ps1') -Name 'First' -Order 999
        New-StepFile -Path (Join-Path $script:stepPath '020-Second.step.ps1') -Name 'Second'

        $steps = Get-SetupStep -Path $script:stepPath

        $steps[0].Name | Should -Be 'Second'
        $steps[1].Order | Should -Be 999
    }

    It 'records where each step came from' {
        $file = Join-Path $script:stepPath '010-First.step.ps1'
        New-StepFile -Path $file -Name 'First'

        $step = Get-SetupStep -Path $script:stepPath

        $step.Path | Should -Be $file
    }

    It 'ignores files that are not steps' {
        New-StepFile -Path (Join-Path $script:stepPath '010-First.step.ps1') -Name 'First'
        Set-Content -LiteralPath (Join-Path $script:stepPath 'notes.ps1') -Value '"noise"'

        $steps = Get-SetupStep -Path $script:stepPath

        $steps.Count | Should -Be 1
    }

    It 'returns nothing for an empty folder' {
        Get-SetupStep -Path $script:stepPath | Should -BeNullOrEmpty
    }

    It 'throws when a step file returns something else' {
        Set-Content -LiteralPath (Join-Path $script:stepPath '010-Broken.step.ps1') -Value '"not a step"'

        { Get-SetupStep -Path $script:stepPath } | Should -Throw '*did not return a step object*'
    }

    It 'throws when the folder is missing' {
        { Get-SetupStep -Path (Join-Path $TestDrive 'nowhere') } | Should -Throw '*Step folder not found*'
    }
}

Describe 'Test-SetupCommand' {
    It 'finds a command that exists' {
        Test-SetupCommand 'Get-Command' | Should -BeTrue
    }

    It 'reports a command that does not' {
        Test-SetupCommand 'Get-NoSuchCommandAnywhere' | Should -BeFalse
    }

    It 'rejects an empty name' {
        { Test-SetupCommand '' } | Should -Throw
    }
}

Describe 'Test-SetupElevation' {
    It 'answers with a boolean' {
        Test-SetupElevation | Should -BeOfType [bool]
    }
}
