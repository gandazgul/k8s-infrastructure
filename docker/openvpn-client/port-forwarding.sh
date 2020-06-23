#!/usr/bin/env bash
# Source: http://www.htpcguides.com
# Adapted from https://github.com/blindpet/piavpn-portforward/
# Author: Mike and Drake
# Based on https://github.com/crapos/piavpn-portforward

# Set path for root Cron Job
# PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

echo "Obtaining forwarded port..."

# declaring array list and index iterator
declare -a credentials=()
i=0

# reading file in row mode, insert each line into array
while IFS= read -r line; do
    credentials[i]=$line
    let "i++"
done < "/vpn/credentials.conf"

USERNAME=${credentials[0]}
PASSWORD=${credentials[1]}
VPNINTERFACE=tun0
VPNLOCALIP=$(ifconfig $VPNINTERFACE | awk '/inet / {print $2}' | awk 'BEGIN { FS = ":" } {print $(NF)}')
CURL_TIMEOUT=5
CLIENT_ID=$(uname -v | sha1sum | awk '{ print $1 }')
TRANSUSER=transmission
TRANSPASS="Winter is coming!"
TRANSHOST=localhost

#request new port
PORTFORWARDJSON=$(curl -m $CURL_TIMEOUT --silent --interface $VPNINTERFACE  'https://www.privateinternetaccess.com/vpninfo/port_forward_assignment' -d "user=$USERNAME&pass=$PASSWORD&client_id=$CLIENT_ID&local_ip=$VPNLOCALIP" | head -1)
echo $PORTFORWARDJSON
#trim VPN forwarded port from JSON
PORT=$(echo $PORTFORWARDJSON | grep -oE '[0-9]+')
# echo $PORT

#change transmission port on the fly
echo "Changing transmission's port..."

SESSIONID=$(curl -u "$TRANSUSER:$TRANSPASS" ${TRANSHOST}:9091/transmission/rpc --silent | grep -oE "X-Transmission-Session-Id: ([^<]+)" | awk -F:\  '{print $2}')
echo "SessionID: ${SESSIONID}"

DATA='{"method": "session-set", "arguments": { "peer-port" :'$PORT' } }'

curl -u "$TRANSUSER:$TRANSPASS" http://${TRANSHOST}:9091/transmission/rpc -d "$DATA" -H "X-Transmission-Session-Id: $SESSIONID"
