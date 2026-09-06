<#
.SYNOPSIS
    Demo: a step that fails when the demo runs with -Fail, and is done otherwise.
#>

$step = @{
    Name   = 'Fail on request'
    Test   = { -not $env:PWSHSETUP_DEMO_FAIL }
    Action = {
        Start-Sleep -Milliseconds 500
        throw 'Failed on purpose: the demo ran with -Fail.'
    }
}
New-SetupStep @step
