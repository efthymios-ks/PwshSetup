# Write-SetupLog

Writes a line to the run log, and shows it dimmed under the running step.

```powershell
Write-SetupLog -Message 'Hosts file updated.'
Write-SetupLog -Message 'Nothing to copy.' -Level Warning
```

## Synopsis

```powershell
Write-SetupLog [-Message] <string> [-Level <Info|Warning|Error>]
```

## Parameters

| Name       | Default | Description                                   |
| ---------- | ------- | --------------------------------------------- |
| `-Message` | required | The line. Accepts pipeline input.            |
| `-Level`   | `Info`  | `Warning` shows yellow, `Error` red.          |

## Where it goes

| Called from          | Screen                         | Log file |
| -------------------- | ------------------------------ | -------- |
| a running step       | under the step, dimmed         | yes      |
| anywhere else        | a line of its own              | no       |

```
→ Install Visual Studio 2026 Community
  choco install visualstudio2026community --yes --no-progress
  visualstudio2026community installed, and asks for a restart.
████████████░░░░░░░░░░░░░░░░░░  40%
```

The text is printed as typed: brackets are not read as PwshAnsi markup.

## Log lines

Each line carries the time, the level and the step:

```
2026-10-13 09:52:40  INFO    110-Install-VisualStudio2026  visualstudio2026community installed, and asks for a restart.
```
