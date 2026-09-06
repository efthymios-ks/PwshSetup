# New-SetupStep

Describes one setup step.  
A step written in place in the run folder returns one, and so does every template.

```powershell
$step = @{
    Name   = 'Install Git'
    Test   = { Test-SetupCommand -Name 'git' }
    Action = { Install-ChocoPackage -Name 'git' }
}
New-SetupStep @step
```

## Synopsis

```powershell
New-SetupStep -Name <string> -Action <scriptblock> [-Test <scriptblock>] [-RequiresRestart]
```

## Parameters

| Name               | Description                                                                          |
| ------------------ | ------------------------------------------------------------------------------------ |
| `-Name`            | What the screen and the log call the step.                                           |
| `-Action`          | The work. Throwing fails the step and stops the run.                                 |
| `-Test`            | `$true` when the work is already done, so the step is skipped. Omit it and the step always runs. |
| `-RequiresRestart` | Restart once the Action is done. The run carries on with the next step after the sign-in. |

## The run folder

A steps folder holds one `.ps1` per step, named `<number>-<Verb-Noun>.ps1`.  
The number sets the run order:

```
steps\
  010-Install-Chocolatey.ps1
  020-Install-Git.ps1
  110-Install-VisualStudio2026.ps1
  260-Edit-HostsFile.ps1
```

Numbers 10 apart leave room to slot a step in later.  
A file without a number runs after the numbered ones, by name.  
Each file returns one step: `New-SetupStep`, written in place, or [`Use-SetupTemplate`](Use-SetupTemplate.md), naming a template.

## The Test

The last thing the Test writes decides, by PowerShell truthiness.  
`$true` skips the step; `$false`, nothing, or an empty `-match` runs it.  
A Test that throws runs the step too, and the log says why.  
Tests should only look: the dry run calls every one of them.

## Values at the top

A step file can set values at its top, and its Test and Action see them when they run later:

```powershell
$entries = @(
    '127.0.0.1 example1.local'
)

$step = @{
    Name   = 'Edit hosts file'
    Test   = { ... $entries ... }
    Action = { ... $entries ... }
}
New-SetupStep @step
```

Each file and each template is loaded in a module of its own, so those values stay with it and never clash with another's.

## What steps run with

| Setting                  | Value                | Why                                                       |
| ------------------------ | -------------------- | --------------------------------------------------------- |
| `$ErrorActionPreference` | `Stop`               | An error fails the step instead of passing as done.       |
| `$ProgressPreference`    | `SilentlyContinue`   | A progress bar would draw over the run's own lines.       |
| Session                  | elevated, pwsh 7.2+  | Installers need it.                                       |

## Output

| What the step writes                       | Where it goes                                         |
| ------------------------------------------ | ----------------------------------------------------- |
| `Write-SetupLog`                           | the log, and dimmed under the running step on screen  |
| output, errors and warnings, native output | the log only                                          |
| `Write-Host`                               | the screen, between the progress lines; avoid it      |

A command that writes to the host, such as an installer script, goes to the log with `*>&1`:

```powershell
& $installer *>&1
```

## Restarts

`-RequiresRestart` is for steps that always need one.  
A step that only sometimes does calls [`Request-SetupRestart`](Request-SetupRestart.md).  
[`Install-ChocoPackage`](Install-ChocoPackage.md) does that on its own when a package asks.
