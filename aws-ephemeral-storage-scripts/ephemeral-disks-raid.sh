#!/bin/bash
set -x

#
# Initials script credit: https://gist.github.com/joemiller/6049831
# Modified to start at reboot and use LVM: Joseph Priolo    12.06.2017
# Rev. 2.0 -- ADDED: Error checking, additional startup script code.
#
# this script will attempt to detect any ephemeral drives on an EC2 node and create a RAID-0 stripe
# mounted at /mnt. It should be run early on the first boot of the system.
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
# EC2 reboot: raid volume and data will be persistent on "/dev/md0"
# EC2 shutdown: all ephemeral storage is wiped. This script will initialize all instance stores and mount raid disk on boot.
#

# declare variables for mount point and Raid device
MP="/saswork"
RAID_PATH="/dev/md0"

# checksum to verify script is executing at reboot
DATE=$(date +'%F %H:%M:%S')
DIR=/tmp
  echo "Current date and time: $DATE" > $DIR/ephem_bootscript_lastrun.txt

# check if Raid 0 disk is mounted | IF mounted then exit - if not continue
if grep "${RAID_PATH}" /etc/mtab > /dev/null 2>&1; then
  echo "'${RAID_PATH}' is mounted...exiting" && exit
else
  echo "'${RAID_PATH}' not mounted"
  echo "Continuing..."
fi


### --- BEGIN CODE --- ###

### Detect ehpemeral disks - Start ###


# set metadata base URL
METADATA_URL_BASE="http://169.254.169.254/2012-01-12"

# install raid utility
yum -y -d0 install mdadm curl

# Configure Raid - take into account xvdb or sdb
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

# ephemeral0 is typically mounted for us already. umount it here
umount /mnt

# create mp and mount drive
mkdir -p $MP

# overwrite first few blocks in case there is a filesystem, otherwise mdadm will prompt for input
for drive in $drives; do
  dd if=/dev/zero of=$drive bs=4096 count=1024
done

partprobe
mdadm --create --verbose /dev/md0 --level=0 -c256 --raid-devices=$ephemeral_count $drives
echo DEVICE $drives | tee /etc/mdadm.conf
mdadm --detail --scan | tee -a /etc/mdadm.conf
blockdev --setra 65536 /dev/md0
mkfs -t ext3 /dev/md0
mount -t ext3 -o noatime /dev/md0 /saswork

# Remove xvdb/sdb from fstab
#chmod 777 /etc/fstab
#sed -i "/${DRIVE_SCHEME}b/d" /etc/fstab


# Make raid volume mount on reboot (Prevent writing entry to /etc/fstab multiple times)
MOUNT_PATH="${RAID_PATH} ${MP} ext3 noatime 0 0"
FILE="/etc/fstab"
grep -qF "$MOUNT_PATH" "$FILE" || echo "$MOUNT_PATH" >> "$FILE"


echo "Looks like we're done US Foods!"

exit 0

