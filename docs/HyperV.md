# Hyper-V test machine

A throwaway Windows on Hyper-V, to try setup runs, restarts included, and module builds not published yet.  
Three scripts in `hyperv\`, and one end-to-end runner at the repository root.  
Each reruns itself elevated, through the same `Assert-SetupAdmin` as a setup.

| Script                            | Does                                                                            |
| --------------------------------- | ------------------------------------------------------------------------------- |
| `hyperv\New-SetupTestVm.ps1`      | creates the machine from a Windows ISO, signed in, with a Clean checkpoint      |
| `hyperv\Sync-SetupTestVm.ps1`     | goes back to Clean, copies the module builds and a setup folder in, starts it   |
| `hyperv\Remove-SetupTestVm.ps1`   | removes the machine, its disks, its checkpoints and its stored password         |
| `Invoke-SystemTest.ps1`           | runs Sync, waits for `.done`, and runs the system tests inside the machine      |

With no arguments, `Invoke-SystemTest.ps1` does it all: it creates the machine when missing, copies the local builds in, runs the sample setup unattended, and runs the template tests inside the machine.

## What you need

- Hyper-V turned on, with its management tools, in Windows Features.
- A Windows 10 or 11 ISO under `%LOCALAPPDATA%\PwshSetup\HyperV\iso\`.  
  Microsoft rotates its signed download links and blocks automated downloads, so the first ISO is saved there by hand.  
  Both sources are free, from microsoft.com:
  [Windows 11, Home and Pro](https://www.microsoft.com/software-download/windows11),
  [Windows 11 Enterprise Evaluation, no key](https://www.microsoft.com/evalcenter/download-windows-11-enterprise).
- For a PwshSetup build not published yet, a local build.  
  Sync copies the newest one under `artifacts\PwshSetup\<version>\`:

  ```powershell
  pwsh -File .\Publish-SetupModule.ps1 -Version 0.1.0-dev -SkipTests
  ```

  PwshAnsi comes from the gallery into the Clean checkpoint, so it needs no local build.

## Create it

```powershell
.\hyperv\New-SetupTestVm.ps1
```

No questions.  
It uses the newest `.iso` in the folder above; with none there, it prints the download links and stops.  
It generates a `setup` administrator with a random password, and keeps the password encrypted for you under `%LOCALAPPDATA%\PwshSetup\HyperV`.  
It picks the edition from the ISO, preferring Pro, then Enterprise Evaluation, then Enterprise.

The image goes straight onto a new disk with an answer file, so there are no Windows Setup screens.  
Once the first sign-in has settled, it installs pwsh 7 and PwshAnsi, then takes the Clean checkpoint.  
Every reset after that starts on a signed-in desktop that has both.

| Machine setting              | Value                                        | Why                                                    |
| ---------------------------- | -------------------------------------------- | ------------------------------------------------------ |
| Generation, Secure Boot, TPM | 2, on, virtual TPM                           | Windows 11 needs them                                  |
| Memory                       | 8 GB, fixed                                  | nested virtualization needs it fixed                   |
| Nested virtualization        | on                                           | WSL and Docker Desktop inside                          |
| Sign-in                      | automatic, at every start                    | a restart mid-setup carries on with nobody there       |
| Network                      | Default Switch                               | internet through the host                              |
| Checkpoint                   | `Clean`, after the first start and the baseline | Sync goes back to it; `-NoReset` keeps the current state |
| Baseline in Clean            | pwsh 7, PwshAnsi                             | `Setup.ps1` only checks for them                       |

The machine's defaults are in `$VmDefaults` at the top of the script.  
Edit them there, or pass a parameter for one run.

| Parameter         | Default            | Note                                                     |
| ----------------- | ------------------ | -------------------------------------------------------- |
| `-IsoPath`        | newest in the folder | a path of your own instead                             |
| `-Edition`        | picked from the ISO | Pro, then Enterprise Evaluation, then Enterprise        |
| `-VmName`         | `PwshSetup-Test`   |                                                          |
| `-Credential`     | generated          | `setup`, a random password, kept encrypted               |
| `-MemoryGB`       | `8`                | 4 to 64, fixed                                           |
| `-ProcessorCount` | `4`                | 2 to 32                                                  |
| `-DiskGB`         | `128`              | 32 to 1024, grows as used                                |
| `-SwitchName`     | `Default Switch`   |                                                          |
| `-Locale`         | `en-US`            | a language the ISO has                                   |
| `-ProductKey`     | none               | only for editions that ask for one                       |

Inside the machine, the answer file holds the password in plain text: keep the machine throwaway.

## Try a run

```powershell
.\hyperv\Sync-SetupTestVm.ps1
```

With no arguments it goes back to Clean, copies the newest local builds and the sample setup in, starts `Setup.ps1` on the desktop, and opens the machine's window.

| Parameter     | Does                                                                   |
| ------------- | ---------------------------------------------------------------------- |
| `-NoReset`    | keeps the current state instead of going back to Clean                  |
| `-NoRun`      | copies everything but does not start `Setup.ps1`                        |
| `-NoConnect`  | does not open the machine's window                                      |
| `-SetupPath`  | the folder copied to `C:\Setup`. Default `hyperv\Setup`                 |
| `-ModulePath` | module build folders, `<Name>\<Version>`. Default the newest local builds |

1 - When the machine does not exist, `New-SetupTestVm.ps1` creates it.  
2 - It goes back to the Clean checkpoint.  
3 - It checks that pwsh 7 and PwshAnsi are there, and stops when one is missing.  
4 - It copies the newest local PwshSetup build to `C:\Program Files\WindowsPowerShell\Modules`.  
5 - It copies the setup folder to `C:\Setup`.  
6 - A scheduled task starts `Setup.ps1` on the signed-in desktop, elevated.  
7 - It opens the machine's window.

The task starts `Setup.ps1` in Windows PowerShell.  
The script moves itself to pwsh 7, which both modules need, and runs `Invoke-PwshSetup -Unattended`.

The sample setup in `hyperv\Setup` uses almost every published template, so the system tests have something to check:

```
hyperv\Setup\
  Setup.ps1
  steps\
    010-Install-Chocolatey.ps1      Use-SetupTemplate -Name 'Install-Chocolatey'
    020-Install-Git.ps1             Use-SetupTemplate -Name 'Install-Git'
    030-Restart-Once.ps1            Use-SetupTemplate -Name 'Restart-Once'     (its own template, below)
    ...                             one step per published template
    275-New-TestArchive.ps1         a step of this setup: the ZIP the Expand-Archive step unpacks
    285-Wait-SqlServer.ps1          a step of this setup: SQL Server started and taking connections
    290-New-SqlDatabase.ps1
  templates\
    Restart-Once.ps1                restarts once, to see the run carry on
```

The whole setup restarts several times, for Visual Studio, SQL Server, WSL, Docker Desktop and the .NET Framework developer pack.  
For a short loop, narrow it with `-Template`, below.

## Run the system tests

```powershell
.\Invoke-SystemTest.ps1
```

It does everything above, then:

1 - It waits for the `C:\Setup\.done` that `Setup.ps1` writes at the end.  
Meanwhile it reads `C:\Setup\.log` as it grows, so the run shows on the host as it happens.  
2 - A restart ends the PowerShell Direct sessions, so it opens new ones on the next poll.  
3 - Once `.done` is there, it copies `tests\system\templates\` to `C:\SystemTests` and runs Pester inside the machine.  
A template's tests skip when the setup did not install it, so the step files decide which tests run.  
4 - With `-ResultPath`, it brings the NUnit XML back.

| Parameter          | Default            | Note                                               |
| ------------------ | ------------------ | -------------------------------------------------- |
| `-VmName`          | `PwshSetup-Test`   |                                                    |
| `-TestPath`        | `tests\system`     | folder of `*.Tests.ps1`                            |
| `-TimeoutMinutes`  | `45`               | how long to wait for `.done`                       |
| `-PollSeconds`     | `3`                | how often to read `.log` and look for `.done`      |
| `-ResultPath`      | none               | where to put the NUnit XML                         |
| `-Template`        | `*`, everything    | name patterns, below                               |

`-Template` matches `*pattern*` against the step files in `hyperv\Setup\steps` and the test files in `tests\system\templates`.  
A narrowed run copies only the matching steps, with `Setup.ps1` and the setup's own templates, and runs only the matching tests.  
It adds no dependencies on its own: a Chocolatey package needs the `Chocolatey` pattern too.

```powershell
# Every template; raise the timeout to cover every restart
.\Invoke-SystemTest.ps1 -TimeoutMinutes 180

# One template and Chocolatey
.\Invoke-SystemTest.ps1 -Template Chocolatey, K9s

# Everything SQL
.\Invoke-SystemTest.ps1 -Template Chocolatey, Sql

# Keep the results
.\Invoke-SystemTest.ps1 -ResultPath .\system-results.xml
```

`Setup.ps1` writes three files in `C:\Setup\` for the runner to follow:

| File       | Written                                                         |
| ---------- | --------------------------------------------------------------- |
| `.running` | at every start, including each start after a restart           |
| `.log`     | all along: a transcript of every start, appended               |
| `.done`    | once, at the end, with the outcome as JSON                     |

`.done` exists only once the run has returned, so it never shows up halfway through a restart.

## Remove it

```powershell
.\hyperv\Remove-SetupTestVm.ps1
.\hyperv\Remove-SetupTestVm.ps1 -WhatIf
```

No prompt: it turns the machine off and deletes it, every disk in its chain, and the stored password.  
`-WhatIf` says what it would remove.  
The ISO folder stays, so the next machine reuses it.
