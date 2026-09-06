<#
.SYNOPSIS
    Test template, your own kind: restarts the machine once, to see the run carry on after the sign-in.
#>
[CmdletBinding()]
param()

$marker = Join-Path -Path $env:ProgramData -ChildPath 'PwshSetup\restart-once.txt'

$step = @{
    Name            = 'Restart once'
    RequiresRestart = $true
    Test            = { Test-Path -LiteralPath $marker }
    Action          = {
        $null = New-Item -ItemType Directory -Path (Split-Path -Path $marker -Parent) -Force
        Set-Content -LiteralPath $marker -Value (Get-Date -Format 'o')
        Write-SetupLog -Message 'Marker written; the machine restarts next.'
    }
}
New-SetupStep @step
