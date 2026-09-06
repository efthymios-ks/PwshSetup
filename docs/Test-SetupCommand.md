# Test-SetupCommand and Test-SetupProgram

The two checks most step Tests need.

```powershell
Test-SetupCommand -Name 'git'
Test-SetupProgram -Name 'Google Chrome'
```

## Synopsis

```powershell
Test-SetupCommand -Name <string>
Test-SetupProgram -Name <string>
```

## Test-SetupCommand

`$true` when a command resolves in this session, through `Get-Command`.  
For tools used from the command line: `git`, `dotnet`, `choco`, `code`.  
Install steps reload PATH after they install, so a command installed by one step resolves in the next.

## Test-SetupProgram

`$true` when Windows lists a program under Installed apps, by display name.  
It reads the uninstall entries Settings shows: machine-wide, 32-bit, and the current user's.  
Wildcards are allowed, so one check covers editions and languages:

| Check                                    | Matches                                     |
| ---------------------------------------- | ------------------------------------------- |
| `'Google Chrome'`                        | Google Chrome                               |
| `'Mozilla Firefox*'`                     | Mozilla Firefox (x64 en-US)                 |
| `'*SQL Server Management Studio*'`       | SQL Server Management Studio 22             |

For apps with no command, or whose folder moves between versions.

## Which to use

| The step installs                | Test with                                   |
| -------------------------------- | ------------------------------------------- |
| a command line tool              | `Test-SetupCommand`                         |
| a desktop app                    | `Test-SetupProgram`                         |
| a Windows feature                | `Get-WindowsOptionalFeature`                |
| an app package, such as Teams    | `Get-AppxProvisionedPackage`                |
| a file or a folder               | `Test-Path`                                 |
