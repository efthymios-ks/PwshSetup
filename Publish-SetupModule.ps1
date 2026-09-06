<#
.SYNOPSIS
    Builds src into one PwshSetup module, then optionally publishes it.
.DESCRIPTION
    Runs the Pester suite first and stops on a red one, so a failing suite never builds or publishes.
    Then merges the sources into artifacts\PwshSetup\<version>:
      PwshSetup.psm1      the loader, from Assert-SetupAdmin.psm1 and Assert-PwshSetup.psm1. Windows PowerShell
                          syntax, so 5.1 imports it.
      PwshSetupCore.ps1   everything else, dot-sourced by the loader on pwsh 7.2+.
      PwshSetup.psd1      the manifest, with PwshAnsi as a required module.
      Templates\          the step templates.
    Per-file #Requires, sibling Import-Module lines and Export-ModuleMember lists are dropped; the manifest's
    FunctionsToExport, read from those lists, decides what is public.
    Validates the build by parsing it, testing the manifest, and importing it in a child session.
    Publishes only with -Publish.
.PARAMETER Version
    Version to stamp. A prerelease suffix is allowed: 1.2.0-beta1 is stamped as 1.2.0 with Prerelease beta1.
.PARAMETER OutputPath
    Where to build.
.PARAMETER Repository
    Repository to publish to.
.PARAMETER NuGetApiKey
    API key for -Publish. Falls back to $env:PSGALLERY_KEY.
.PARAMETER Publish
    Publish after building. Prompts unless -Force.
.PARAMETER SkipTests
    Build without the suite. Refused together with -Publish.
.PARAMETER Force
    Overwrite an existing build, and publish without prompting.
.NOTES
    Exit codes: 0 built (and published when asked), 1 a step failed.
.EXAMPLE
    .\Publish-SetupModule.ps1 -Version 0.1.0 -SkipTests
.EXAMPLE
    .\Publish-SetupModule.ps1 -Version 1.0.0 -Publish -NuGetApiKey $key
#>
#Requires -Version 7.2
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Build console output, read by a person or a CI log.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [ValidatePattern('^\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$')] [string] $Version,
    [ValidateNotNullOrEmpty()] [string] $OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath 'artifacts'),
    [ValidateNotNullOrEmpty()] [string] $Repository = 'PSGallery',
    [string] $NuGetApiKey,
    [switch] $Publish,
    [switch] $SkipTests,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A new GUID would look like a different module to the gallery.
$ModuleName = 'PwshSetup'
$ModuleGuid = '17dd0be0-8c54-4739-96fe-a17b43bc5aa6'
$Author = 'Efthymios Koktsidis'
$PwshAnsiVersion = '0.1.9'
$LoaderModule = 'Assert-SetupAdmin.psm1'
$LoaderExtras = @('Assert-PwshSetup.psm1')
$InternalModule = @('Core.psm1', 'Steps.psm1', 'State.psm1', 'Restart.psm1', 'Shell.psm1')
$CoreOrder = @(
    'Core.psm1'
    'Steps.psm1'
    'State.psm1'
    'Restart.psm1'
    'Shell.psm1'
    'New-SetupStep.psm1'
    'Write-SetupLog.psm1'
    'Request-SetupRestart.psm1'
    'Test-SetupCommand.psm1'
    'Update-SetupEnvironment.psm1'
    'Get-SetupTemplate.psm1'
    'Use-SetupTemplate.psm1'
    'Install-ChocoPackage.psm1'
    'Invoke-SetupSql.psm1'
    'Invoke-PwshSetup.psm1'
)

$moduleVersion = $Version
$prerelease = ''
if ($Version -match '^(?<base>\d+\.\d+\.\d+)-(?<pre>[A-Za-z0-9.]+)$')
{
    $moduleVersion = $Matches['base']
    $prerelease = $Matches['pre']
}

# ── Console ──────────────────────────────────────────────────────────────────

function Write-BuildStep
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message
    )

    Write-Host -Object ''
    Write-Host -Object ('== {0}' -f $Message) -ForegroundColor Cyan
}

function Write-BuildGood
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message
    )

    Write-Host -Object ('   [ok]   {0}' -f $Message) -ForegroundColor Green
}

function Write-BuildNote
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message
    )

    Write-Host -Object ('          {0}' -f $Message) -ForegroundColor DarkGray
}

function Stop-Build
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message
    )

    Write-Host -Object ('   [fail] {0}' -f $Message) -ForegroundColor Red
    exit 1
}

# ── Sources ──────────────────────────────────────────────────────────────────

function Get-MergedBody
{
    # A source file without what a merged file must not keep: version guards, sibling imports, the export list.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    $kept = [System.Collections.Generic.List[string]]::new()
    $inExport = $false
    foreach ($line in (Get-Content -LiteralPath $Path))
    {
        if ($inExport)
        {
            $inExport = $line -match ',\s*$'
            continue
        }
        if ($line -match '^\s*#Requires\b')
        {
            continue
        }
        if ($line -match '^\s*Import-Module\s+-Name\s+\(Join-Path\s+-Path\s+\$PSScriptRoot\b')
        {
            continue
        }
        if ($line -match '^\s*Export-ModuleMember\b')
        {
            $inExport = $line -match ',\s*$'
            continue
        }
        $kept.Add($line)
    }
    return ($kept -join [Environment]::NewLine).Trim()
}

function Get-ExportedFunction
{
    # The names a source file exports, so the manifest cannot drift from the sources.
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    $text = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($text, '(?ms)^\s*Export-ModuleMember\s+-Function\s+(?<list>.*?)(?=\r?\n\s*\r?\n|\z)')
    if (-not $match.Success)
    {
        return @()
    }
    $names = $match.Groups['list'].Value -split ',' | ForEach-Object -Process { $_.Trim() } |
        Where-Object -FilterScript { $_ -match '^[A-Za-z]+-[A-Za-z][A-Za-z0-9]*$' }
    return @($names)
}

# ── Tests ────────────────────────────────────────────────────────────────────

Write-Host -Object ''
Write-Host -Object ('{0} {1}' -f $ModuleName, $Version) -ForegroundColor White

Write-BuildStep -Message 'tests'
if ($SkipTests -and $Publish)
{
    Stop-Build -Message '-SkipTests cannot be combined with -Publish: a published build must be tested'
}
if ($SkipTests)
{
    Write-BuildNote -Message 'skipped (-SkipTests): build only, publishing is refused'
}
else
{
    $runner = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-Test.ps1'
    & $runner -Output None | Out-Host
    if ($LASTEXITCODE -ne 0)
    {
        Stop-Build -Message ('tests failed (exit {0}), nothing was built or published' -f $LASTEXITCODE)
    }
    Write-BuildGood -Message 'suite green'
}

Write-BuildStep -Message 'sources'
$sourceRoot = Join-Path -Path $PSScriptRoot -ChildPath 'src'
$templateRoot = Join-Path -Path $PSScriptRoot -ChildPath 'templates'
$loaderPath = Join-Path -Path $sourceRoot -ChildPath $LoaderModule

$coreFiles = foreach ($name in $CoreOrder)
{
    $path = Join-Path -Path $sourceRoot -ChildPath $name
    if (-not (Test-Path -LiteralPath $path))
    {
        Stop-Build -Message ('missing source: {0}' -f $name)
    }
    $path
}

$loaderExtraPaths = foreach ($name in $LoaderExtras)
{
    $path = Join-Path -Path $sourceRoot -ChildPath $name
    if (-not (Test-Path -LiteralPath $path))
    {
        Stop-Build -Message ('missing source: {0}' -f $name)
    }
    $path
}
$onDisk = @(Get-ChildItem -LiteralPath $sourceRoot -Filter '*.psm1' -File | Select-Object -ExpandProperty Name)
$missed = @($onDisk | Where-Object -FilterScript { $_ -ne $LoaderModule -and $LoaderExtras -notcontains $_ -and $CoreOrder -notcontains $_ })
if ($missed.Count -gt 0)
{
    Stop-Build -Message ('not in the build order: {0}' -f ($missed -join ', '))
}
Write-BuildGood -Message ('loader: {0} (+ {1} extra)  core: {2} modules' -f $LoaderModule, $LoaderExtras.Count, @($coreFiles).Count)

$publicFunctions = [System.Collections.Generic.List[string]]::new()
foreach ($path in @($loaderPath) + @($loaderExtraPaths) + @($coreFiles))
{
    if ((Split-Path -Path $path -Leaf) -in $InternalModule)
    {
        continue
    }
    foreach ($name in (Get-ExportedFunction -Path $path))
    {
        if (-not $publicFunctions.Contains($name))
        {
            $publicFunctions.Add($name)
        }
    }
}
Write-BuildGood -Message ('{0} public functions: {1}' -f $publicFunctions.Count, ($publicFunctions -join ', '))

# ── Build ────────────────────────────────────────────────────────────────────

$moduleRoot = Join-Path -Path (Join-Path -Path $OutputPath -ChildPath $ModuleName) -ChildPath $moduleVersion
$loaderOutput = Join-Path -Path $moduleRoot -ChildPath ('{0}.psm1' -f $ModuleName)
$coreOutput = Join-Path -Path $moduleRoot -ChildPath ('{0}Core.ps1' -f $ModuleName)
$manifestOutput = Join-Path -Path $moduleRoot -ChildPath ('{0}.psd1' -f $ModuleName)

Write-BuildStep -Message ('build -> {0}' -f $moduleRoot)
if (Test-Path -LiteralPath $moduleRoot)
{
    if (-not ($Force -or $PSCmdlet.ShouldProcess($moduleRoot, 'Overwrite existing build')))
    {
        Stop-Build -Message 'build folder exists; pass -Force to overwrite'
    }
    Remove-Item -LiteralPath $moduleRoot -Recurse -Force
}
$null = New-Item -ItemType Directory -Path $moduleRoot -Force
$newLine = [Environment]::NewLine

$loaderHeader = @(
    '#Requires -Version 5.1'
    ''
    ('# {0} {1}, built by Publish-SetupModule.ps1. Do not edit this file.' -f $ModuleName, $Version)
    ('# On pwsh 7.2+ it loads the whole module from {0}Core.ps1.' -f $ModuleName)
    '# On Windows PowerShell it exports the bootstrap only: Assert-PwshSetup, Assert-SetupAdmin and Test-SetupAdmin.'
) -join $newLine
$loaderTail = @(
    'if ($PSVersionTable.PSVersion -ge [version]''7.2'')'
    '{'
    ('    . (Join-Path -Path $PSScriptRoot -ChildPath ''{0}Core.ps1'')' -f $ModuleName)
    '}'
    ''
    '# The manifest''s FunctionsToExport decides what is public; helpers stay hidden.'
    'Export-ModuleMember -Function *'
) -join $newLine
$loaderBodies = @(Get-MergedBody -Path $loaderPath)
foreach ($extraPath in $loaderExtraPaths)
{
    $loaderBodies += Get-MergedBody -Path $extraPath
}
$loaderParts = @($loaderHeader) + $loaderBodies + @($loaderTail)
Set-Content -LiteralPath $loaderOutput -Value (($loaderParts -join ($newLine * 2)) + $newLine) -Encoding utf8BOM
Write-BuildGood -Message ('{0}.psm1' -f $ModuleName)

$coreParts = [System.Collections.Generic.List[string]]::new()
$coreParts.Add(('# {0}Core.ps1 {1}, built from src by Publish-SetupModule.ps1. Do not edit this file.' -f $ModuleName, $Version))
foreach ($path in $coreFiles)
{
    $name = Split-Path -Path $path -Leaf
    $coreParts.Add(('#region {0}' -f $name))
    $coreParts.Add((Get-MergedBody -Path $path))
    $coreParts.Add(('#endregion {0}' -f $name))
}
Set-Content -LiteralPath $coreOutput -Value (($coreParts -join ($newLine * 2)) + $newLine) -Encoding utf8BOM
Write-BuildGood -Message ('{0}Core.ps1' -f $ModuleName)

Copy-Item -LiteralPath $templateRoot -Destination (Join-Path -Path $moduleRoot -ChildPath 'Templates') -Recurse
$templateCount = @(Get-ChildItem -LiteralPath (Join-Path -Path $moduleRoot -ChildPath 'Templates') -Filter '*.ps1').Count
Write-BuildGood -Message ('Templates, {0} files' -f $templateCount)

$manifest = @{
    Path                 = $manifestOutput
    RootModule           = ('{0}.psm1' -f $ModuleName)
    ModuleVersion        = $moduleVersion
    GUID                 = $ModuleGuid
    Author               = $Author
    CompanyName          = $Author
    Copyright            = ('(c) {0} {1}. All rights reserved.' -f [datetime]::UtcNow.Year, $Author)
    Description          = 'Machine setup as ordered PowerShell steps: checks what is done, runs the rest, restarts and carries on by itself. Drawn with PwshAnsi.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    RequiredModules      = @(@{ ModuleName = 'PwshAnsi'; ModuleVersion = $PwshAnsiVersion })
    FunctionsToExport    = @($publicFunctions)
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    Tags                 = @('Setup', 'Provisioning', 'Bootstrap', 'Automation', 'Chocolatey', 'Windows', 'Restart', 'Unattended')
    ProjectUri           = 'https://github.com/efthymios-ks/PwshSetup'
    LicenseUri           = 'https://github.com/efthymios-ks/PwshSetup/blob/master/LICENSE'
    ReleaseNotes         = ('{0} {1}' -f $ModuleName, $Version)
}
if ($prerelease)
{
    $manifest.Prerelease = $prerelease
}
New-ModuleManifest @manifest
Write-BuildGood -Message ('{0}.psd1' -f $ModuleName)

# ── Validate ─────────────────────────────────────────────────────────────────

Write-BuildStep -Message 'validate'
foreach ($file in @($loaderOutput, $coreOutput))
{
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$errors)
    if ($errors -and $errors.Count -gt 0)
    {
        Stop-Build -Message ('{0} does not parse: line {1}: {2}' -f (Split-Path -Path $file -Leaf), $errors[0].Extent.StartLineNumber, $errors[0].Message)
    }
}
Write-BuildGood -Message 'both files parse'

try
{
    $null = Test-ModuleManifest -Path $manifestOutput -ErrorAction Stop
}
catch
{
    Stop-Build -Message ('manifest is not valid: {0}' -f $_.Exception.Message)
}
Write-BuildGood -Message 'manifest is valid'

# A child session, so this one keeps whatever it has loaded.
$check = @(
    '$ErrorActionPreference = ''Stop'''
    ('Import-Module -Name ''{0}'' -Force' -f $manifestOutput)
    ('$exported = @((Get-Module -Name ''{0}'').ExportedFunctions.Keys)' -f $ModuleName)
    ('if ($exported.Count -ne {0}) {{ throw (''exported {{0}} functions, expected {0}'' -f $exported.Count) }}' -f $publicFunctions.Count)
    ('$templates = @(Get-SetupTemplate)')
    ('Format-AnsiText -Message (''[BrightGreen]{0} imports:[/] {{0}} functions, {{1}} templates'' -f $exported.Count, $templates.Count) | Out-AnsiHost' -f $ModuleName)
) -join $newLine
& (Get-Process -Id $PID).Path -NoProfile -NoLogo -Command $check | Out-Host
if ($LASTEXITCODE -ne 0)
{
    Stop-Build -Message 'built module failed to import'
}
Write-BuildGood -Message 'imports'

# ── Publish ──────────────────────────────────────────────────────────────────

if (-not $Publish)
{
    Write-Host -Object ''
    Write-Host -Object ('Built {0} {1}' -f $ModuleName, $Version) -ForegroundColor Green
    Write-BuildNote -Message ('import: Import-Module -Name ''{0}'' -Force' -f $manifestOutput)
    Write-Host -Object ''
    exit 0
}

Write-BuildStep -Message ('publish -> {0}' -f $Repository)
$key = $NuGetApiKey
if (-not $key)
{
    $key = $env:PSGALLERY_KEY
}
if (-not $key)
{
    Stop-Build -Message 'no API key: pass -NuGetApiKey or set $env:PSGALLERY_KEY'
}
if (-not ($Force -or $PSCmdlet.ShouldProcess(('{0} {1}' -f $ModuleName, $Version), ('Publish to {0}' -f $Repository))))
{
    Write-BuildNote -Message 'declined, nothing was published'
    exit 0
}

try
{
    Publish-Module -Path $moduleRoot -Repository $Repository -NuGetApiKey $key -Force -ErrorAction Stop
}
catch
{
    Stop-Build -Message ('publish failed: {0}' -f $_.Exception.Message)
}
Write-BuildGood -Message ('published {0} {1} to {2}' -f $ModuleName, $Version, $Repository)
Write-Host -Object ''
exit 0
