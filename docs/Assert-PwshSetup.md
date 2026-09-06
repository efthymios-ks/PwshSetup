# Assert-PwshSetup

Ensures the calling script runs on pwsh 7.2+ with the latest PwshSetup.  
It is the second guard line, after `Assert-PwshAnsi` and before `Assert-SetupAdmin`.

```powershell
#Requires -Version 5.1
[CmdletBinding()]
param()

Import-Module -Name PwshSetup
Assert-PwshAnsi
Assert-PwshSetup
Assert-SetupAdmin

Invoke-PwshSetup -Path (Join-Path -Path $PSScriptRoot -ChildPath 'steps')
```

## Synopsis

```powershell
Assert-PwshSetup [-Arguments <hashtable>] [-ScriptPath <string>] [-SkipUpdate]
```

## Parameters

| Name          | Default                          | Description                                              |
| ------------- | -------------------------------- | -------------------------------------------------------- |
| `-Arguments`  | the calling script's parameters  | Parameters to pass to the rerun.                         |
| `-ScriptPath` | the calling script               | Script to rerun.                                         |
| `-SkipUpdate` | off                              | Skip the gallery check, for a faster start.              |

## What it does

1 - **PwshSetup update**, unless `-SkipUpdate`.  
It asks the PowerShell Gallery for a newer PwshSetup.  
When there is one, it installs it for the current user and reruns the script to load it.  
Windows PowerShell and pwsh keep separate copies, so each edition checks and updates its own.  
On Windows PowerShell this happens before the move to pwsh, which ends that process.  
When the gallery is out of reach or the install fails, it prints a yellow warning and carries on with the loaded version.

2 - **pwsh check.**  
On Windows PowerShell it reruns the script on pwsh 7.2+.  
When there is none, it installs the latest stable release from the official MSI first, with one UAC prompt for `msiexec`.  
A pwsh 7.2+ already there is used as it is, never updated.

When both are in place it returns at once, with no output.

## The rerun

The script's parameters travel through a temp file, so arrays, switches and hashtables come back intact.  
Each stage (`module-Desktop`, `pwsh`, `module-Core`) is added to `$env:PWSHSETUP_RERUN`, so no stage runs twice.  
`Assert-SetupAdmin` adds its own stage to the same variable.

| Started from                                                        | The rerun                                          |
| ------------------------------------------------------------------- | -------------------------------------------------- |
| A classic Windows PowerShell window: double-click, Run with PowerShell | a new Windows Terminal tab on pwsh; this window exits with `0` |
| A Windows PowerShell tab in Windows Terminal                        | the same tab                                       |
| An editor's terminal, such as VS Code                               | the same window                                    |
| Redirected input or output, such as CI                              | the same window, exit code passed through          |
| No `wt.exe`, `winget` there                                         | Windows Terminal installed, then a tab opens       |
| No `wt.exe`, no `winget`, or offline                                | the same window                                    |
| pwsh 7.2+ already                                                   | no rerun                                           |
| A module update (`module-Desktop`, `module-Core`)                   | the same window                                    |

A classic window keeps its font on rerun, and that font lacks the glyphs PwshAnsi draws with; that is why it moves to Windows Terminal.

## Notes

Call it from a script file, not from a prompt or a scriptblock.  
Pass `-ScriptPath` when calling it from a wrapper.  
The MSI sets `ADD_PATH=1`, `USE_MU=1` and `ENABLE_MU=1`, and never restarts the PC.
