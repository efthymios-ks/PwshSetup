<#
.SYNOPSIS
    Demo: a step whose Test says it is done, so the dry run says skip and the run skips it.
#>

$step = @{
    Name   = 'Show a step that is already done'
    Test   = { $true }
    Action = { Start-Sleep -Milliseconds 300 }
}
New-SetupStep @step
