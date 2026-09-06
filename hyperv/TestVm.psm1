<#
.SYNOPSIS
    Shared parts of the Hyper-V test machine scripts: names, the stored password, waiting for Windows, and the ISO cache.
#>
#Requires -Version 7.2

$CheckpointName = 'Clean'
$CredentialRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'PwshSetup\HyperV'
$IsoRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'PwshSetup\HyperV\iso'
$ReadyTimeoutMinutes = 40
$ReadyPollSeconds = 10
$RetailIsoUri = 'https://www.microsoft.com/software-download/windows11'
$EvaluationIsoUri = 'https://www.microsoft.com/evalcenter/download-windows-11-enterprise'

function Get-TestVmCredentialFile
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $VmName
    )

    return (Join-Path -Path $CredentialRoot -ChildPath ('{0}.credential.xml' -f $VmName))
}

function Save-TestVmCredential
{
    # Export-Clixml encrypts the password for the current user on this machine.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $VmName,
        [Parameter(Mandatory)] [pscredential] $Credential
    )

    if (-not (Test-Path -LiteralPath $CredentialRoot))
    {
        $null = New-Item -ItemType Directory -Path $CredentialRoot -Force
    }
    $Credential | Export-Clixml -LiteralPath (Get-TestVmCredentialFile -VmName $VmName)
}

function Read-TestVmCredential
{
    [CmdletBinding()]
    [OutputType([pscredential])]
    param(
        [Parameter(Mandatory)] [string] $VmName
    )

    $file = Get-TestVmCredentialFile -VmName $VmName
    if (-not (Test-Path -LiteralPath $file))
    {
        throw ('No stored password for {0}. Create the machine with New-SetupTestVm.ps1 first.' -f $VmName)
    }
    return (Import-Clixml -LiteralPath $file)
}

function Remove-TestVmCredential
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $VmName
    )

    Remove-Item -LiteralPath (Get-TestVmCredentialFile -VmName $VmName) -Force -ErrorAction Ignore
}

function Assert-TestVmHost
{
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name 'New-VM' -ErrorAction Ignore))
    {
        throw 'Hyper-V is not turned on. Enable it in Windows Features (Hyper-V, with its management tools), restart, and run again.'
    }
}

function Wait-TestVmWindows
{
    # Windows reports no first-boot progress, so $Task is driven off elapsed time against the timeout.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $VmName,
        [Parameter(Mandatory)] [pscredential] $Credential,
        [object] $Task
    )

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $limit = [TimeSpan]::FromMinutes($ReadyTimeoutMinutes)
    while ($watch.Elapsed -lt $limit)
    {
        try
        {
            $signedIn = Invoke-Command -VMName $VmName -Credential $Credential -ErrorAction Stop -ScriptBlock {
                [bool](Get-Process -Name 'explorer' -ErrorAction Ignore)
            }
            if ($signedIn)
            {
                return
            }
        }
        catch
        {
            Write-Verbose -Message ('Not reachable yet: {0}' -f $_.Exception.Message)
        }

        if ($Task)
        {
            $Task.Update($watch.Elapsed.TotalSeconds, $limit.TotalSeconds)
        }
        Start-Sleep -Seconds $ReadyPollSeconds
    }
    throw ('{0} was not signed in after {1} minutes. Open it with vmconnect to see why.' -f $VmName, $ReadyTimeoutMinutes)
}

function Start-TestVm
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $VmName
    )

    if ((Get-VM -Name $VmName).State -ne 'Running')
    {
        Start-VM -Name $VmName
    }
}

function Get-TestVmIso
{
    # Picks the newest *.iso the user has placed under the cache. Microsoft rotates signed download URLs
    # and gates fetches with bot detection, so the first ISO is dropped in by hand; the cache then serves
    # every subsequent run.
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-Path -LiteralPath $IsoRoot))
    {
        $null = New-Item -ItemType Directory -Path $IsoRoot -Force
    }
    $existing = Get-ChildItem -LiteralPath $IsoRoot -Filter '*.iso' -ErrorAction Ignore |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1
    if ($existing)
    {
        return $existing.FullName
    }

    # Written before the throw: the error view folds long messages, so the links would not stay readable inside it.
    $folderUri = ([Uri]::new($IsoRoot)).AbsoluteUri
    $lines = @(
        ''
        ('No Windows ISO under [link={0}]{1}[/].' -f $folderUri, $IsoRoot)
        'Download one from Microsoft, free and without an account, save it there, then run again:'
        ('  Retail, Home and Pro:          [link={0}]{0}[/]' -f $RetailIsoUri)
        ('  Enterprise Evaluation:         [link={0}]{0}[/]' -f $EvaluationIsoUri)
        ''
    )
    foreach ($line in $lines)
    {
        Format-AnsiText -Message $line | Out-AnsiHost
    }
    throw 'No Windows ISO found. See the links above.'
}

function New-TestVmPassword
{
    # 20 chars with at least one of each class, so the Windows local-account complexity policy is always met.
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Strings over [char[]] literals: @() unrolls char arrays, which would flatten the classes into one pool.
    $alphabets = 'ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnpqrstuvwxyz', '23456789', '!@#$%^&*()-_=+'
    $chars = [System.Collections.Generic.List[char]]::new()
    foreach ($alphabet in $alphabets)
    {
        $chars.Add($alphabet[(Get-Random -Minimum 0 -Maximum $alphabet.Length)])
    }
    $pool = -join $alphabets
    while ($chars.Count -lt 20)
    {
        $chars.Add($pool[(Get-Random -Minimum 0 -Maximum $pool.Length)])
    }
    return (-join ($chars | Sort-Object -Property { Get-Random }))
}

function New-TestVmCredential
{
    [CmdletBinding()]
    [OutputType([pscredential])]
    param(
        [string] $UserName = 'setup'
    )

    $password = ConvertTo-SecureString -String (New-TestVmPassword) -AsPlainText -Force
    return (New-Object -TypeName 'System.Management.Automation.PSCredential' -ArgumentList $UserName, $password)
}

Export-ModuleMember -Function Get-TestVmCredentialFile, Save-TestVmCredential, Read-TestVmCredential,
Remove-TestVmCredential, Assert-TestVmHost, Wait-TestVmWindows, Start-TestVm,
Get-TestVmIso, New-TestVmPassword, New-TestVmCredential -Variable CheckpointName
