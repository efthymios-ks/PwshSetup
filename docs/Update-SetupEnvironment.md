# Update-SetupEnvironment

Reloads the machine and user environment variables into this session.

```powershell
Update-SetupEnvironment
```

## Synopsis

```powershell
Update-SetupEnvironment
```

## What it does

Installers write PATH and other variables to the registry, which a running session never reads again.  
This copies them in, machine first and user second, and joins both PATHs without duplicates.  
So a command installed by one step resolves in the next, with no new window.

`PSModulePath` and `USERNAME` are left alone: pwsh builds the first itself, and the second belongs to the process.

## When to call it

[`Install-ChocoPackage`](Install-ChocoPackage.md) calls it after every install.  
Call it yourself after an installer you start directly:

```powershell
Start-Process -FilePath $installer -ArgumentList '/quiet' -Wait
Update-SetupEnvironment
```
