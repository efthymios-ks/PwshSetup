# Templates

The templates published with the module.  
A step file names one with [`Use-SetupTemplate`](Use-SetupTemplate.md); the run folder's numbers set the order.  
Package ids are Chocolatey's, from community.chocolatey.org.

## Tools and apps

| Template                        | Installs                                    | Done when                                        | Restart |
| ------------------------------- | ------------------------------------------- | ------------------------------------------------ | ------- |
| `Install-Chocolatey`            | Chocolatey, with `exitOnRebootDetected` on  | `choco` resolves                                 |         |
| `Install-Git`                   | `git`                                       | `git` resolves                                   |         |
| `Install-GoogleChrome`          | `googlechrome`, checksums skipped           | Installed apps lists Google Chrome               |         |
| `Install-Firefox`               | `firefox`                                   | Installed apps lists Mozilla Firefox             |         |
| `Install-NotepadPlusPlus`       | `notepadplusplus`                           | Installed apps lists Notepad++                   |         |
| `Install-WinRar`                | `winrar`                                    | Installed apps lists WinRAR                      |         |
| `Install-Postman`               | `postman`, for the user running setup       | Installed apps lists Postman                     |         |
| `Install-MicrosoftTeams`        | `microsoft-teams-new-bootstrapper`          | the MSTeams app package is provisioned           |         |
| `Install-RemoteDesktopManager`  | `rdm`                                       | Installed apps lists Remote Desktop Manager      |         |
| `Install-VsCode`                | `vscode`                                    | `code` resolves                                  |         |

Every package step needs `choco`: put `Install-Chocolatey` first.

## .NET and Visual Studio

| Template                        | Parameters                                  | Installs                                                    | Done when                                        | Restart |
| ------------------------------- | ------------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------ | ------- |
| `Install-VisualStudio2026`      | `Workload`, default `NetWeb`, `ManagedDesktop` | `visualstudio2026community`, then `visualstudio2026-workload-<name>` each | vswhere finds 2026 Community with every workload | yes |
| `Install-NetFrameworkDevPack`   |                                             | `netfx-4.8.1-devpack`                                       | the 4.8.1 reference assemblies exist             | yes     |
| `Install-DotnetSdk`             | `Version`, default `10`                     | `dotnet-<version>.0-sdk`                                    | `dotnet --list-sdks` has that major version      |         |
| `Install-Nvm`                   |                                             | `nvm`                                                       | `nvm` resolves                                   |         |

```powershell
Use-SetupTemplate -Name 'Install-DotnetSdk' -Parameter @{ Version = 8 }
Use-SetupTemplate -Name 'Install-VisualStudio2026' -Parameter @{ Workload = 'NetWeb', 'ManagedDesktop', 'Azure' }
```

## Containers and Kubernetes

| Template                  | Installs                                          | Done when                                            | Restart |
| ------------------------- | ------------------------------------------------- | ---------------------------------------------------- | ------- |
| `Enable-Wsl`              | WSL and the Virtual Machine Platform, no distro   | both Windows features are on                         | yes     |
| `Install-DockerDesktop`   | `docker-desktop`                                  | Installed apps lists Docker Desktop                  | yes     |
| `Install-PodmanCli`       | `podman-cli`                                      | `podman` resolves                                    |         |
| `Install-PodmanDesktop`   | `podman-desktop`                                  | Installed apps lists Podman Desktop                  |         |
| `Install-K9s`             | `k9s`                                             | `k9s` resolves                                       |         |
| `Install-Lens`            | `lens`, for every user                            | Installed apps lists Lens                            |         |

Docker Desktop runs on WSL: put `Enable-Wsl` before it.

## SQL Server

| Template                             | Installs                                       | Done when                                          | Restart |
| ------------------------------------ | ---------------------------------------------- | -------------------------------------------------- | ------- |
| `Install-SqlServer2022`              | `sql-server-2022`, Developer, default instance | the MSSQLSERVER service exists                     | yes     |
| `Install-SqlServerManagementStudio`  | `sql-server-management-studio`, the latest     | Installed apps lists SQL Server Management Studio  |         |
| `Install-Sqlcmd`                     | `sqlcmd`, the Go one                           | `sqlcmd` resolves                                  |         |
| `Install-SqlPackage`                 | `sqlpackage`                                   | `sqlpackage` resolves                              |         |

SQL Server makes the user running setup its administrator.  
For the `sa` sign-in too, set a `SETUP_SQL_SA_PASSWORD` user variable before the run.  
It never goes in a step file, which is committed.

## Files and settings

These throw without their values.

| Template            | Parameters                          | Does                                     | Done when                  |
| ------------------- | ----------------------------------- | ---------------------------------------- | -------------------------- |
| `Edit-HostsFile`    | `Entries`                           | adds the lines to the hosts file         | every line is there        |
| `Copy-Repository`   | `RepositoryUrl`, `DestinationPath`  | clones the repository                    | the folder has a `.git`    |
| `Expand-Archive`    | `ArchivePath`, `DestinationPath`    | unpacks the archive                      | the folder exists          |
| `New-SqlDatabase`   | `ConnectionString`                  | creates the database it names            | the database exists        |

```powershell
Use-SetupTemplate -Name 'Edit-HostsFile' -Parameter @{ Entries = '127.0.0.1 shop.local', '127.0.0.1 api.shop.local' }
Use-SetupTemplate -Name 'Copy-Repository' -Parameter @{ RepositoryUrl = 'https://github.com/efthymios-ks/PwshSetup.git'; DestinationPath = 'C:\Repos\PwshSetup' }
```

## What changed from the first templates

| Was                                          | Now                                              | Why                                                          |
| -------------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------ |
| numbered files copied into `steps`           | unnumbered, named with `Use-SetupTemplate`       | the run folder owns the order; module updates flow in        |
| values edited at the top of a copy           | `-Parameter`                                     | no copy to keep in step with the module                      |
| `microsoft-teams`                            | `microsoft-teams-new-bootstrapper`               | the old package is classic Teams                             |
| Visual Studio 2022, workloads in one call    | Visual Studio 2026, one package per workload     | 2026 is current, and its package installs workloads that way |
| .NET SDK 8 and 9, a template each            | `Install-DotnetSdk -Parameter @{ Version = n }`  | one template for every version; 10 is the current LTS        |
| SSMS checked by its 19 folder                | checked in Installed apps                        | the package installs 22, in another folder                   |
| SQL Server `/SAPWD=` and SA required         | `/SAPWD:` only when the variable is set          | the package reads `/NAME:value`; Windows sign-in needs none  |
| app checks by install folder                 | `Test-SetupProgram`                              | folders move between versions and per-user installs          |
| no WSL step                                  | `Enable-Wsl` before Docker                       | Docker Desktop runs on it                                    |
| `Invoke-SqlScript`, always ran               | `New-SqlDatabase`, done once the database exists | a step should know when it is done                           |
