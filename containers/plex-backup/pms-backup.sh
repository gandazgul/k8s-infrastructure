#!/bin/bash

# Run this script with the following variables exported
# GOTIFY_TOKEN=xxxxxx
# PLEX_IP=x.x.x.x

BACKUP_LOC="${BACKUP_LOC:-/media/backup/pms-backup}"
# PMS_DIR="${PMS_DIR:-/media/yasr/configs/plex/Library/Application\ Support/Plex\ Media\ Server/}"
PMS_DIR="/media/yasr/configs/plex/Library/Application Support/Plex Media Server/"
PMS_LIST=(${PMS_LIST:-"Media" "Metadata" "Plug-ins" "Plug-in Support" "Preferences.xml"})
LOGFILE="${LOGFILE:-$BACKUP_LOC/pms-backup.log}"
# MSG_URL="https://gotify.fqdn/message?token=$GOTIFY_TOKEN"

function sendMsg {
    # 1 = msg, 2 = priority
    MSG_TITLE="Plex Backup Script"
    MSG=$1
    MSG_PRIORITY=$2
    MSG_DATE="$(date '+%Y-%m-%d %T')"

    echo "$MSG_DATE $MSG" | tee -a $LOGFILE
    # if [ $MSG_PRIORITY -gt 1 ]; then
        # eval $(curl $MSG_URL -F "title=$MSG_TITLE" -F "message=$MSG" -F "priority=$MSG_PRIORITY")
    # fi
}

# create log file
touch $LOGFILE

sendMsg "Starting Plex Backup" "1"

# check for pms directories
if [ ! -d "$PMS_DIR" ]; then
    sendMsg "Can't find Plex Media Server directory, exiting..." "3"
    exit 1
fi

# check for backup location mounted
if [ ! -d "$BACKUP_LOC" ]; then
    sendMsg "Backup location not found, exiting..." "3"
    exit 1
fi

# switching to a directory where I should have enough space
pushd "$PMS_DIR"

BK_PREFIX="pms-backup-$(date '+%Y-%m-%d-%H%M%S')"
# tar components (loop)
for i in "${PMS_LIST[@]}"; do
    sendMsg "Backing up $i ..." "1"
    
    # add conditional filename change for directory with space
    if [ "$i" == "Plug-in Support" ]; then
        FILENAME="$PMS_DIR/$BK_PREFIX-Plug-in_Support.tar.gz"
    else
        FILENAME="$PMS_DIR/$BK_PREFIX-$i.tar.gz"  
    fi
    # make archive
    # uncomment below for verbose flag
    #tar -czvf "$FILENAME" "$i"
    # comment out if using the verbose flag above
    tar -czf "$FILENAME" "$i"
    
    if [ -d "$BACKUP_LOC" ]; then
        mv "$FILENAME" "$BACKUP_LOC/"
    else
        sendMsg "Issue with Mount Location ${BACKUP_LOC}, skipping moving ${FILENAME}" "3"
    fi
done

popd
sendMsg "Backup Completed" "1"

# start pms service
sendMsg "Restarting Plex Media Server" "1"
systemctl start plexmediaserver
sleep 10

# checking to ensure running
if [[ "$(systemctl is-active --quiet plexmediaserver)" -ne 0 ]]; then
    sendMsg "Plex is not running, startup might have gone wrong" "3"
    exit 1
fi