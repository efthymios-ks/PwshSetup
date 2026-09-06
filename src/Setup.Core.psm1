#Requires -Version 7.2

# Setup.Core.psm1
# Shared building blocks: the log writer, the step object every step file returns,
# and the discovery that turns a folder of step files into an ordered list.

$script:SetupLogColorMap = @{
    'Info'    = 'Cyan'
    'Warning' = 'Yellow'
    'Error'   = 'Red'
    'Success' = 'Green'
}

function Write-SetupLog {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'None')]
        [string]$Level = 'Info',

        [switch]$Timestamp
    )
    process {
        $line = if ($Timestamp) {
            '[{0}] [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level.ToUpperInvariant(), $Message
        }
        else {
            $Message
        }

        $color = $script:SetupLogColorMap[$Level]

        if ($color) {
            Write-Host $line -ForegroundColor $color
        }
        else {
            Write-Host $line
        }
    }
}

function New-SetupStep {
    <#
        The contract a step file returns. Test decides whether the step still has work to do,
        Action does it, and RequiresRestart says the machine has to reboot before the next step.
    #>
    [CmdletBinding()]
    [OutputType('Setup.Step')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock]$Action,

        [ValidateNotNull()]
        [scriptblock]$Test,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Order = 0,

        [switch]$RequiresRestart
    )

    [PSCustomObject]@{
        PSTypeName      = 'Setup.Step'
        Name            = $Name
        Order           = $Order
        Test            = $Test
        Action          = $Action
        RequiresRestart = [bool]$RequiresRestart
        Path            = $null
    }
}

function Get-SetupStep {
    <#
        Reads every *.step.ps1 under a folder and returns the step objects in run order.
        The leading number in the file name is the order unless the step states its own.
    #>
    [CmdletBinding()]
    [OutputType('Setup.Step')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Step folder not found: $Path"
    }

    $files = Get-ChildItem -LiteralPath $Path -Filter '*.step.ps1' -File | Sort-Object -Property Name
    $steps = [System.Collections.Generic.List[object]]::new()

    foreach ($file in $files) {
        $step = & $file.FullName

        if ($step -isnot [psobject] -or -not $step.PSObject.TypeNames.Contains('Setup.Step')) {
            throw "Step file did not return a step object: $($file.FullName)"
        }

        if ($step.Order -eq 0 -and $file.Name -match '^(?<order>\d+)') {
            $step.Order = [int]$Matches.order
        }

        $step.Path = $file.FullName
        $steps.Add($step)
    }

    $steps | Sort-Object -Property Order, Name
}

function Test-SetupCommand {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    [bool](Get-Command -Name $Name -ErrorAction Ignore)
}

function Test-SetupElevation {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()

    [Security.Principal.WindowsPrincipal]::new($identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

Export-ModuleMember -Function Write-SetupLog, New-SetupStep, Get-SetupStep, Test-SetupCommand, Test-SetupElevation
