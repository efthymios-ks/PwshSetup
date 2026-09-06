<#
.SYNOPSIS
    Demo: output and native command lines go to the log file, never between the progress lines.
#>

$step = @{
    Name   = 'Write output to the log only'
    Test   = { $false }
    Action = {
        'this line is output, so it goes to the log'
        cmd.exe /c 'echo this one comes from a native command'
        Start-Sleep -Milliseconds 700
    }
}
New-SetupStep @step
