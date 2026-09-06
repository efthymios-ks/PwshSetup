# PwshSetup

A machine setup that runs as ordered steps: each one says whether it still has work to do, does it,
and can ask for a reboot the run comes back from.

```
Invoke-Setup.ps1        entry point — elevates, transcribes, runs the steps
Invoke-Test.ps1         Pester 5 runner
src/                    the runner
├── Setup.Core.psm1     Write-SetupLog, New-SetupStep, Get-SetupStep, Test-SetupCommand
├── Invoke-SetupPipeline.psm1
└── Restart-SetupHost.psm1
steps/                  your pipeline — the steps that actually run
templates/              the catalog to copy from
└── modules/            step support: Invoke-ChocoPackage, Invoke-SetupSql
tests/                  Pester tests, driven by the dummy steps in tests/fixtures
```

## Running it

```powershell
./Invoke-Setup.ps1                       # runs everything under ./steps
./Invoke-Setup.ps1 -SkipRestart -WhatIf  # says what it would do, reboots nothing
```

Copy what you want out of `templates/` into `steps/`, renumber the file names to set the order, and
edit the values at the top of the ones that need them. The run is transcribed to `logs/`.

Not elevated, it relaunches itself as administrator. A step that asks for a restart gets one: the
pipeline registers itself with RunOnce first, so the machine comes back and carries on.

## Writing a step

A step file returns one step object. The name is what the log shows, the order decides when it runs,
`Test` decides whether it runs at all, and `Action` is the work.

```powershell
#Requires -Version 7.2

Import-Module (Join-Path $PSScriptRoot '..\src\Setup.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'modules\Invoke-ChocoPackage.psm1') -Force -DisableNameChecking

New-SetupStep -Name 'Install k9s' -Order 19 `
    -Test {
        -not (Test-SetupCommand 'k9s')
    } `
    -Action {
        Install-ChocoPackage -Name 'k9s'

        Sync-ChocoEnvironment
    }
```

| Part | Does |
| --- | --- |
| `-Name` | what the log calls it |
| `-Order` | run order; taken from the leading number in the file name when not given |
| `-Test` | `$true` when there is work to do, `$false` to skip. Omit it and the step always runs |
| `-Action` | the work. Throwing stops the run on this step |
| `-RequiresRestart` | reboot once the action is done, then carry on from the next step |

A step is skipped, completed or failed, and each outcome comes back as a `Setup.StepResult`.

## Testing

```powershell
./Invoke-Test.ps1
```

The tests cover the runner and the core helpers, and drive the pipeline with the dummy steps in
`tests/fixtures` — they read and write nothing on the machine.

## License

MIT.
