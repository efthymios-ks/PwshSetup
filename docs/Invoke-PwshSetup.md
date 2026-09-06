# Invoke-PwshSetup

Runs the steps in a folder, in order, and carries on across restarts by itself.

```powershell
Invoke-PwshSetup -Path (Join-Path -Path $PSScriptRoot -ChildPath 'steps')
```

## Synopsis

```powershell
Invoke-PwshSetup [-Path] <string>
                 [-LogPath <string>]
                 [-Unattended]
                 [-SkipRestart]
                 [-ScriptPath <string>]
                 [-Arguments <hashtable>]
                 [-PassThru]
                 [-WhatIf]
```

## Parameters

| Name           | Default                             | Description                                                     |
| -------------- | ----------------------------------- | --------------------------------------------------------------- |
| `-Path`        | required                            | The steps folder. Every `.ps1` in it is a step, in number order. |
| `-LogPath`     | `%ProgramData%\PwshSetup\Logs`      | Folder for the log files, one per run.                          |
| `-Unattended`  | off                                 | Run straight away, without the list and the confirm.            |
| `-SkipRestart` | off                                 | Note a needed restart and carry on without one.                 |
| `-ScriptPath`  | the calling script                  | Script the resume task starts after a restart.                  |
| `-Arguments`   | the calling script's parameters     | Parameters the resume task passes back to it.                   |
| `-PassThru`    | off                                 | Return the outcome.                                             |
| `-WhatIf`      | off                                 | The dry run, without the list: show what each step would do.    |

Needs an elevated session, except with `-WhatIf`.  
Call [`Assert-SetupAdmin`](Assert-SetupAdmin.md) before it.

## The list

The folder is the plan: every step in it runs, in the order of its number.  
The run opens on the list, read from the files without running any of them:

```
─ PwshSetup ───────────────────────────────────────────────────────────────
Steps     C:\Setup\steps
Machine   DEV-01  setup

F6 Run · F7 Dry run · Esc Quit
╭─────┬────────────────────────────┬────────────────────┬──────────────────────────────╮
│ #   │ Step                       │ From               │ Does                         │
├─────┼────────────────────────────┼────────────────────┼──────────────────────────────┤
│ 010 │ Install Chocolatey         │ Install-Chocolatey │ run                          │
├─────┼────────────────────────────┼────────────────────┼──────────────────────────────┤
│ 020 │ Install Git                │ Install-Git        │ install git                  │
├─────┼────────────────────────────┼────────────────────┼──────────────────────────────┤
│ 030 │ Restart once               │ Restart-Once       │ run, then restart            │
├─────┼────────────────────────────┼────────────────────┼──────────────────────────────┤
│ 040 │ Set wallpaper              │ own                │ run                          │
╰─────┴────────────────────────────┴────────────────────┴──────────────────────────────╯
```

| Key | Does                                                                         |
| --- | ---------------------------------------------------------------------------- |
| F6  | "Run 4 steps? [y/N]", then the run.                                          |
| F7  | "Dry run 4 steps? [y/N]", then the dry run; a key goes back to the list.     |
| Esc | Quits. Nothing ran.                                                          |

Both confirms default to No, so Enter alone never starts anything.  
The list redraws when the window is resized.

## The run

Each step is checked right before it runs, and skipped when its Test says it is done.  
A step that needs a restart ends the run there: it registers itself for the next sign-in, counts down ten seconds, and restarts.  
The full walk-through is in the [Overview](Overview.md#how-a-run-goes).

## Dry run

F7 on the list, or `-WhatIf` without it.  
Every step's Test runs, since Tests only look, and nothing else does.

```
✔ Checking 4 steps  0.6s
╭─────┬────────────────────┬───────────────────────────╮
│ #   │ Step               │ Would                     │
├─────┼────────────────────┼───────────────────────────┤
│ 010 │ Install Chocolatey │ skip, already done        │
├─────┼────────────────────┼───────────────────────────┤
│ 020 │ Install Git        │ install git               │
├─────┼────────────────────┼───────────────────────────┤
│ 030 │ Restart once       │ run, then restart         │
├─────┼────────────────────┼───────────────────────────┤
│ 040 │ Set wallpaper      │ run                       │
╰─────┴────────────────────┴───────────────────────────╯
Dry run: 3 of 4 steps would run, and 1 would restart the machine. Nothing ran.
```

| Would                    | When                                                                                   |
| ------------------------ | -------------------------------------------------------------------------------------- |
| `skip, already done`     | the step's Test returned `$true`                                                       |
| `install <packages>`     | the Action calls `Install-ChocoPackage` with these names, read from its code            |
| `... and more`           | some names are only known once the Action runs                                         |
| `run`                    | the step does something else; only running it would say what                          |
| `then restart`           | the step has `-RequiresRestart`. A package can still ask for one at install time.      |
| `(check failed: ...)`    | the Test threw, often because it checks something an earlier step installs             |

## Resuming

A run remembers its steps and their results per steps folder, under `%ProgramData%\PwshSetup\State`.

| The next run finds a state file and              | It                                               |
| ------------------------------------------------ | ------------------------------------------------ |
| the machine restarted since the run asked        | carries on, no list, no questions                |
| was started by the resume task                   | carries on, no list, no questions                |
| `-Unattended`                                    | carries on, no list, no questions                |
| anything else (a failure, a cancelled restart)   | asks whether to carry on; No goes to the list    |

Carrying on runs what is left: steps that failed, steps waiting for a restart, and steps not reached.

## Outcome

With `-PassThru` it returns one object:

| Property   | Meaning                                                                              |
| ---------- | ------------------------------------------------------------------------------------ |
| `Status`   | `Finished`, `Failed`, `Restarting`, `Cancelled` or `DryRun`.                         |
| `LogFile`  | The run's log, empty when nothing ran.                                               |
| `Duration` | A `[TimeSpan]` from the run's first start, restarts included; zero when nothing ran. |

```powershell
$outcome = Invoke-PwshSetup -Path $steps -PassThru
if ($outcome.Status -eq 'Failed')
{
    exit 1
}
```

## Windows it opens

A window this run opened itself, the elevated one or the resumed one, waits for a key at the end, so the summary can be read.  
A run started from your own terminal ends straight away.
