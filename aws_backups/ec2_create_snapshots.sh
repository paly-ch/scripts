#!/bin/bash

# AWS EBS Snapshot creation script - `ec2_create_snapshots.sh`
# ============================================================
#
# Author: Pavel Lechenko
# License: APLv2 [http://www.apache.org/licenses/LICENSE-2.0.html]
#
# This script initiates snapshot creation for all EBS volumes on instance
# and removes old (8+ days older) snapshots.
#
# Installation
# ------------
#
# Just copy this script into the desired directory and set the exec permission
#
#	# chmod a+x ec2_dumped_backup.sh
#
# Next, you should install the EC2 CLI Tools [http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/SettingUp_CommandLine.html]
#
# Configuration
# -------------
#
# To configure the script you should create/edit the `/etc/aws-security` file 
# with following content:
#
#    AWS_ACCESS_KEY=your-aws-access-key-id
#    AWS_SECRET_KEY=your-aws-secret-key
#   
# Usage
# -----
#
# This script is designed to work under `crontab` as well as from console/terminal.
# To run it from console just do:
#
#   # ./ec2_create_snapshots.sh
#
# To configure the scheduler you should add into your crontab file a string like:
#
#	30 03 * * * /bin/sh /vol/ec2_create_snapshots.sh >> /var/log/create_snapshots.log 2>&1
#
# This string says that the script will run every day at 03:30.
# The log with all messages and errors will be located at `/var/log/create_snapshots.log`

echo "`date` [$$] Started Snapshotting"

# Constants
ec2_bin="/usr/bin"
. /etc/aws-security
export AWS_ACCESS_KEY
export AWS_SECRET_KEY

instance_id=`wget -q -O- http://169.254.169.254/latest/meta-data/instance-id`

pid=$$
snapshot=snap_$pid

# Dates
datecheck_7d=`date --date '7 days ago' +%s`

echo "`date` [$$] Get the region"
EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
EC2_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed -e 's:\([0-9][0-9]*\)[a-z]*\$:\\1:'`"

echo "`date` [$$] Get all volume info and copy to temp file"
$ec2_bin/ec2-describe-volumes --region $EC2_REGION --filter "attachment.instance-id=$instance_id" > /tmp/volume_info_${pid}.txt 2>&1

echo "`date` [$$] Get all snapshot info"
$ec2_bin/ec2-describe-snapshots --region $EC2_REGION | grep "$instance_id" | /usr/bin/awk '{printf "%s$%s$%s\n", $2,$3,$5;}' > /tmp/snap_info_${pid}.txt 2>&1

# Loop to remove any snapshots older than 7 days
echo "`date` [$$] Load text file lines into a bash array"
lines_array=`cat /tmp/snap_info_${pid}.txt`

for snap in ${lines_array}
do
echo "snap: $snap"

        snapshot_name=`echo $snap | awk -F$ '{print $1}'`
        datecheck_old=`echo $snap | awk -F$ '{print $3}' | awk -F "T" '{printf "%s", $1}'`
        datecheck_s_old=`date --date="$datecheck_old" +%s`

        if [ $datecheck_s_old -le $datecheck_7d ];
        then
                echo "`date` [$$] deleting snapshot $snapshot_name ..."
                $ec2_bin/ec2-delete-snapshot --region $EC2_REGION $snapshot_name
        else
                echo "`date` [$$] not deleting snapshot $snapshot_name ..."

        fi
done

echo "`date` [$$] Create snapshot"
for volume in `cat /tmp/volume_info_${pid}.txt | grep "VOLUME" | awk '{print $2}'`
do
        description="`hostname`_backup-`date +%Y-%m-%d`_[$instance_id]"
        echo "`date` [$$] Creating Snapshot for the volume: $volume with description: $description"
        $ec2_bin/ec2-create-snapshot --region $EC2_REGION -d $description $volume
done

rm /tmp/*_${pid}.txt

echo "`date` [$$] Finished Snapshotting"
