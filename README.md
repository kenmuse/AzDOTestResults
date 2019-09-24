# AzDOTestResults
This module downloads the test results (TRX files, code coverage, etc.) associated
with a build in Azure DevOps. Additionally, the dependencies of the TRX file can
will be restored using the directory structure specified in the TRX, optionally being
restored into a directory structure which is user-configurable. 

## Installation
WintellectPowerShell is in the [PowerShell Gallery](https://www.powershellgallery.com/packages/AzDOTestResults/).
To install, execute the following command:

	Install-Module -Name AzDOTestResults -Scope CurrentUser

This will configure the module and make the included cmdlets available. Full details are available
in the [related help file](src/about_AzDOTestResults.help.txt).

## Development
A set of Pester tests is included to make it easier to validate the behavior
of the functions within the module. To run these tests in PowerShell or PowerShell Core,
ensure Pester is installed (`Install-Module -Name Pester`) and execute the following steps in the root
of the project:

```PS
Import-Module Pester
Invoke-Pester tests
```
