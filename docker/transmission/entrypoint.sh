#!/usr/bin/env bash

# start crond to run the transmission port cronjob
touch /var/log/crond.log
crond -L /var/log/crond.log

# Call the original entry point
su -s /bin/bash abc -c \
  "/usr/bin/transmission-daemon --foreground -g /data --port ${RPC_PORT}"
