# PwshSetup

Machine setup as a folder of ordered PowerShell steps.  
Each step is a published template by name, your own template, or a step written in place.  
Each says whether it is already done, does its work when it is not, and can ask for a restart.  
The run restarts the machine, signs back in through the user, and carries on by itself.  
The screens are drawn with [PwshAnsi](https://github.com/efthymios-ks/PwshAnsi).

## Contents

- [Overview](docs/Overview.md): how a run works, what it leaves on disk, layout, build
- [`Invoke-PwshSetup`](docs/Invoke-PwshSetup.md): runs a steps folder, across restarts
- [`Assert-SetupAdmin`](docs/Assert-SetupAdmin.md): reruns the calling script elevated, and `Test-SetupAdmin`
- [`Assert-PwshSetup`](docs/Assert-PwshSetup.md): ensures pwsh 7.2+ and the latest PwshSetup, reruns the script to pick it up
- [`New-SetupStep`](docs/New-SetupStep.md): a step written in place, and how the run folder is named
- [`Use-SetupTemplate`](docs/Use-SetupTemplate.md): a step that names a template, published or your own
- [`Write-SetupLog`](docs/Write-SetupLog.md): a log line that shows under the running step
- [`Request-SetupRestart`](docs/Request-SetupRestart.md): a restart a step asks for while it runs
- [`Test-SetupCommand`](docs/Test-SetupCommand.md): the checks most step Tests need, and `Test-SetupProgram`
- [`Update-SetupEnvironment`](docs/Update-SetupEnvironment.md): reloads PATH and the rest after an install
- [`Install-ChocoPackage`](docs/Install-ChocoPackage.md): Chocolatey for steps, and `Invoke-ChocoCommand`
- [`Invoke-SetupSql`](docs/Invoke-SetupSql.md): SQL Server calls, `Invoke-SetupSqlScalar` and `Test-SetupSqlDatabase`
- [`Get-SetupTemplate`](docs/Get-SetupTemplate.md): the templates a step can name, with their parameters
- [Templates](docs/Templates.md): what each published template installs, how it checks, what it takes
- [Hyper-V test machine](docs/HyperV.md): a throwaway Windows to try runs and unpublished builds in

## Quick start

A setup is a folder: a `Setup.ps1`, and a `steps` folder of ordered items.

```
C:\Setup\
  Setup.ps1
  steps\
    010-Install-Chocolatey.ps1     Use-SetupTemplate -Name 'Install-Chocolatey'
    020-Install-Git.ps1            Use-SetupTemplate -Name 'Install-Git'
    030-Install-DotnetSdk.ps1      Use-SetupTemplate -Name 'Install-DotnetSdk' -Parameter @{ Version = 8 }
```

`Setup.ps1`:

```powershell
#Requires -Version 5.1
[CmdletBinding()]
param()

if (-not (Get-Module -ListAvailable -Name PwshSetup))
{
    Install-Module -Name PwshSetup -Scope CurrentUser -Force
}
Import-Module -Name PwshSetup
Assert-PwshAnsi
Assert-PwshSetup
Assert-SetupAdmin

$outcome = Invoke-PwshSetup -Path (Join-Path -Path $PSScriptRoot -ChildPath 'steps') -PassThru
if ($outcome.Status -eq 'Failed')
{
    exit 1
}
```

Copy the folder to the new machine and run `Setup.ps1`, from Windows PowerShell or pwsh.  
The first lines install PwshSetup, and PwshAnsi with it, when missing.  
`Assert-PwshAnsi` moves the script to pwsh 7, installing it when missing.  
`Assert-PwshSetup` loads the latest PwshSetup from the gallery.  
`Assert-SetupAdmin` elevates.  
Then the list opens: F6 runs, F7 dry-runs, each after a y/n.

## Try it without installing anything

```powershell
.\demo\Show-SetupDemo.ps1
.\demo\Show-SetupDemo.ps1 -Fail
.\demo\Show-SetupDemo.ps1 -DryRun
```

The demo steps only wait, write log lines, ask for a restart and fail on request.  
Restarts are skipped.  
It runs from `src`, so it shows the code as it is in the repository.

## Test

Two kinds of tests, a runner each.

```powershell
pwsh -File .\Invoke-Test.ps1
```

The unit tests, every Pester 5 file under `tests\unit\`.  
They parse-check the module source, and need nothing else.  
It exits non-zero when a test fails or none is found.  
`.github/workflows/test.yml` runs them on `windows-latest` for every pull request and every push to `master` or `main`.

```powershell
pwsh -File .\Invoke-SystemTest.ps1
```

The system tests, every Pester 5 file under `tests\system\templates\`, run inside the Hyper-V test machine.  
It creates the machine with `hyperv\New-SetupTestVm.ps1` when there is none, and copies the `hyperv\Setup` folder in.  
It runs that setup unattended, then the tests inside the machine, and can bring the NUnit XML back.  
A template's tests skip when the setup did not install it, so the step files decide which tests run.  
`-Template <patterns>` narrows both the steps and the tests.  
It runs only on a machine with Hyper-V and a Windows ISO under `%LOCALAPPDATA%\PwshSetup\HyperV\iso\`.  
See [Hyper-V test machine](docs/HyperV.md).

## Build and publish

```powershell
pwsh -File .\Publish-SetupModule.ps1 -Version 0.1.0 -SkipTests
pwsh -File .\Publish-SetupModule.ps1 -Version 1.0.0 -Publish -NuGetApiKey $key
```

The suite runs first, and a red one stops the build.  
`-SkipTests` builds without it, and is refused together with `-Publish`.  
The build lands in `artifacts\PwshSetup\<version>\` and is imported in a child session to check it.  
The manifest requires PwshAnsi 0.1.9 or later, so that version has to be installed to build.

| Parameter      | Meaning                                                      |
| -------------- | ------------------------------------------------------------ |
| `-Version`     | Version to stamp. Required.                                  |
| `-OutputPath`  | Where to build. Default `.\artifacts`.                       |
| `-Publish`     | Publish after building; prompts unless `-Force`.             |
| `-Repository`  | Target repository. Default `PSGallery`.                      |
| `-NuGetApiKey` | Falls back to `$env:PSGALLERY_KEY`.                          |
| `-SkipTests`   | Build without the suite. Cannot be combined with `-Publish`. |
| `-Force`       | Overwrite an existing build, and publish without prompting.  |

## Release

`.github/workflows/publish.yml` runs on a version tag, and the tag is the version.  
`v0.3.0` publishes `0.3.0`, `v0.4.0-beta1` publishes `0.4.0` as prerelease `beta1`.  
It installs Pester and PwshAnsi, then calls the same script with the key from the `PSGALLERY_API_KEY` secret.  
`workflow_dispatch` takes a version instead, for a rerun without a new tag.

```powershell
git tag v0.1.0
git push origin v0.1.0
```

## License

MIT.
