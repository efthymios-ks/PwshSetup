<#
.SYNOPSIS
    Runs the system test suite against a fresh test machine, end to end.
.DESCRIPTION
    Reverts the test machine to its Clean checkpoint, pushes the local module builds and the hyperv/Setup folder, runs
    Setup.ps1 on the desktop and waits for its .done sentinel, then copies the system tests folder in and runs Pester
    inside the guest. Pulls the NUnit XML back and exits non-zero when Setup failed or any assertion failed.
    Live output from both Setup.ps1 and the in-guest Pester run is streamed through C:\Setup\.log via Start-Transcript,
    tailed on a second PSSession so the host console sees progress as it happens.
    Not intended for hosted CI runners: needs Hyper-V on the host and a Windows ISO cached under
    %LOCALAPPDATA%\PwshSetup\HyperV\iso. New-SetupTestVm.ps1 creates the machine on first use.
.PARAMETER VmName
    The test machine. Reused across runs; the Clean checkpoint guarantees a pristine starting state each time.
.PARAMETER TestPath
    Folder of *.Tests.ps1 files to run in the guest. Defaults to tests\system beside this script.
.PARAMETER TimeoutMinutes
    How long to wait for Setup.ps1 to write its .done sentinel, across every restart and the slowest step.
.PARAMETER PollSeconds
    Interval between tail reads and .done checks. Lower is more responsive, higher is kinder on PowerShell Direct.
.PARAMETER ResultPath
    When set, the NUnit XML is pulled from the guest to this host path, overwriting any existing file.
.PARAMETER Template
    Wildcard patterns matched against step file names under hyperv\Setup\steps AND test file names under
    tests\system\templates. Matching step files (plus the unchanged Setup.ps1 and the local templates
    folder) are staged into a temporary folder which Sync pushes in place of the full set; matching
    *.Tests.ps1 files (plus _Helpers.ps1) are copied into C:\SystemTests. Default '*' pushes and runs
    everything. Dependencies are not auto-included: a Template choice that needs Chocolatey must also
    match the Install-Chocolatey step.
.EXAMPLE
    .\Invoke-SystemTest.ps1
.EXAMPLE
    .\Invoke-SystemTest.ps1 -ResultPath .\system-results.xml
.EXAMPLE
    # Dev loop: just install + test VS Code (and its Chocolatey prerequisite)
    .\Invoke-SystemTest.ps1 -Template 'Chocolatey', 'VsCode'
.EXAMPLE
    # Everything SQL (needs Chocolatey too, and Install-SqlServer2022 reboots)
    .\Invoke-SystemTest.ps1 -Template 'Chocolatey', 'Sql'
#>
#Requires -Version 7.2
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9-]{1,40}$')] [string] $VmName = 'PwshSetup-Test',
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })] [string] $TestPath = (Join-Path -Path $PSScriptRoot -ChildPath 'tests\system'),
    [ValidateRange(5, 240)] [int] $TimeoutMinutes = 45,
    [ValidateRange(2, 60)] [int] $PollSeconds = 3,
    [string] $ResultPath,
    [string[]] $Template = @('*')
)

if (-not (Get-Module -ListAvailable -Name PwshAnsi | Where-Object -FilterScript { $_.Version -ge [version]'0.1.9' }))
{
    Install-Module -Name PwshAnsi -Scope CurrentUser -MinimumVersion '0.1.9' -Force -AllowClobber
}
Import-Module -Name PwshAnsi -MinimumVersion '0.1.9'
Assert-PwshAnsi
# Elevated from the start: Get-VM, New-PSSession -VMName and Copy-Item -ToSession all need Hyper-V administrator
# rights, here and in every script this one calls.
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'src\Assert-SetupAdmin.psm1') -Force -DisableNameChecking
Assert-SetupAdmin

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'hyperv\TestVm.psm1') -Force
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$GuestSetupPath = 'C:\Setup'
$GuestTestPath = 'C:\SystemTests'
$GuestLogPath = Join-Path -Path $GuestSetupPath -ChildPath '.log'
$GuestResultPath = Join-Path -Path $GuestTestPath -ChildPath 'results.xml'

function Read-GuestLogAppend
{
    # Reads whatever has been appended since the last offset and prints it on the host. Opens the file with
    # FileShare.ReadWrite so a writing process in the guest never blocks us or vice versa.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Runspaces.PSSession] $Session,
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [ref] $Offset
    )

    $chunk = Invoke-Command -Session $Session -ArgumentList $Path, $Offset.Value -ScriptBlock {
        param($Path, $Offset)
        if (-not (Test-Path -LiteralPath $Path))
        {
            return $null
        }
        $length = (Get-Item -LiteralPath $Path).Length
        if ($length -le $Offset)
        {
            return $null
        }
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try
        {
            $stream.Position = $Offset
            $reader = [System.IO.StreamReader]::new($stream)
            [pscustomobject]@{
                Content = $reader.ReadToEnd()
                Offset  = $length
            }
        }
        finally
        {
            $stream.Dispose()
        }
    }
    if ($chunk -and $chunk.Content)
    {
        [Console]::Out.Write($chunk.Content)
        $Offset.Value = $chunk.Offset
    }
}

function Read-GuestLogTail
{
    # Read-GuestLogAppend that never stops the run: a read that fails while the guest restarts is retried on the next
    # poll.
    [CmdletBinding()]
    param(
        [AllowNull()] [System.Management.Automation.Runspaces.PSSession] $Session,
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [ref] $Offset
    )

    if (-not $Session)
    {
        return
    }
    try
    {
        Read-GuestLogAppend -Session $Session -Path $Path -Offset $Offset
    }
    catch
    {
        Write-Verbose -Message ('Log not readable this poll: {0}' -f $_.Exception.Message)
    }
}

Clear-Host
Format-AnsiRule -Title '[BrightWhite]PwshSetup system test[/]' -Alignment Left -LineColor DarkGray | Out-AnsiHost

# Stage a filtered copy of hyperv\Setup if -Template narrows the step list. Setup.ps1 and the templates
# folder beside it are always copied verbatim; only steps\ is subsetted.
$sourceSetup = Join-Path -Path $PSScriptRoot -ChildPath 'hyperv\Setup'
$sourceStepRoot = Join-Path -Path $sourceSetup -ChildPath 'steps'
$filtered = ($Template.Count -gt 0) -and -not ($Template.Count -eq 1 -and $Template[0] -eq '*')
$setupPath = $sourceSetup
$stepRoot = $sourceStepRoot
if ($filtered)
{
    $stagingRoot = Join-Path -Path $env:TEMP -ChildPath ('PwshSetup-staging-{0}' -f [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $stagingRoot -Force
    Copy-Item -LiteralPath (Join-Path -Path $sourceSetup -ChildPath 'Setup.ps1') -Destination $stagingRoot -Force
    if (Test-Path -LiteralPath (Join-Path -Path $sourceSetup -ChildPath 'templates') -PathType Container)
    {
        Copy-Item -Path (Join-Path -Path $sourceSetup -ChildPath 'templates') -Destination $stagingRoot -Recurse -Force
    }
    $stagingStepRoot = Join-Path -Path $stagingRoot -ChildPath 'steps'
    $null = New-Item -ItemType Directory -Path $stagingStepRoot -Force
    foreach ($pattern in $Template)
    {
        Get-ChildItem -LiteralPath $sourceStepRoot -Filter ('*{0}*.ps1' -f $pattern) -ErrorAction Ignore |
            Copy-Item -Destination $stagingStepRoot -Force
    }
    if (-not (Get-ChildItem -LiteralPath $stagingStepRoot -Filter '*.ps1' -ErrorAction Ignore))
    {
        throw ('No step files under {0} matched -Template: {1}' -f $sourceStepRoot, ($Template -join ', '))
    }
    $setupPath = $stagingRoot
    $stepRoot = $stagingStepRoot
}

# Pre-flight manifest: show what will install and which tests will apply before any VM work. Comes straight
# from the local file inventory, so a drift between step files and test files is obvious at a glance.
$steps = @(Get-ChildItem -LiteralPath $stepRoot -Filter '*.ps1' -ErrorAction Ignore |
    Sort-Object -Property Name |
    ForEach-Object -MemberName BaseName)
$tests = @(Get-ChildItem -LiteralPath $TestPath -Filter '*.Tests.ps1' -Recurse -ErrorAction Ignore |
    Sort-Object -Property Name |
    ForEach-Object -Process { $_.BaseName -replace '\.Tests$', '' })
Format-AnsiText -Message ('[DarkGray]Setup steps ({0}):[/] {1}' -f $steps.Count, ($steps -join ', ')) | Out-AnsiHost
Format-AnsiText -Message ('[DarkGray]Tests on hand ({0}):[/] {1}' -f $tests.Count, ($tests -join ', ')) | Out-AnsiHost
[Console]::WriteLine()

# -NoConnect: this script follows the run itself. A script called with & that exits only sets $LASTEXITCODE, so it
# is checked here; set to 0 first, since a script that never exits leaves it unset under StrictMode.
$global:LASTEXITCODE = 0
& (Join-Path -Path $PSScriptRoot -ChildPath 'hyperv\Sync-SetupTestVm.ps1') -VmName $VmName -NoConnect -SetupPath $setupPath
if ($LASTEXITCODE -ne 0)
{
    exit $LASTEXITCODE
}

if ($ResultPath -and (Test-Path -LiteralPath $ResultPath))
{
    Remove-Item -LiteralPath $ResultPath -Force
}

$credential = Read-TestVmCredential -VmName $VmName
# Two sessions: one for commands, one for the parallel log tail. PSSessions serialise commands, so sharing
# one would block the tail whenever Invoke-Command -AsJob held the main session for Pester.
$session = New-PSSession -VMName $VmName -Credential $credential
$tailSession = New-PSSession -VMName $VmName -Credential $credential

function Confirm-GuestSession
{
    # PowerShell Direct sessions end when the guest restarts and never come back: a closed one is dropped and, once
    # the machine runs again, replaced. Called before every poll, so a restart costs a few polls, not the run.
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Runspaces.PSSession])]
    param(
        [Parameter(Mandatory)] [ref] $Session,
        [Parameter(Mandatory)] [string] $VmName,
        [Parameter(Mandatory)] [pscredential] $Credential
    )
    if ($Session.Value -and $Session.Value.State -eq 'Opened')
    {
        return
    }
    if ($Session.Value)
    {
        Remove-PSSession -Session $Session.Value -ErrorAction Ignore
    }
    $Session.Value = $null
    if ((Get-VM -Name $VmName -ErrorAction Ignore).State -ne 'Running')
    {
        return
    }
    try
    {
        $Session.Value = New-PSSession -VMName $VmName -Credential $Credential -ErrorAction Stop
    }
    catch
    {
        Write-Verbose -Message ('Session not open yet, retried on the next poll: {0}' -f $_.Exception.Message)
    }
}

try
{
    # Sentinels and logs from an earlier run are removed whatever the checkpoint holds.
    Invoke-Command -Session $session -ArgumentList $GuestSetupPath, $GuestTestPath -ScriptBlock {
        param($SetupFolder, $TestFolder)
        Remove-Item -LiteralPath (Join-Path -Path $SetupFolder -ChildPath '.done') -Force -ErrorAction Ignore
        Remove-Item -LiteralPath (Join-Path -Path $SetupFolder -ChildPath '.running') -Force -ErrorAction Ignore
        Remove-Item -LiteralPath (Join-Path -Path $SetupFolder -ChildPath '.log') -Force -ErrorAction Ignore
        Remove-Item -LiteralPath $TestFolder -Recurse -Force -ErrorAction Ignore
    }

    # Poll for .done, tailing .log as it fills. Setup restarts the VM for some steps; Invoke-Command throws
    # while Windows is down, so a per-tick try/catch swallows the gap instead of giving up on the first
    # unreachable sample.
    Format-AnsiText -Message ('[DarkGray]Waiting for {0} (up to {1} minutes). Live output follows:[/]' -f $GuestLogPath, $TimeoutMinutes) | Out-AnsiHost
    [Console]::WriteLine()
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $logOffset = [int64]0
    $done = $null
    while ((Get-Date) -lt $deadline)
    {
        Confirm-GuestSession -Session ([ref]$session) -VmName $VmName -Credential $credential
        Confirm-GuestSession -Session ([ref]$tailSession) -VmName $VmName -Credential $credential
        if ($session -and $tailSession)
        {
            try
            {
                Read-GuestLogAppend -Session $tailSession -Path $GuestLogPath -Offset ([ref]$logOffset)
                $done = Invoke-Command -Session $session -ArgumentList $GuestSetupPath -ScriptBlock {
                    param($SetupFolder)
                    $path = Join-Path -Path $SetupFolder -ChildPath '.done'
                    if (Test-Path -LiteralPath $path)
                    {
                        Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
                    }
                }
            }
            catch
            {
                Write-Verbose -Message ('Guest not reachable this tick: {0}' -f $_.Exception.Message)
            }
        }
        if ($done)
        {
            break
        }
        Start-Sleep -Seconds $PollSeconds
    }
    # The lines written between the last read and .done.
    Read-GuestLogTail -Session $tailSession -Path $GuestLogPath -Offset ([ref]$logOffset)
    if (-not $done)
    {
        throw ('Setup.ps1 did not write {0}\.done within {1} minutes.' -f $GuestSetupPath, $TimeoutMinutes)
    }

    [Console]::WriteLine()
    $statusColor = 'BrightRed'
    if ($done.status -eq 'Succeeded')
    {
        $statusColor = 'BrightGreen'
    }
    Format-AnsiText -Message ('[DarkGray]Setup status:[/] [{0}]{1}[/]  [DarkGray]duration:[/] {2}' -f $statusColor, $done.status, $done.duration) | Out-AnsiHost
    if ($done.status -ne 'Succeeded' -and $done.PSObject.Properties['error'] -and $done.error)
    {
        Format-AnsiText -Message ('[BrightRed]Setup error:[/] {0}' -f $done.error) | Out-AnsiHost
    }
    if ($done.outcome -and $done.outcome.PSObject.Properties['LogFile'] -and $done.outcome.LogFile)
    {
        Format-AnsiText -Message ('[DarkGray]Setup log on the guest:[/] {0}' -f $done.outcome.LogFile) | Out-AnsiHost
    }
    [Console]::WriteLine()

    # Push tests in and run Pester inside the guest so assertions see the real installed state (choco list,
    # Get-Service, $env:PATH, registry) rather than a stale projection over PSSession.
    Invoke-Command -Session $session -ArgumentList $GuestTestPath -ScriptBlock {
        param($Target)
        $null = New-Item -ItemType Directory -Path $Target -Force
    }
    if ($filtered)
    {
        # Stage a filtered mirror of $TestPath on the host, then push it. Keeps the original directory
        # layout so each *.Tests.ps1 still dot-sources _Helpers.ps1 from $PSScriptRoot.
        $stagingTests = Join-Path -Path $env:TEMP -ChildPath ('PwshSetup-tests-{0}' -f [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $stagingTests -Force
        foreach ($helper in Get-ChildItem -LiteralPath $TestPath -Filter '_Helpers.ps1' -Recurse -ErrorAction Ignore)
        {
            $relative = $helper.FullName.Substring($TestPath.Length).TrimStart('\')
            $target = Join-Path -Path $stagingTests -ChildPath $relative
            $null = New-Item -ItemType Directory -Path (Split-Path -Path $target -Parent) -Force
            Copy-Item -Path $helper.FullName -Destination $target -Force
        }
        $seen = @{}
        foreach ($pattern in $Template)
        {
            foreach ($file in Get-ChildItem -LiteralPath $TestPath -Filter ('*{0}*.Tests.ps1' -f $pattern) -Recurse -ErrorAction Ignore)
            {
                if ($seen.ContainsKey($file.FullName))
                {
                    continue
                }
                $seen[$file.FullName] = $true
                $relative = $file.FullName.Substring($TestPath.Length).TrimStart('\')
                $target = Join-Path -Path $stagingTests -ChildPath $relative
                $null = New-Item -ItemType Directory -Path (Split-Path -Path $target -Parent) -Force
                Copy-Item -Path $file.FullName -Destination $target -Force
            }
        }
        Copy-Item -Path (Join-Path -Path $stagingTests -ChildPath '*') -Destination $GuestTestPath -ToSession $session -Recurse -Force
    }
    else
    {
        Copy-Item -Path (Join-Path -Path $TestPath -ChildPath '*') -Destination $GuestTestPath -ToSession $session -Recurse -Force
    }

    Format-AnsiText -Message '[DarkGray]Running system tests. Live output follows:[/]' | Out-AnsiHost
    [Console]::WriteLine()
    # -AsJob so the main session doesn't block; the tail session reads .log while Pester runs.
    $job = Invoke-Command -Session $session -AsJob -ArgumentList $GuestTestPath, $GuestResultPath, $GuestLogPath -ScriptBlock {
        param($TestFolder, $ResultFile, $LogFile)
        if (-not (Get-Module -ListAvailable -Name Pester | Where-Object -FilterScript { $_.Version -ge [version]'5.0.0' }))
        {
            # Save-PSResource via pwsh so no NuGet provider install prompt interrupts the run. Target the
            # WindowsPowerShell modules folder which both editions scan, so this PSSession (Windows
            # PowerShell 5.1) sees Pester immediately after.
            $pwshPath = Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\7\pwsh.exe'
            $targetRoot = Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsPowerShell\Modules'
            $install = {
                param($TargetRoot)
                Save-PSResource -Name Pester -Path $TargetRoot -TrustRepository
            }
            & $pwshPath -NoProfile -NoLogo -Command $install -args $targetRoot
            if ($LASTEXITCODE -ne 0)
            {
                throw ('pwsh exited with code {0} installing Pester.' -f $LASTEXITCODE)
            }
        }
        Import-Module -Name Pester -MinimumVersion '5.0.0'
        Start-Transcript -LiteralPath $LogFile -Append -Force | Out-Null
        try
        {
            $config = New-PesterConfiguration
            $config.Run.Path = $TestFolder
            $config.Run.PassThru = $true
            $config.Run.Exit = $false
            $config.Output.Verbosity = 'Detailed'
            $config.TestResult.Enabled = $true
            $config.TestResult.OutputPath = $ResultFile
            $config.TestResult.OutputFormat = 'NUnitXml'
            $pesterResult = Invoke-Pester -Configuration $config
            [pscustomobject]@{
                Passed  = $pesterResult.PassedCount
                Failed  = $pesterResult.FailedCount
                Skipped = $pesterResult.SkippedCount
                Total   = $pesterResult.TotalCount
            }
        }
        finally
        {
            Stop-Transcript | Out-Null
        }
    }
    while ($job.State -eq 'Running')
    {
        Read-GuestLogTail -Session $tailSession -Path $GuestLogPath -Offset ([ref]$logOffset)
        Start-Sleep -Seconds $PollSeconds
    }
    Read-GuestLogTail -Session $tailSession -Path $GuestLogPath -Offset ([ref]$logOffset)
    $result = Receive-Job -Job $job -Wait -ErrorAction Stop
    Remove-Job -Job $job -Force

    if ($ResultPath)
    {
        Copy-Item -Path $GuestResultPath -Destination $ResultPath -FromSession $session -Force
    }

    [Console]::WriteLine()
    $color = 'BrightRed'
    if ($done.status -eq 'Succeeded' -and $result.Failed -eq 0)
    {
        $color = 'BrightGreen'
    }
    Format-AnsiText -Message (
        'Setup: [BrightCyan]{0}[/]  Tests: [BrightGreen]{1} passed[/], [{4}]{2} failed[/], [DarkGray]{3} skipped[/]' -f
        $done.status, $result.Passed, $result.Failed, $result.Skipped, $color
    ) | Out-AnsiHost

    if ($done.status -ne 'Succeeded' -or $result.Failed -gt 0)
    {
        exit 1
    }
}
catch
{
    Format-AnsiException -Exception $_ | Out-AnsiHost
    exit 1
}
finally
{
    foreach ($guestSession in @($session, $tailSession))
    {
        if ($guestSession)
        {
            Remove-PSSession -Session $guestSession -ErrorAction Ignore
        }
    }
    # An elevated rerun runs in a window of its own, which closes when the script exits cleanly, so it waits for
    # Enter to keep the summary on screen. A run started from your own shell ends straight away.
    if ($env:PWSHSETUP_RERUN)
    {
        [Console]::WriteLine()
        $null = Read-Host -Prompt 'Press Enter to close this window'
    }
}
