#!/usr/bin/env bash

# start crond to run the transmission port cronjob
crond

# Call the original entry point
/usr/bin/openvpn.sh
