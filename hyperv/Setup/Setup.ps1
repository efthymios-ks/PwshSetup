<#
.SYNOPSIS
    Sets up this machine with the steps in the steps folder beside this script, unattended.
.DESCRIPTION
    Starts on Windows PowerShell or pwsh and moves to pwsh 7. Needs pwsh 7, PwshAnsi and PwshSetup on the machine
    already, as the test machine has them; elevates, then runs every step. After a restart it carries on by itself.
    Writes three files beside itself, so a watcher outside the machine can follow the run:
      .running   written at every start, including each start after a restart
      .log       a transcript of every start, appended
      .done      written once, at the end, with the outcome as JSON
.NOTES
    Exit code 1 when a step failed or the run threw; 0 otherwise.
.EXAMPLE
    .\Setup.ps1
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$runningPath = Join-Path -Path $PSScriptRoot -ChildPath '.running'
$donePath = Join-Path -Path $PSScriptRoot -ChildPath '.done'
$logPath = Join-Path -Path $PSScriptRoot -ChildPath '.log'

$running = @{
    pid  = $PID
    time = (Get-Date).ToString('o')
}
$running | ConvertTo-Json | Set-Content -LiteralPath $runningPath -Encoding utf8

# Appended across restarts, so one file holds the whole run.
Start-Transcript -LiteralPath $logPath -Append -Force | Out-Null

# The move to pwsh happens here, in this window, so the transcript keeps every line; a rerun in a new Windows
# Terminal tab would write outside it.
if ($PSVersionTable.PSEdition -eq 'Desktop')
{
    $pwsh = Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\7\pwsh.exe'
    if (-not (Test-Path -LiteralPath $pwsh))
    {
        throw ('PowerShell 7 is required but was not found at {0}.' -f $pwsh)
    }
    Stop-Transcript | Out-Null
    & $pwsh -NoProfile -NoLogo -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

# Import-Module resolves PwshSetup's required PwshAnsi from disk, so both must be installed before this runs.
if (-not (Get-Module -ListAvailable -Name PwshAnsi))
{
    throw 'PwshAnsi is required but not installed. Run: Install-PSResource -Name PwshAnsi -Scope AllUsers -TrustRepository'
}
if (-not (Get-Module -ListAvailable -Name PwshSetup))
{
    throw 'PwshSetup is required but not installed. Run: Install-PSResource -Name PwshSetup -Scope AllUsers -TrustRepository'
}
Import-Module -Name PwshSetup
Assert-PwshAnsi
Assert-SetupAdmin

$outcome = $null
$failure = $null
try
{
    $outcome = Invoke-PwshSetup -Path (Join-Path -Path $PSScriptRoot -ChildPath 'steps') -Unattended -PassThru
}
catch
{
    $failure = $_
}
finally
{
    Stop-Transcript | Out-Null
}

$status = 'Succeeded'
if ($failure)
{
    $status = 'Error'
}
elseif ($outcome.Status -eq 'Failed')
{
    $status = 'Failed'
}

$duration = $null
if ($outcome)
{
    $duration = $outcome.Duration.ToString()
}
$errorText = $null
if ($failure)
{
    $errorText = $failure.ToString()
}

$payload = @{
    status   = $status
    time     = (Get-Date).ToString('o')
    duration = $duration
    outcome  = $outcome
    error    = $errorText
}
$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $donePath -Encoding utf8
Remove-Item -LiteralPath $runningPath -Force -ErrorAction Ignore

if ($status -ne 'Succeeded')
{
    exit 1
}
