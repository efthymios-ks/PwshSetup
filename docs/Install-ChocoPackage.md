# Install-ChocoPackage and Invoke-ChocoCommand

Chocolatey for steps: success decided by the exit code, restarts handled, PATH reloaded.

```powershell
Install-ChocoPackage -Name 'git'
Install-ChocoPackage -Name 'googlechrome' -AdditionalArgument '--ignore-checksums'
Install-ChocoPackage -Name 'sql-server-2022' -AdditionalArgument '--params', "'/SECURITYMODE:SQL /SAPWD:$password'"
```

## Synopsis

```powershell
Install-ChocoPackage -Name <string> [-Version <string>] [-AdditionalArgument <string[]>] [-PassThru]
Invoke-ChocoCommand -ArgumentList <string[]>
```

## Install-ChocoPackage

Runs `choco install <name> --yes --no-progress`, plus `--version` and the extra arguments.

| Exit code      | Means                                              | Then                                                    |
| -------------- | -------------------------------------------------- | ------------------------------------------------------- |
| `0`            | installed                                          | PATH reloaded                                           |
| `1641`, `3010` | installed, and asks for a restart                  | PATH reloaded, restart after the step                   |
| `350`, `1604`  | Chocolatey saw a pending restart and did nothing   | restart, then the step runs again                       |
| anything else  | failed                                             | throws, with the last 15 lines of Chocolatey's output   |

The restarts go through [`Request-SetupRestart`](Request-SetupRestart.md), so the run decides when.  
The screen shows the command line and one result line under the step; the full output goes to the log.

| Parameter             | Description                                               |
| --------------------- | --------------------------------------------------------- |
| `-Name`               | The package id, as on community.chocolatey.org.           |
| `-Version`            | A version to pin. The latest when omitted.                |
| `-AdditionalArgument` | More choco arguments, one per item.                       |
| `-PassThru`           | Return the result: `ExitCode` and `Output`.               |

## Invoke-ChocoCommand

Runs `choco` with any arguments and returns `ExitCode` and `Output`, without judging them.  
Throws when Chocolatey is not installed.

```powershell
$null = Invoke-ChocoCommand -ArgumentList 'feature', 'enable', '--name=exitOnRebootDetected'
```

## Chocolatey itself

The `Install-Chocolatey` template installs it and turns on `exitOnRebootDetected`.  
With that on, Chocolatey refuses to install over a pending restart (exit `350`), and the run restarts first.  
Put that template first: every package step needs `choco`.
