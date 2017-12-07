#!/bin/bash

# Script to install custon Cloudwatch metrics into multiple MBR/GPT volumes | RHEL 6.x
# Joseph Priolo
# 11.19.17

# create log file
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>log.out 2>&1
# Everything below will go to the file 'log.out':

# remove CPAN config
#rm -rf /usr/share/perl5/CPAN/Config.pm


# required perl packages
sudo yum install perl-DateTime perl-CPAN perl-Net-SSLeay perl-IO-Socket-SSL perl-Digest-SHA gcc -y

 # install zip and unzip 
sudo yum install zip unzip -y

# install AWS CloudWatch Scripts
pushd /opt
curl -s http://aws-cloudwatch.s3.amazonaws.com/downloads/CloudWatchMonitoringScripts-1.2.1.zip -O

unzip -o CloudWatchMonitoringScripts-1.2.1.zip
rm -rf CloudWatchMonitoringScripts-1.2.1.zip
popd


# bypass default CPAN prompts
export PERL_MM_USE_DEFAULT=1

# install cpan modules:
cpan YAML
cpan LWP::Protocol::https
cpan Sys::Syslog
cpan Switch



# GET MOUNT POINTS & create cron job ************
for disk in $(grep xvd /etc/fstab | awk '{print $2}'); do z+='--disk-path='$disk' '; done
echo "*/5 * * * * /opt/aws-scripts-mon/mon-put-instance-data.pl --mem-util --disk-space-util --disk-path=/ $z --from-cron" > /tmp/awscron
crontab /tmp/awscron
rm /tmp/awscron


# verify cw scripts are functioning
/opt/aws-scripts-mon/mon-put-instance-data.pl --mem-util --verify --verbose