<#
.SYNOPSIS
    Runs the unit tests with Pester 5 and fails when any test fails.
.DESCRIPTION
    Discovers *.Tests.ps1 under -Path, runs them with Pester 5, and exits non-zero when anything fails or errors, or
    when no test is found. For local use and CI. The system tests need the Hyper-V test machine, so they are not
    picked up by default.
.PARAMETER Path
    Folder or file to run.
.PARAMETER Output
    Pester output verbosity.
.PARAMETER TestName
    Only run tests whose full name matches this wildcard pattern.
.PARAMETER Tag
    Only run tests carrying one of these tags.
.PARAMETER ResultPath
    Write NUnit XML results to this path.
.PARAMETER SkipInstall
    Fail when Pester 5 is missing, instead of installing it.
.NOTES
    Exit codes: 0 all tests passed, 1 a test failed, 2 no tests found, 3 Pester 5 unavailable.
.EXAMPLE
    .\Invoke-Test.ps1
.EXAMPLE
    .\Invoke-Test.ps1 -Output Normal -ResultPath .\testResults.xml
.EXAMPLE
    .\Invoke-Test.ps1 -TestName '*Parse*'
#>
#Requires -Version 7.2
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Test console output, read by a person or a CI log.')]
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()] [string] $Path = (Join-Path -Path $PSScriptRoot -ChildPath 'tests\unit'),
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')] [string] $Output = 'Detailed',
    [ValidateNotNullOrEmpty()] [string] $TestName,
    [ValidateNotNullOrEmpty()] [string[]] $Tag,
    [ValidateNotNullOrEmpty()] [string] $ResultPath,
    [switch] $SkipInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MinimumPesterVersion = [version]'5.0.0'
$NextMajorPesterVersion = [version]'6.0.0'
$InstallPesterVersion = '5.5.0'
$MaximumPesterVersion = '5.99.99'

function Get-PesterModule
{
    # The newest installed Pester 5, or nothing.
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSModuleInfo])]
    param()

    Get-Module -ListAvailable -Name 'Pester' |
        Where-Object -FilterScript { $_.Version -ge $MinimumPesterVersion -and $_.Version -lt $NextMajorPesterVersion } |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1
}

function Stop-TestRun
{
    # Not Write-Error: with ErrorActionPreference Stop it ends the script before exit, and the exit code would no
    # longer say why the run stopped.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message,
        [Parameter(Mandatory)] [ValidateRange(1, 255)] [int] $ExitCode
    )

    Write-Host -Object ('ERROR: {0}' -f $Message) -ForegroundColor Red
    exit $ExitCode
}

# ── Pester ───────────────────────────────────────────────────────────────────

$pesterModule = Get-PesterModule
if (-not $pesterModule)
{
    if ($SkipInstall)
    {
        $hint = 'Install-Module -Name Pester -Scope CurrentUser -MinimumVersion {0} -Force -SkipPublisherCheck' -f $InstallPesterVersion
        Stop-TestRun -Message ('Pester 5 is not installed. Run: {0}' -f $hint) -ExitCode 3
    }

    Write-Host -Object 'Pester 5 not found, installing it for the current user...' -ForegroundColor Yellow
    $installArguments = @{
        Name               = 'Pester'
        Scope              = 'CurrentUser'
        MinimumVersion     = $InstallPesterVersion
        MaximumVersion     = $MaximumPesterVersion
        Force              = $true
        SkipPublisherCheck = $true
        AllowClobber       = $true
        ErrorAction        = 'Stop'
    }
    try
    {
        Install-Module @installArguments
    }
    catch
    {
        Stop-TestRun -Message ('Failed to install Pester 5: {0}' -f $_.Exception.Message) -ExitCode 3
    }

    $pesterModule = Get-PesterModule
    if (-not $pesterModule)
    {
        Stop-TestRun -Message 'Pester 5 is still unavailable after installing it.' -ExitCode 3
    }
}

# Windows ships Pester 3; unload it if it got in first, then load 5.
Get-Module -Name 'Pester' |
    Where-Object -FilterScript { $_.Version -lt $MinimumPesterVersion } |
    Remove-Module -Force
Import-Module -Name $pesterModule.Path -Force

# ── Run ──────────────────────────────────────────────────────────────────────

if (-not (Test-Path -LiteralPath $Path))
{
    Stop-TestRun -Message ('Test path not found: {0}' -f $Path) -ExitCode 2
}

$configuration = New-PesterConfiguration
$configuration.Run.Path = $Path
$configuration.Run.PassThru = $true
$configuration.Run.Exit = $false
$configuration.Output.Verbosity = $Output
if ($PSBoundParameters.ContainsKey('TestName'))
{
    $configuration.Filter.FullName = $TestName
}
if ($PSBoundParameters.ContainsKey('Tag'))
{
    $configuration.Filter.Tag = $Tag
}
if ($PSBoundParameters.ContainsKey('ResultPath'))
{
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputPath = $ResultPath
    $configuration.TestResult.OutputFormat = 'NUnitXml'
}

Write-Host -Object ('Pester {0}, running the tests in {1}' -f $pesterModule.Version, $Path) -ForegroundColor Cyan
try
{
    $result = Invoke-Pester -Configuration $configuration
}
catch
{
    Stop-TestRun -Message ('Pester run failed: {0}' -f $_.Exception.Message) -ExitCode 1
}
if (-not $result)
{
    Stop-TestRun -Message ('No tests were found under {0}.' -f $Path) -ExitCode 2
}

$total = $result.PassedCount + $result.FailedCount + $result.SkippedCount + $result.NotRunCount
$summaryColor = 'Green'
if ($result.FailedCount -gt 0)
{
    $summaryColor = 'Red'
}
$summary = 'Passed: {0}  Failed: {1}  Skipped: {2}  Duration: {3:n2}s' -f
$result.PassedCount, $result.FailedCount, $result.SkippedCount, $result.Duration.TotalSeconds
Write-Host -Object ''
Write-Host -Object $summary -ForegroundColor $summaryColor

if ($total -eq 0)
{
    Stop-TestRun -Message ('No tests were found under {0}.' -f $Path) -ExitCode 2
}
if ($result.FailedCount -gt 0 -or $result.FailedBlocksCount -gt 0 -or $result.FailedContainersCount -gt 0)
{
    Write-Host -Object 'TESTS FAILED' -ForegroundColor Red
    exit 1
}

Write-Host -Object 'ALL TESTS PASSED' -ForegroundColor Green
exit 0
