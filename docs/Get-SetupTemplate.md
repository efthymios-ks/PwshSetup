# Get-SetupTemplate

Lists the templates a step file can name with [`Use-SetupTemplate`](Use-SetupTemplate.md).

```powershell
Get-SetupTemplate
Get-SetupTemplate -Id '*Sql*'
Get-SetupTemplate -StepPath 'C:\Setup\steps'
```

## Synopsis

```powershell
Get-SetupTemplate [-Id <string[]>] [-StepPath <string>]
```

| Parameter   | Default | Description                                                         |
| ----------- | ------- | ------------------------------------------------------------------- |
| `-Id`       | `*`     | Template ids to return, wildcards allowed.                          |
| `-StepPath` | none    | A steps folder, to list your own templates beside it too.           |

## Output

One object per template:

| Property     | Example                                              |
| ------------ | ---------------------------------------------------- |
| `Id`         | `Install-DotnetSdk`, the name `Use-SetupTemplate` takes |
| `Name`       | `Install Git`, the step's own name when it is fixed  |
| `Parameters` | `Version`                                            |
| `Source`     | `Module`, or `Own` for one beside the steps folder   |
| `Path`       | the template file                                    |

Everything is read from the files' code, never by running them.

```powershell
Get-SetupTemplate | Format-Table -Property Id, Parameters, Source
```

To change a published template, copy its `Path` into your `templates` folder and edit it there.  
Yours wins by name.
