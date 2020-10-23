#!/usr/bin/env bash

# start crond to run the transmission port cronjob
crond

# Call the original entry point
/usr/bin/transmission-daemon --foreground -g /data --port "${RPC_PORT}"
