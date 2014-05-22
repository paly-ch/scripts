#!/bin/bash

# MySQL db backup script for AWS - `ec2_dumped_backup.sh`
# =======================================================
#
# Author: Pavel Lechenko
# License: APLv2 [http://www.apache.org/licenses/LICENSE-2.0.html]
#
# This script dumps all or selected databases from local MySQL server, 
# copies selected files and dirs, compresses and uploads them to S3 
# or local directory.
# It makes full DB backup (in case if this is the 1st backup for today) 
# and then incremental backups.
# It also removes old files (8+ days older) to reduce disk/S3 usage.
#
# Installation
# ------------
#
# Just copy this script into the desired directory and set the exec permission
#
#	# chmod a+x ec2_dumped_backup.sh
#
# In case if you want to use local directory to store your backups 
# you do not need anything else to install.
#
# If you want to upload your backups to S3 bucket you must install
# s3cmd [http://s3tools.org/s3cmd] :
#
#	# sudo apt-get install s3cmd
#
# Then apply this patch [https://github.com/s3tools/s3cmd/commit/9c57a3ba2163915deb2cc63cefa885a66ac377ab]
#
# And finally configure the s3cmd
#
#	# s3cmd --configure 
#
# During configuration you should indicate that config file is located 
# at `/etc/s3cmd`. This is very important.
#
# Configuration
# -------------
#
# To configure the script you should create file `/etc/dump_backup` with following sample contents:
#
#    BACKUPS_DIR=/mnt/backups	# Directory for backups
#								# # This directory is used to store backups if S3_BUCKET is no configured
#    MYSQL_ROOT_PWD=secret		# MySQL root password
#    S3_BUCKET=s3://lgc-backups	# S3 bucket name where backups should be uploaded.
#                               # # If empty of not set then S3 is not used and all backups left in BACKUPS_DIR
#    COPY_DIRS="/vol/files /var/www /etc/hostname"	# List of files and directories to be backed up
#    
# Usage
# -----
#
# This script is designed to work under `crontab` as well as from console/terminal.
# To run it from console just do:
#
#   # ./ec2_dumped_backup.sh
#
# To configure the scheduler you should add into your crontab file a string like:
#
#	05 * * * * /bin/sh /path_to_script/ec2_dumped_backup.sh >> /var/log/dump_backup.log 2>&1
#
# This string says that the script will run at 5 minutes of each hour.
# The log with all messages and errors will be located at `/var/log/dump_backup.log`

echo "`date` [$$] Started dumped backup"

# Constants
. /etc/dump_backup
instance_id=`/usr/bin/wget -q -O- http://169.254.169.254/latest/meta-data/instance-id`

pid=$$

ts=`date +'%s'`

snapshot=snap_$pid
filename=backup_${instance_id}_`date +%Y-%m-%d_%H%M%S`

if [ "${BACKUPS_DIR}" = "" ];
then
    BACKUPS_DIR=/tmp/dump_backups
fi

LAST_TS=0
if [ -f ${BACKUPS_DIR}/dump_backup.cfg ];
then
    . ${BACKUPS_DIR}/dump_backup.cfg
fi

echo "`date` [$$] Creating backup dir ${BACKUPS_DIR}/$snapshot"
mkdir -p ${BACKUPS_DIR}/$snapshot
cd ${BACKUPS_DIR}/$snapshot

if [ "${MYSQL_ROOT_PWD}" != "" ];
then
    creds="-u root --password=${MYSQL_ROOT_PWD}"
fi

if [ "${MYSQL_DATABASES}" != "" ];
then
    dbs="--databases ${MYSQL_DATABASES}"
else
    dbs="--all-databases"
fi

echo "`date` [$$] Dumping MySQL: $dbs"

/usr/bin/mysqldump --flush-logs --compact --opt --skip-extended-insert $creds $dbs > mysql.dump
suffix='full'
if [ "`date --date=@${LAST_TS} +'%Y%m%d'`" == "`date --date=@${ts} +'%Y%m%d'`" ];
then
    echo "`date` [$$] Last backup was today"
    if [ -f ${BACKUPS_DIR}/mysql.dump ];
    then
        echo "`date` [$$] Making MySQL dump patch mysql.dump.${ts}.patch"
        /usr/bin/diff ${BACKUPS_DIR}/mysql.dump mysql.dump > mysql.dump.${ts}.patch
        mv -f mysql.dump ${BACKUPS_DIR}/mysql.dump
        suffix='patch'
    else
        cp -f mysql.dump ${BACKUPS_DIR}/mysql.dump
    fi
else
    echo "`date` [$$] Last backup was not today. Keeping full dump."
    cp -f mysql.dump ${BACKUPS_DIR}/mysql.dump
fi

filename=$filename.$suffix

echo "LAST_TS=$ts" > ${BACKUPS_DIR}/dump_backup.cfg

for d in $COPY_DIRS;
do
    echo "`date` [$$] Copying dir $d"
    if [ ! -d .$d ];
    then
        mkdir -p .$d
    fi
    cp -rpf $d/* .$d/
done

echo "`date` [$$] Taring to ${filename}.tgz"
/bin/tar zcf ${BACKUPS_DIR}/${filename}.tgz *

cd ${BACKUPS_DIR}

echo "`date` [$$] Removing snapshot dir ${BACKUPS_DIR}/$snapshot"
rm -rf $snapshot
if [ "${S3_BUCKET}" != "" ]; then
    echo "`date` [$$] Uploading $filename.tgz to ${S3_BUCKET}"
    /usr/bin/s3cmd -c /etc/s3cmd put $filename.tgz ${S3_BUCKET}

    datecheck=`date --date '3 days ago' +%s`

    contents=`/usr/bin/s3cmd -c /etc/s3cmd ls ${S3_BUCKET} | grep backup_ | /usr/bin/awk '{printf "%s$%s\n", $1,$4;}'`

    echo "`date` [$$] Deleting old backups ..."
    for f in $contents;
    do
        fd=`echo $f | /usr/bin/awk -F$ '{print $1;}'`
        fn=`echo $f | /usr/bin/awk -F$ '{print $2;}'`
        fd_s=$(date --date="$fd" +%s)

        if [ $fd_s -le $datecheck ];
        then
            echo "`date` [$$]    ... $fn"
            /usr/bin/s3cmd -c /etc/s3cmd del $fn
    fi

    done
    echo "`date` [$$] Deleting backup file"
    rm ${BACKUPS_DIR}/${filename}.tgz
else
    echo "`date` [$$] S3_BUCKET env variable not set. Backup left at ${BACKUPS_DIR}/${filename}.tgz"

    datecheck=`date --date '8 days ago' +%s`

    contents=`ls -l --time-style=+%Y-%m-%d | grep backup_ | /usr/bin/awk '{printf "%s$%s\n", $6,$7;}'`

    echo "`date` [$$] Deleting old backups ..."
    for f in $contents;
    do
        fd=`echo $f | /usr/bin/awk -F$ '{print $1;}'`
        fn=`echo $f | /usr/bin/awk -F$ '{print $2;}'`
        fd_s=$(date --date="$fd" +%s)

        if [ $fd_s -le $datecheck ];
        then
            echo "`date` [$$]    ... $fn"
            rm $fn
    fi

    done
fi

echo "`date` [$$] Finished dumped backup"
