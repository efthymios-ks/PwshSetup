<#
.SYNOPSIS
    Creates a Hyper-V machine to try PwshSetup in, from a Windows ISO, with nobody at the keyboard.
.DESCRIPTION
    Applies the Windows image from the ISO straight onto a new virtual disk, with an answer file that creates a local
    administrator and signs it in on its own at every start, so restarts during a setup run carry on unattended.
    Generation 2 with Secure Boot and a virtual TPM for Windows 11, and nested virtualization so WSL and Docker work
    inside.
    Waits until Windows is up and signed in, then takes the Clean checkpoint that Sync-SetupTestVm.ps1 goes back to.
    The password is kept for Sync-SetupTestVm.ps1, encrypted for the current user, under %LOCALAPPDATA%\PwshSetup\HyperV.
    Zero-arg run: no ISO on hand, the script prints the Microsoft download pages and stops so one can be dropped in;
    no credential, one is generated; the machine already exists, nothing is done.
.PARAMETER IsoPath
    A Windows 10 or 11 ISO. When omitted, the newest *.iso under %LOCALAPPDATA%\PwshSetup\HyperV\iso is used, and if
    nothing is there the script prints the free download pages and stops.
.PARAMETER Edition
    The image to install, by name, such as 'Windows 11 Pro'. Picked automatically otherwise: the single edition when
    the ISO has one, else the first match in Pro / Enterprise Evaluation / Enterprise on Windows 11 then on Windows 10,
    else the first image in the ISO.
.PARAMETER VmName
    The machine's name in Hyper-V. Its computer name is the same, cut to 15 characters.
.PARAMETER Credential
    The local administrator. Generated when omitted (user 'setup', 20-char random password), and saved for Sync.
.PARAMETER MemoryGB
    Fixed memory; nested virtualization needs it fixed.
.PARAMETER ProcessorCount
    Virtual processors.
.PARAMETER DiskGB
    Size of the dynamically growing disk.
.PARAMETER SwitchName
    The virtual switch; Default Switch gives internet through the host.
.PARAMETER Locale
    Language, region and keyboard. Must be a language the ISO has.
.PARAMETER ProductKey
    Only for editions that ask for one.
.NOTES
    Runs on the Hyper-V host, elevated: the script reruns itself as administrator.
    The answer file stays inside the machine with the password in it; use a throwaway one.
.EXAMPLE
    .\hyperv\New-SetupTestVm.ps1
.EXAMPLE
    .\hyperv\New-SetupTestVm.ps1 -IsoPath 'D:\ISO\Win11_Enterprise_Eval.iso' -Edition 'Windows 11 Enterprise Evaluation'
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateScript({ -not $_ -or (Test-Path -LiteralPath $_ -PathType Leaf) })] [string] $IsoPath,
    [string] $Edition,
    [ValidatePattern('^[A-Za-z0-9-]{1,40}$')] [string] $VmName,
    [pscredential] $Credential,
    [ValidateRange(4, 64)] [int] $MemoryGB,
    [ValidateRange(2, 32)] [int] $ProcessorCount,
    [ValidateRange(32, 1024)] [int] $DiskGB,
    [ValidateNotNullOrEmpty()] [string] $SwitchName,
    [ValidateNotNullOrEmpty()] [string] $Locale,
    [string] $ProductKey
)

# Baked-in machine spec. One place to edit; CLI flags still override.
$VmDefaults = @{
    VmName         = 'PwshSetup-Test'
    MemoryGB       = 8
    ProcessorCount = 4
    DiskGB         = 128
    SwitchName     = 'Default Switch'
    Locale         = 'en-US'
}
foreach ($key in $VmDefaults.Keys)
{
    if (-not $PSBoundParameters.ContainsKey($key))
    {
        Set-Variable -Name $key -Value $VmDefaults[$key]
    }
}

if (-not (Get-Module -ListAvailable -Name PwshAnsi | Where-Object -FilterScript { $_.Version -ge [version]'0.1.9' }))
{
    Install-Module -Name PwshAnsi -Scope CurrentUser -MinimumVersion '0.1.9' -Force -AllowClobber
}
Import-Module -Name PwshAnsi -MinimumVersion '0.1.9'
Assert-PwshAnsi
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\Assert-SetupAdmin.psm1') -Force -DisableNameChecking
Assert-SetupAdmin

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestVm.psm1') -Force
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# GPT type GUIDs for the three partitions below.
$BasicDataType = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'
$EfiSystemType = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
$ReservedType = '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'

# The PowerShell baked into the Clean checkpoint. Pinned, so every rebuilt machine starts the same.
$PwshVersion = '7.6.7'
$PwshMsiUri = 'https://github.com/PowerShell/PowerShell/releases/download/v{0}/PowerShell-{0}-win-x64.msi'

# Settling after the first sign-in: Windows counts as idle once the first-start setup reports complete and stays so.
$SettleTimeoutMinutes = 10
$SettleGraceSeconds = 30
$SettlePollSeconds = 5

function New-TestVmAnswerFile
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $ComputerName,
        [Parameter(Mandatory)] [pscredential] $Credential,
        [Parameter(Mandatory)] [string] $Locale,
        [Parameter(Mandatory)] [string] $TimeZone,
        [string] $ProductKey
    )

    $user = [System.Security.SecurityElement]::Escape($Credential.UserName)
    $password = [System.Security.SecurityElement]::Escape($Credential.GetNetworkCredential().Password)
    $component = 'processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"'
    $key = ''
    if ($ProductKey)
    {
        $key = '<ProductKey>{0}</ProductKey>' -f [System.Security.SecurityElement]::Escape($ProductKey)
    }

    return @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" $component>
      <ComputerName>$ComputerName</ComputerName>
      $key
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" $component>
      <InputLocale>$Locale</InputLocale>
      <SystemLocale>$Locale</SystemLocale>
      <UILanguage>$Locale</UILanguage>
      <UserLocale>$Locale</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" $component>
      <TimeZone>$TimeZone</TimeZone>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>$user</Name>
            <Group>Administrators</Group>
            <Password>
              <Value>$password</Value>
              <PlainText>true</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <AutoLogon>
        <Enabled>true</Enabled>
        <Username>$user</Username>
        <Password>
          <Value>$password</Value>
          <PlainText>true</PlainText>
        </Password>
        <LogonCount>9999</LogonCount>
      </AutoLogon>
    </component>
  </settings>
</unattend>
"@
}

Assert-TestVmHost
Clear-Host
Format-AnsiRule -Title '[BrightWhite]PwshSetup test machine[/]' -Alignment Left -LineColor DarkGray | Out-AnsiHost
if (Get-VM -Name $VmName -ErrorAction Ignore)
{
    Format-AnsiText -Message ('[DarkGray]{0} already exists. Remove-SetupTestVm.ps1 removes it, Sync-SetupTestVm.ps1 reuses it.[/]' -f $VmName) | Out-AnsiHost
    return
}
if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction Ignore))
{
    throw ('No virtual switch named {0}. Pass -SwitchName.' -f $SwitchName)
}

# Scrub leftovers from an aborted earlier run: an orphan VHDX attached to no VM, and the temp mount
# folders it would have used. Only acts when no VM owns the file, so a running machine stays untouched.
$vhdPath = Join-Path -Path (Get-VMHost).VirtualHardDiskPath -ChildPath ('{0}.vhdx' -f $VmName)
if (Test-Path -LiteralPath $vhdPath)
{
    Dismount-VHD -Path $vhdPath -ErrorAction Ignore
    Remove-Item -LiteralPath $vhdPath -Force -ErrorAction Ignore
}
Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter ('PwshSetup-{0}-*' -f $VmName) -ErrorAction Ignore |
    Remove-Item -Recurse -Force -ErrorAction Ignore
if (-not $Credential)
{
    $Credential = New-TestVmCredential -UserName 'setup'
}

if (-not $IsoPath)
{
    $IsoPath = Get-TestVmIso
}
$isoFullPath = (Resolve-Path -LiteralPath $IsoPath).ProviderPath
$build = @{
    IsoMounted  = $false
    VhdMounted  = $false
    VmCreated   = $false
    ImagePath   = $null
    ImageIndex  = 0
    ImageName   = $null
    # Folder mounts, not drive letters: letters would park two drives in Explorer during the build.
    SystemRoot  = Join-Path -Path $env:TEMP -ChildPath ('PwshSetup-{0}-system-{1}' -f $VmName, [guid]::NewGuid())
    WindowsRoot = Join-Path -Path $env:TEMP -ChildPath ('PwshSetup-{0}-windows-{1}' -f $VmName, [guid]::NewGuid())
}

try
{
    $iso = Mount-DiskImage -ImagePath $isoFullPath -PassThru
    $build.IsoMounted = $true
    $isoDrive = '{0}:' -f ($iso | Get-Volume).DriveLetter
    $build.ImagePath = @('install.wim', 'install.esd') |
        ForEach-Object -Process { Join-Path -Path $isoDrive -ChildPath ('sources\{0}' -f $_) } |
        Where-Object -FilterScript { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if (-not $build.ImagePath)
    {
        throw ('{0} has no sources\install.wim or install.esd. Is it a Windows ISO?' -f $IsoPath)
    }

    $images = @(Get-WindowsImage -ImagePath $build.ImagePath)
    $image = $null
    if ($Edition)
    {
        $image = $images | Where-Object -FilterScript { $_.ImageName -eq $Edition } | Select-Object -First 1
        if (-not $image)
        {
            throw ('No {0} in the ISO. It has: {1}' -f $Edition, (($images | ForEach-Object -Process { $_.ImageName }) -join ', '))
        }
    }
    elseif ($images.Count -eq 1)
    {
        $image = $images[0]
    }
    else
    {
        # Preference order lands on something activation-friendly for a disposable VM.
        $preferences = @(
            'Windows 11 Pro'
            'Windows 11 Enterprise Evaluation'
            'Windows 11 Enterprise'
            'Windows 10 Pro'
            'Windows 10 Enterprise Evaluation'
            'Windows 10 Enterprise'
        )
        foreach ($preferred in $preferences)
        {
            $image = $images | Where-Object -FilterScript { $_.ImageName -eq $preferred } | Select-Object -First 1
            if ($image)
            {
                break
            }
        }
        if (-not $image)
        {
            $image = $images[0]
        }
    }
    $build.ImageIndex = $image.ImageIndex
    $build.ImageName = $image.ImageName

    $header = @(
        , [string[]]@('[DarkGray]Machine[/]', $VmName)
        , [string[]]@('[DarkGray]Windows[/]', $build.ImageName)
        , [string[]]@('[DarkGray]Size   [/]', ('{0} GB memory, {1} processors, {2} GB disk' -f $MemoryGB, $ProcessorCount, $DiskGB))
        , [string[]]@('[DarkGray]Sign-in[/]', $Credential.UserName)
    )
    Format-AnsiGrid -Rows $header -Padding 3 | Out-AnsiHost
    [Console]::WriteLine()

    $createDisk = {
        $null = New-VHD -Path $vhdPath -SizeBytes ([uint64]$DiskGB * 1GB) -Dynamic
        $disk = Mount-VHD -Path $vhdPath -Passthru | Get-Disk
        $build.VhdMounted = $true
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT

        # The system partition is formatted as basic data, then turned into the EFI one.
        $system = New-Partition -DiskNumber $disk.Number -Size 260MB -GptType $BasicDataType
        $null = Format-Volume -Partition $system -FileSystem FAT32 -NewFileSystemLabel 'System' -Confirm:$false -Force
        Set-Partition -DiskNumber $disk.Number -PartitionNumber $system.PartitionNumber -GptType $EfiSystemType
        $null = New-Partition -DiskNumber $disk.Number -Size 16MB -GptType $ReservedType
        $windows = New-Partition -DiskNumber $disk.Number -UseMaximumSize -GptType $BasicDataType
        $null = Format-Volume -Partition $windows -FileSystem NTFS -NewFileSystemLabel 'Windows' -Confirm:$false -Force

        $null = New-Item -ItemType Directory -Path $build.SystemRoot -Force
        $null = New-Item -ItemType Directory -Path $build.WindowsRoot -Force
        Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $system.PartitionNumber -AccessPath $build.SystemRoot
        Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $windows.PartitionNumber -AccessPath $build.WindowsRoot
    }

    $applyImage = {
        $applyArguments = @{
            ImagePath = $build.ImagePath
            Index     = $build.ImageIndex
            ApplyPath = $build.WindowsRoot
        }
        $null = Expand-WindowsImage @applyArguments
    }

    $makeBootable = {
        $bcdboot = Join-Path -Path $env:SystemRoot -ChildPath 'System32\bcdboot.exe'
        $output = & $bcdboot (Join-Path -Path $build.WindowsRoot -ChildPath 'Windows') /s $build.SystemRoot /f UEFI 2>&1
        if ($LASTEXITCODE -ne 0)
        {
            throw ('bcdboot failed with exit code {0}: {1}' -f $LASTEXITCODE, ($output -join ' '))
        }

        $answerArguments = @{
            ComputerName = $VmName.Substring(0, [Math]::Min(15, $VmName.Length))
            Credential   = $Credential
            Locale       = $Locale
            TimeZone     = (Get-TimeZone).Id
            ProductKey   = $ProductKey
        }
        $panther = Join-Path -Path $build.WindowsRoot -ChildPath 'Windows\Panther'
        $null = New-Item -ItemType Directory -Path $panther -Force
        New-TestVmAnswerFile @answerArguments | Set-Content -LiteralPath (Join-Path -Path $panther -ChildPath 'unattend.xml') -Encoding utf8

        Dismount-VHD -Path $vhdPath
        $build.VhdMounted = $false
        Dismount-DiskImage -ImagePath $isoFullPath | Out-Null
        $build.IsoMounted = $false
    }

    $createMachine = {
        $vmArguments = @{
            Name               = $VmName
            Generation         = 2
            MemoryStartupBytes = [int64]$MemoryGB * 1GB
            VHDPath            = $vhdPath
            SwitchName         = $SwitchName
        }
        $null = New-VM @vmArguments
        $build.VmCreated = $true

        Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $false
        Set-VMProcessor -VMName $VmName -Count $ProcessorCount -ExposeVirtualizationExtensions $true
        $firmwareArguments = @{
            VMName             = $VmName
            EnableSecureBoot   = 'On'
            SecureBootTemplate = 'MicrosoftWindows'
            FirstBootDevice    = Get-VMHardDiskDrive -VMName $VmName
        }
        Set-VMFirmware @firmwareArguments
        Set-VMKeyProtector -VMName $VmName -NewLocalKeyProtector
        Enable-VMTPM -VMName $VmName
        Set-VM -Name $VmName -CheckpointType Standard -AutomaticCheckpointsEnabled $false
        Enable-VMIntegrationService -VMName $VmName -Name 'Guest Service Interface'
        Save-TestVmCredential -VmName $VmName -Credential $Credential
    }

    $startWindows = {
        param($Task)

        Start-VM -Name $VmName
        Wait-TestVmWindows -VmName $VmName -Credential $Credential -Task $Task
        Invoke-Command -VMName $VmName -Credential $Credential -ScriptBlock {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
        }
    }

    # The desktop appears before the first-start screens and the first update scan finish. A checkpoint taken then
    # replays those screens after every reset, so the step waits until Windows reports its first start complete and
    # stays that way for a while.
    $settleWindows = {
        param($Task)

        $started = [System.Diagnostics.Stopwatch]::StartNew()
        $limit = [TimeSpan]::FromMinutes($SettleTimeoutMinutes)
        $readySince = $null
        while ($started.Elapsed -lt $limit)
        {
            $ready = $false
            try
            {
                $ready = [bool](Invoke-Command -VMName $VmName -Credential $Credential -ErrorAction Stop -ScriptBlock {
                    $oobe = (Get-ItemProperty -Path 'HKLM:\SYSTEM\Setup' -Name 'OOBEInProgress' -ErrorAction Ignore).OOBEInProgress
                    $state = (Get-ItemProperty -Path 'HKLM:\SYSTEM\Setup' -Name 'ImageState' -ErrorAction Ignore).ImageState
                    $null -ne $oobe -and $oobe -eq 0 -and $state -eq 'IMAGE_STATE_COMPLETE'
                })
            }
            catch
            {
                Write-Verbose -Message ('Not reachable yet: {0}' -f $_.Exception.Message)
            }

            if ($ready)
            {
                if (-not $readySince)
                {
                    $readySince = [System.Diagnostics.Stopwatch]::StartNew()
                }
                if ($readySince.Elapsed.TotalSeconds -ge $SettleGraceSeconds)
                {
                    break
                }
            }
            else
            {
                $readySince = $null
            }
            if ($Task)
            {
                $Task.Update($started.Elapsed.TotalSeconds, $limit.TotalSeconds)
            }
            Start-Sleep -Seconds $SettlePollSeconds
        }
    }

    # Installed into the Clean checkpoint, so every reset starts with pwsh and PwshAnsi on disk. The MSI comes
    # straight from GitHub and PwshAnsi through Save-PSResource, so neither needs the NuGet provider.
    $installBaseline = {
        Invoke-Command -VMName $VmName -Credential $Credential -ArgumentList $PwshVersion, $PwshMsiUri -ScriptBlock {
            param($Version, $MsiUri)
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

            $pwshPath = Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\7\pwsh.exe'
            if (-not (Test-Path -LiteralPath $pwshPath))
            {
                $msi = Join-Path -Path $env:TEMP -ChildPath ('PowerShell-{0}-win-x64.msi' -f $Version)
                Invoke-WebRequest -Uri ($MsiUri -f $Version) -OutFile $msi -UseBasicParsing
                $msiArguments = @(
                    '/i'
                    ('"{0}"' -f $msi)
                    '/qn'
                    '/norestart'
                    'ADD_PATH=1'
                    'ENABLE_PSREMOTING=1'
                )
                $exit = (Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArguments -Wait -PassThru).ExitCode
                Remove-Item -LiteralPath $msi -Force -ErrorAction Ignore
                if ($exit -ne 0)
                {
                    throw ('msiexec exited with code {0} installing PowerShell {1}.' -f $exit, $Version)
                }
            }

            # Into the Windows PowerShell modules folder, which Windows PowerShell and pwsh both read;
            # Install-PSResource -Scope AllUsers would write to pwsh's own folder, which Windows PowerShell does not
            # read. Save-PSResource needs no NuGet provider and writes the <Name>\<Version> layout Import-Module
            # expects. The gallery's latest PwshAnsi is the one baked in.
            $targetRoot = Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsPowerShell\Modules'
            $install = {
                param($TargetRoot)
                if (-not (Get-Module -ListAvailable -Name PwshAnsi))
                {
                    Save-PSResource -Name PwshAnsi -Path $TargetRoot -TrustRepository
                }
            }
            & $pwshPath -NoProfile -NoLogo -Command $install -args $targetRoot
            if ($LASTEXITCODE -ne 0)
            {
                throw ('pwsh exited with code {0} installing PwshAnsi.' -f $LASTEXITCODE)
            }
        }
    }

    $takeCheckpoint = {
        Checkpoint-VM -Name $VmName -SnapshotName $CheckpointName
    }

    $null = Start-AnsiTitleAnimation -Text $VmName
    try
    {
        Invoke-AnsiTask -Show Both -ProgressShow Percent -Task @(
            @{ Name = 'Create the disk'; Script = $createDisk }
            @{ Name = ('Apply {0}' -f $build.ImageName); Script = $applyImage }
            @{ Name = 'Make it bootable, with the answer file'; Script = $makeBootable }
            @{ Name = 'Create the machine'; Script = $createMachine }
            @{ Name = 'Start Windows and wait for the sign-in'; Script = $startWindows }
            @{ Name = 'Let Windows finish OOBE and settle'; Script = $settleWindows }
            @{ Name = 'Install PowerShell 7 and PwshAnsi'; Script = $installBaseline }
            @{ Name = ('Take the {0} checkpoint' -f $CheckpointName); Script = $takeCheckpoint }
        )
    }
    finally
    {
        Stop-AnsiTitleAnimation -Title $VmName
    }
}
catch
{
    Format-AnsiException -Exception $_ | Out-AnsiHost
    if (-not $build.VmCreated -and (Test-Path -LiteralPath $vhdPath))
    {
        if ($build.VhdMounted)
        {
            Dismount-VHD -Path $vhdPath -ErrorAction Ignore
            $build.VhdMounted = $false
        }
        Remove-Item -LiteralPath $vhdPath -Force -ErrorAction Ignore
    }
    if ($build.VmCreated)
    {
        Format-AnsiText -Message ('[DarkGray]The machine is left as it is. Remove-SetupTestVm.ps1 -VmName {0} removes it.[/]' -f $VmName) | Out-AnsiHost
    }
    exit 1
}
finally
{
    if ($build.VhdMounted)
    {
        Dismount-VHD -Path $vhdPath -ErrorAction Ignore
    }
    if ($build.IsoMounted)
    {
        Dismount-DiskImage -ImagePath $isoFullPath -ErrorAction Ignore | Out-Null
    }
    foreach ($mount in @($build.SystemRoot, $build.WindowsRoot))
    {
        Remove-Item -LiteralPath $mount -Recurse -Force -ErrorAction Ignore
    }
}

[Console]::WriteLine()
Format-AnsiText -Message ('[BrightGreen]{0} is ready.[/] Next: Sync-SetupTestVm.ps1' -f $VmName) | Out-AnsiHost
