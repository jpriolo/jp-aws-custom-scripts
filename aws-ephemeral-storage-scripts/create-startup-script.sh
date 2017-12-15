#!/bin/bash

#######  To use as startup script  ########
### 1. Copy scipt to directory: /opt/aws/

SCRIPT=/tmp/ephemeral-disks-raid.sh
mkdir -p /opt/aws/
cp $SCRIPT /opt/aws/myscript.sh
chmod 755 /opt/aws/myscript.sh
# 
### 2: Add script path to 'rc.local' to execute at startup:
echo "# Detect and initialize ephemeral disks" | tee -a /etc/rc.d/rc.local
echo "/opt/aws/myscript.sh" | tee -a /etc/rc.d/rc.local

