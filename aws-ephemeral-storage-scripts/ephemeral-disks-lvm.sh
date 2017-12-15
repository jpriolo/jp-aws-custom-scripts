#!/bin/bash
set -x
#
# Initials script credit: https://gist.github.com/joemiller/6049831
# Modified to start at reboot and use LVM: Joseph Priolo    12.06.2017
# Rev 2.1 -- ADDED: Error checking, additional startup script code.
#
#
      #######  To use as startup script  ########
      ### 1. Copy scipt to directory: /opt/aws/
      # mkdir -p /opt/aws/
      # cp 'myscript.sh' /opt/aws/
      # chmod 755 /opt/aws/myscript.sh
      # 
      ### 2: Add script path to 'rc.local' to execute at startup:
      # echo "/opt/aws/myscript.sh" | tee -a /etc/rc.d/rc.local
#
### Intended use: 
# This script will attempt to detect any ephemeral drives on an EC2 node and create a single LVM volume
# EC2 reboot: LVM volume and data will be persistent on "/dev/md0"
# EC2 shutdown: all ephemeral storage is wiped. This script will initialize all instance stores and mount LVM disk on boot.


# declare variables for mount point and LVM
MP="/saswork"
VG="vg0"
LV="lv_ephem0"
LVM_PATH="/dev/mapper/$VG-$LV"

# checksum to verify script is executing at reboot
DATE=$(date +'%F %H:%M:%S')
DIR=/tmp
  echo "Current date and time: $DATE" > $DIR/ephem_bootscript_lastrun.txt

# check if LVM volume is mounted | IF mounted then exit - if not continue
if grep "${LVM_PATH}" /etc/mtab > /dev/null 2>&1; then
  echo "'${LVM_PATH}' is mounted...exiting" && exit
else
  echo "'${LVM_PATH}' not mounted"
  echo "Continuing..."
fi


### --- BEGIN CODE --- ###

### Detect ehpemeral disks - Start ###

# set metadata base URL
METADATA_URL_BASE="http://169.254.169.254/2012-01-12"

# drive scheme -  take into account xvdb or sdb
root_drive=`df -h | grep -v grep | awk 'NR==2{print $1}'`

if [ "$root_drive" == "/dev/xvda1" ]; then
  echo "Detected 'xvd' drive naming scheme (root: $root_drive)"
  DRIVE_SCHEME='xvd'
else
  echo "Detected 'sd' drive naming scheme (root: $root_drive)"
  DRIVE_SCHEME='sd'
fi


# figure out how many ephemerals we have by querying the metadata API, and then:
#  - convert the drive name returned from the API to the hosts DRIVE_SCHEME, if necessary
#  - verify a matching device is available in /dev/
drives=""
ephemeral_count=0
ephemerals=$(curl --silent $METADATA_URL_BASE/meta-data/block-device-mapping/ | grep ephemeral)
for e in $ephemerals; do
  echo "Probing $e .."
  device_name=$(curl --silent $METADATA_URL_BASE/meta-data/block-device-mapping/$e)
  # might have to convert 'sdb' -> 'xvdb'
  device_name=$(echo $device_name | sed "s/sd/$DRIVE_SCHEME/")
  device_path="/dev/$device_name"

    # test that the device actually exists since you can request more ephemeral drives than are available
  # for an instance type and the meta-data API will happily tell you it exists when it really does not.
  if [ -b $device_path ]; then
    echo "Detected ephemeral disk: $device_path"
    drives="$drives $device_path"
    ephemeral_count=$((ephemeral_count + 1 ))
  else
    echo "Ephemeral disk $e, $device_path is not present. skipping"
  fi
done

if [ "$ephemeral_count" = 0 ]; then
  echo "No ephemeral disk detected. exiting"
  exit 0
fi

### Detect ephemeral disks - END ###

### Initialize disks & create lvm volume group - Start ###

# create lvm partitions & physical volumes
for d in ${drives}; do
    echo ',,8e;' | sfdisk ${d}
    pvcreate "${d}"1
done

# create partition array
PART=$(for v in ${drives}; do	
       	 printf "${v}1 "
      done)

	# create volume group
		vgcreate $VG $PART

			# create logical volume
				lvcreate -l 100%FREE -n $LV $VG
					mkfs.ext4 /dev/$VG/$LV -E lazy_itable_init


		# create mp and mount drive
		mkdir -p $MP

	mount /dev/$VG/$LV $MP

# confirm drives are ready (LVM2)
file -s /dev/xvd*
lvdisplay -v
df -h

# Make LVM volume mount on reboot (Prevent writing entry to /etc/fstab multiple times)
MOUNT_PATH="${LVM_PATH} ${MP} ext4 noatime 0 0"
FILE="/etc/fstab"
grep -qF "$MOUNT_PATH" "$FILE" || echo "$MOUNT_PATH" >> "$FILE"

exit 0