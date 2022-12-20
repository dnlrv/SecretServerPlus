# SecretServerPlus
The intent is to add ease of use with certain queries when working directly with a Delinea Secret Server Instance once you are authenticated. This script provides new functions and classes to work with data within Secret Server.

## Installation

To install the script to your current working directory via the command line, run the following:
```
(Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/DelineaPS/SecretServerPlus/main/SecretServerPlus.ps1').Content | Out-File .\SecretServerPlus.ps1
```

## Running the script

If scripts are not allowed to be run in your environment, an alternative method is the run the following once the script is downloaded:

```
([ScriptBlock]::Create((Get-Content .\SecretServerPlus.ps1 -Raw))).Invoke()
```

Alternatively, for a completely scriptless run, where the script's contents is retrieved from the internet, and immediately executed as a ScriptBlock object (basically combining the previous cmdlets):
```
([ScriptBlock]::Create(((Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/DelineaPS/SecretServerPlus/main/SecretServerPlus.ps1').Content))).Invoke()
```

## Requirements

This script has only one requirement:
 - Authenticated to your PAS tenant via the Connect-SecretServerInstance cmdlet.

All results are based on your existing instance permissions. If you are not getting expected results, ensure that your instance permissions are accurate.

This script does not require privilege elevation to run.

## Major functions

- Invoke-SecretServerAPI - Allows a direct call to a named RestAPI endpoint with a JSON body payload. Allows for different Method calls as well.
