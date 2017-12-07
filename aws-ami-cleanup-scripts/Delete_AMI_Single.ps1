### Script to delete inactive AWS AMI's
#
### Joseph Priolo | US FOODS
#
### 10.31.17

### USAGE: Delete a single AWS AMI by defining the variable '$aminame' below

### DRY-RUN OPTION! --- This script will not actually delete anything until you remove " -WhatIf " from all locations!


# --- BEGIN CODE ---


## Runas admin prompt:
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{   
#"No Administrative rights, it will display a popup window asking user for Admin rights"

$arguments = "& '" + $myinvocation.mycommand.definition + "'"
Start-Process "$psHome\powershell.exe" -Verb runAs -ArgumentList $arguments

break
}


# Set execution policy and load AWS PS module
Set-ExecutionPolicy Unrestricted -Force
Import-Module AWSPowerShell

# Declare variables
$region = 'us-west-2'
$amiName = ‘ami-884ceee8’    #ami-e4fe299c

# Grab AMI & snapshot attributes and remove
$myImage = Get-EC2Image $amiName -Region $region
$count = $myImage[0].BlockDeviceMapping.Count
$mySnaps = @()
for ($i=0; $i -lt $count; $i++)
{
$snapId = $myImage[0].BlockDeviceMapping[$i].Ebs | foreach {$_.SnapshotId}
$mySnaps += $snapId
}
Write-Host “Unregistering” $amiName
Unregister-EC2Image $amiName -Region $region -Force  -WhatIf
foreach ($item in $mySnaps)
{
Write-Host ‘Removing’ $item
Remove-EC2Snapshot $item -Region $region -Force  -WhatIf
}


Read-Host -Prompt "--->>> COMPLETE! ...Press Enter to exit' <<<---"