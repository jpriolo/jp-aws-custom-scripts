### Script to delete inactive AWS AMI's
#
### Joseph Priolo | US FOODS
#
### 10.31.17

### USAGE: This script will 'deregister' AWS AMIs and their associated snapshots

### Please define the variable '$server_type' below to target the AMIS you wish to evaluate, report and delete

### DRY-RUN OPTION! --- This script will not actually delete anything until you remove " -WhatIf " from all locations!

### Reports:
### c:\AWS_AMIS_DELETED.csv


# --- BEGIN CODE ---


## Runas admin prompt:
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{   
#"No Administrative rights, it will display a popup window asking user for Admin rights"

$arguments = "& '" + $myinvocation.mycommand.definition + "'"
Start-Process "$psHome\powershell.exe" -Verb runAs -ArgumentList $arguments

break
}

#-------------------

##Create Log:
$Logfile = "C:\AWS_AMIS_DELETED.csv"
    $LogTime = Get-Date -Format "MM-dd-yyyy_hh-mm-ss"
        Set-Content $Logfile -Value $LogTime

Function LogWrite
{
   Param ([string]$logstring)

   add-content $Logfile -value $logstring
}

#-------------------

# Set execution policy and load AWS PS module
Set-ExecutionPolicy Unrestricted -Force
Import-Module AWSPowerShell



# Declare variables
$region = 'us-west-2'
$owner = 'self'
$server_type = '*linux*'

# Create array of AMI's in us-west-2 with the server type:
$AllAMINames = Get-EC2Image -Region $region -Owner $owner -Filter @{ Name='name'; Values=$server_type}   

echo "Deleting your AMI's and snapshots! Please be patient while we work on that for you..."

foreach ($aminame in $AllAMINames.imageid)

{

# Grab AMI & snapshot attributes and remove | write to log.csv
$myImage = Get-EC2Image $aminame -Region $region
$count = $myImage[0].BlockDeviceMapping.Count
$mySnaps = @()

for ($i=0; $i -lt $count; $i++)
  {
        $snapId = $myImage[0].BlockDeviceMapping[$i].Ebs | foreach {$_.SnapshotId}
        $mySnaps += $snapId
    }

        LogWrite (“Unregistering $amiName,$($myimage.name)")
        Unregister-EC2Image $amiName -Region $region -Force -WhatIf

foreach ($item in $mySnaps)

  {
        LogWrite ("Removing $item")
        Remove-EC2Snapshot $item -Region $region -Force -WhatIf
    }

 }


Write-Host "--->>> COMPLETE! Log file written to 'C:\AWS_AMIs_Deleted.csv ...Press Enter to exit' <<<---"
