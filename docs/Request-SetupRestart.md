# Request-SetupRestart

Asks for a restart once the running step ends.  
For steps that only sometimes need one; a step that always does has `-RequiresRestart`.

```powershell
$process = Start-Process -FilePath $installer -ArgumentList '/quiet' -Wait -PassThru
if ($process.ExitCode -eq 3010)
{
    Request-SetupRestart
}
```

## Synopsis

```powershell
Request-SetupRestart [-Retry]
```

## Parameters

| Name     | Description                                              |
| -------- | -------------------------------------------------------- |
| `-Retry` | The step could not do its work yet: run it again after the restart. |

## Without and with -Retry

| Call                          | The step counts as | After the restart            | Screen                                  |
| ----------------------------- | ------------------ | ---------------------------- | --------------------------------------- |
| `Request-SetupRestart`        | done               | the run goes on with the next step | `↻ Install X  3m 12s  restart`    |
| `Request-SetupRestart -Retry` | waiting            | the same step runs again     | `↻ Install X  0.4s  restart, then again` |

A step that asks for a retry a second time in a row fails, so a restart that never clears the way cannot loop.  
With `-SkipRestart` on the run, a retry is skipped as `needs a restart first`, and the run goes on.  
Outside a run it does nothing.
