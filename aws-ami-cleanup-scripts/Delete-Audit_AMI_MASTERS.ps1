### Script to delete only AMI masters 'not in use'
### Joseph Priolo
### Created: 11.14.17
### Rev 1.2 |  11.17.17

### USAGE: This script will 'deregister' AWS AMIs and their associated snapshots

### Please define the variables '$server_type'& '$branch' below to target the AMIS you wish to evaluate, report and delete

### DRY-RUN OPTION! --- This script will not actually delete anything until you remove " -WhatIf " from all locations!

### Reports:
### c:\aws-master-ami--audit.csv
### c:\AWS_MASTER_AMIS__DELETED.csv


# --- BEGIN CODE ---


# Set execution policy and load AWS PS module
Set-ExecutionPolicy Unrestricted -Force
Import-Module AWSPowerShell


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
$Logfile = "c:\AWS_MASTER_AMIS__DELETED.csv"
    $LogTime = Get-Date -Format "MM-dd-yyyy_hh-mm-ss"
        Set-Content $Logfile -Value $LogTime

Function LogWrite
{
   Param ([string]$logstring)

   Add-content $Logfile -value $logstring
}

#-------------------


echo "CREATING VARIABLES - PLEASE BE PATIENT..."

# Declare variables
$region = 'us-west-2'
$owner = 'self'
$server_type = '*master-v*'   # <--- modify
$branch = 'master'            # <--- modify

# Create array of ALL AMI's in us-west-2 with the server type (master):
$AllAMINames = Get-EC2Image -Region $region -Owner $owner -Filter @{ Name='name'; Values=$server_type}


#--------------------
#  CODE TO EXCLUDE THE LATEST REVISION OF ANY MASTER

# Find latest version of all masters

    # Get latest version of amazon-linux master
    $amzn_lnx = $AllAMINames | where {$_.name -like "*amazon-linux-$branch-v*"}
    $amzn_lnx_latest = $amzn_lnx | select name,creationdate,imageid | sort creationdate | select -Last 1

        # Get latest version of redhat-linux master
        $rhel = $AllAMINames | where {$_.name -like "*redhat-linux-$branch-v*"}
        $rhel_latest = $rhel | select name,creationdate,imageid | sort creationdate | select -Last 1

            # Get latest version of redhat-linux master v6x
            $rhel_v6x = $AllAMINames | where {$_.name -like "*redhat-linux-v6x-$branch-v*"}
            $rhel_v6x_latest = $rhel_v6x | select name,creationdate,imageid | sort creationdate | select -Last 1

                # Get latest version of windows master
                $win = $AllAMINames | where {$_.name -like "*windows-$branch-v*"}
                $win_latest = $win | select name,creationdate,imageid | sort creationdate | select -Last 1


# All masters - latest version:
Write-Output "--- Latest versions of all '$branch' AMIs:"

    $amzn_lnx_latest.name
    $rhel_latest.name
    $rhel_v6x_latest.name
    $win_latest.name

# Create array of latest master amis
$latest_master_amis = @(

    $amzn_lnx_latest.imageid
    $rhel_latest.imageid
    $rhel_v6x_latest.imageid
    $win_latest.imageid
)

#---------------END 'Latest Masters' CODE ---------------


# Collect AMI image ID's that have an instance associated with it
$EC2instances = Get-EC2Instance -region $region
$amis_w_instances = $EC2instances.instances.imageid

# remove duplicates
$amis_w_instances = $amis_w_instances | select -Unique

# Check if AMI is associated w an EC2 instance OR is latest master ami & write to file
$output =
                     foreach ($id in $AllAMINames)

                { IF (($id.ImageId -notin $amis_w_instances ) -and ($id.Imageid -notin $latest_master_amis))

            { Write-Output ("NOT IN-USE: $($id.Name),$($id.Imageid)") }

    else { Write-Output  ("IN-USE: $($id.Name),$($id.Imageid)") }

 }

 # Write Report to CSV
 $output | Sort-Object -Descending | Out-File c:\aws-master-ami--audit.csv

 $output | Sort-Object -Descending


#   --------------------------------------------------------------
### - CODE TO DELETE AMIS NOT ASSOCIATED W AN EC2 INSTANCE OR IS THE LATEST REVISION OF ANY MASTER

### echo "Deleting your AMI's and snapshots! Please be patient while we work on that for you..."


# Create an array of all AMIs that are "NOT USED"

$notused =

        foreach ($a in $AllAMINames)
   {
        IF (($a.ImageId -notin $amis_w_instances ) -and ($a.Imageid -notin $latest_master_amis))

        { Write-Output $($a) }
    }


# DELETE AMIs that are "NOT USED" -----------------

        foreach ($aminame in $notused.imageid )
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
        Unregister-EC2Image $amiName -Region $region -Force    -WhatIf

foreach ($item in $mySnaps)

  {
        LogWrite ("Removing $item")
        Remove-EC2Snapshot $item -Region $region -Force    -WhatIf
    }

 }


Write-Host  "--->>> COMPLETE! Log file written to 'C:\AWS_AMIS__DELETED.csv ...Press Enter to exit' <<<---"
