# Assert-SetupAdmin

Ensures the calling script runs as administrator.  
It is the last of the guard lines at the top of the script that starts the setup.

```powershell
Import-Module -Name PwshSetup
Assert-PwshAnsi
Assert-PwshSetup
Assert-SetupAdmin
```

## Synopsis

```powershell
Assert-SetupAdmin [-Arguments <hashtable>] [-ScriptPath <string>]
Test-SetupAdmin
```

## Parameters

| Name          | Default                          | Description                          |
| ------------- | -------------------------------- | ------------------------------------ |
| `-Arguments`  | the calling script's parameters  | Parameters to pass to the rerun.     |
| `-ScriptPath` | the calling script               | Script to rerun.                     |

## What it does

Already elevated: returns at once, with no output.  
Otherwise it reruns the script elevated, after one UAC prompt, and this window ends.

| Started from                       | The elevated rerun                  |
| ---------------------------------- | ----------------------------------- |
| Anywhere, Windows Terminal found   | a new Windows Terminal window       |
| Anywhere, no Windows Terminal      | a new console window                |
| UAC declined                       | nothing; it throws                  |

The rerun keeps the working folder and the script's parameters, carried through a temp file.  
It marks itself in `$env:PWSHSETUP_RERUN`, so a rerun that is still not elevated throws instead of looping.  
A script that fails before the run starts keeps its window open on the error.

## Why last

`Assert-PwshAnsi` moves the script to pwsh 7, installing it when missing.  
`Assert-PwshSetup` loads the latest PwshSetup.  
Elevating after both means the elevated window starts on pwsh with the latest module, and each move happens once.  
All three work on Windows PowerShell 5.1, so the order is a choice, not a requirement.

## Test-SetupAdmin

`$true` when the session runs as administrator.

```powershell
if (-not (Test-SetupAdmin))
{
    'Not elevated'
}
```

## Windows PowerShell

On Windows PowerShell the module exports the bootstrap only: `Assert-PwshSetup`, `Assert-SetupAdmin` and `Test-SetupAdmin`.  
Everything else loads once the script runs on pwsh 7.2+.
