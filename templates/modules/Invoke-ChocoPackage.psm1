#Requires -Version 7.2

# Invoke-ChocoPackage.psm1
# Chocolatey wrapped so a step says what it wants installed and gets a result object back.
# Success is decided by the exit code, never by grepping the output for the word "error".

Import-Module (Join-Path $PSScriptRoot '..\..\src\Setup.Core.psm1') -Force -DisableNameChecking

# Chocolatey's own contract: 0 succeeded, 1641 and 3010 succeeded and want a reboot.
$script:ChocoSuccessExitCodes = @(0, 1641, 3010)
$script:ChocoRestartExitCodes = @(1641, 3010)

function Test-ChocoInstalled {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    [bool](Get-Command -Name 'choco' -ErrorAction Ignore)
}

function Sync-ChocoEnvironment {
    <#
        Reloads PATH and the rest of the environment a Chocolatey install just changed,
        so the next step sees the new command without a new shell.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [ValidateRange(0, 60)]
        [int]$DelaySeconds = 3
    )

    if ($DelaySeconds -gt 0) {
        Start-Sleep -Seconds $DelaySeconds
    }

    $profileModule = Join-Path $env:ChocolateyInstall 'helpers\chocolateyProfile.psm1'

    if (-not (Test-Path -LiteralPath $profileModule)) {
        Write-SetupLog "Chocolatey profile not found at $profileModule" -Level Warning
        return
    }

    Import-Module $profileModule -Force -DisableNameChecking
    Update-SessionEnvironment
}

function Invoke-ChocoCommand {
    <#
        Runs choco with the arguments given and reports what happened.
        Returns Setup.ChocoResult: Success, ExitCode, RestartRequired, Output.
    #>
    [CmdletBinding()]
    [OutputType('Setup.ChocoResult')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromRemainingArguments)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ArgumentList
    )

    Write-SetupLog "choco $($ArgumentList -join ' ')"

    $output = & choco @ArgumentList 2>&1 | Out-String
    $exitCode = $LASTEXITCODE

    [PSCustomObject]@{
        PSTypeName      = 'Setup.ChocoResult'
        Success         = $script:ChocoSuccessExitCodes -contains $exitCode
        ExitCode        = $exitCode
        RestartRequired = $script:ChocoRestartExitCodes -contains $exitCode
        Output          = $output.TrimEnd()
    }
}

function Install-ChocoPackage {
    <#
        Installs one package, and throws when Chocolatey says it failed, so the
        pipeline stops on the step that broke rather than the one after it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('Setup.ChocoResult')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [string[]]$AdditionalArgument = @()
    )

    $arguments = @('install', $Name, '--yes', '--no-progress')

    if ($PSBoundParameters.ContainsKey('Version')) {
        $arguments += @('--version', $Version)
    }

    $arguments += $AdditionalArgument

    if (-not $PSCmdlet.ShouldProcess($Name, 'choco install')) {
        return
    }

    $result = Invoke-ChocoCommand @arguments

    if (-not $result.Success) {
        throw "choco install $Name failed with exit code $($result.ExitCode).`n$($result.Output)"
    }

    $result
}

Export-ModuleMember -Function Test-ChocoInstalled, Sync-ChocoEnvironment, Invoke-ChocoCommand, Install-ChocoPackage
