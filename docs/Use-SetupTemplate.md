# Use-SetupTemplate

Returns the step a template describes, so a step file can be one line naming it.

```powershell
Use-SetupTemplate -Name 'Install-Git'
```

## Synopsis

```powershell
Use-SetupTemplate -Name <string> [-Parameter <hashtable>]
```

| Parameter    | Description                                                              |
| ------------ | ------------------------------------------------------------------------ |
| `-Name`      | The template, by file name without `.ps1`.                               |
| `-Parameter` | Values for the template's parameters.                                    |

## A run folder

A run folder is a `steps` folder of ordered items.  
Each item is a published template by name, your own template by name, or a step written in place:

```
C:\Setup\
  Setup.ps1
  steps\
    010-Install-Chocolatey.ps1     Use-SetupTemplate -Name 'Install-Chocolatey'
    020-Install-Git.ps1            Use-SetupTemplate -Name 'Install-Git'
    030-Install-DotnetSdk.ps1      Use-SetupTemplate -Name 'Install-DotnetSdk' -Parameter @{ Version = 8 }
    040-Edit-HostsFile.ps1         Use-SetupTemplate -Name 'Edit-HostsFile' -Parameter @{ Entries = '127.0.0.1 shop.local' }
    050-Install-ShopCert.ps1       Use-SetupTemplate -Name 'Install-ShopCert'     (your own, below)
    060-Set-Wallpaper.ps1          New-SetupStep @step                            (written in place)
  templates\
    Install-ShopCert.ps1
```

The numbers set the run order, and only the run folder has them.  
Templates carry none.

## Where it looks

1 - The `templates` folder beside the `steps` folder: your own.  
2 - The templates published with the module: [Templates](Templates.md).

Your own template wins over a published one of the same name, so you can override one without renaming anything.  
A name found in neither throws, and the run stops before anything starts.

## Writing your own

A template is a step file with an optional `param()` block, the same shape as the published ones:

```powershell
<#
.SYNOPSIS
    Imports the shop's development certificate into the machine store.
.PARAMETER Thumbprint
    The certificate to look for.
#>
[CmdletBinding()]
param(
    [string] $Thumbprint = 'A1B2C3D4E5F60718293A4B5C6D7E8F9012345678'
)

$certificate = Join-Path -Path $PSScriptRoot -ChildPath '..\assets\shop-dev.pfx'

$step = @{
    Name   = 'Install shop certificate'
    Test   = { Test-Path -LiteralPath ('Cert:\LocalMachine\Root\{0}' -f $Thumbprint) }
    Action = { $null = Import-PfxCertificate -FilePath $certificate -CertStoreLocation 'Cert:\LocalMachine\Root' }
}
New-SetupStep @step
```

`$PSScriptRoot` inside a template is the template's own folder.  
A parameter the template does not have throws, so a typo in `-Parameter` never passes silently.

## Templates that need values

`Edit-HostsFile`, `Copy-Repository`, `Expand-Archive` and `New-SqlDatabase` throw without theirs.  
[Templates](Templates.md) lists every parameter.
