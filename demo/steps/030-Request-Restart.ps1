<#
.SYNOPSIS
    Demo: a step that asks for a restart while it runs. The demo skips restarts, so it notes it and carries on.
#>

$step = @{
    Name   = 'Ask for a restart'
    Test   = { $false }
    Action = {
        Start-Sleep -Milliseconds 900
        Request-SetupRestart
    }
}
New-SetupStep @step
