#!/usr/bin/env bash

# Set path for root Cron Job
# PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

#
# Enable port forwarding when using Private Internet Access
#
# Usage:
#  ./port_forwarding.sh

error() {
  echo "$@" 1>&2
  exit 1
}

error_and_usage() {
  echo "$@" 1>&2
  usage_and_exit 1
}

usage() {
  echo "Usage: $(dirname $0)/$PROGRAM"
}

usage_and_exit() {
  usage
  exit $1
}

version() {
  echo "$PROGRAM version $VERSION"
}

port_forward_assignment() {
  CURL_TIMEOUT=5
  TRANSUSER=transmission
  #TRANSPASS=Pass this variable in with your password when running the container
  TRANSHOST=localhost

  echo 'Loading port forward assignment information...'
  if [ "$(uname)" == "Linux" ]; then
    CLIENT_ID=$(head -n 100 /dev/urandom | sha256sum | tr -d " -")
  fi
  if [ "$(uname)" == "Darwin" ]; then
    CLIENT_ID=$(head -n 100 /dev/urandom | shasum -a 256 | tr -d " -")
  fi

  PORTFORWARDJSON=$(curl -m ${CURL_TIMEOUT} "http://209.222.18.222:2000/?client_id=${CLIENT_ID}" 2>/dev/null)
  if [ "$json" == "" ]; then
    PORTFORWARDJSON='Port forwarding is already activated on this connection, has expired, or you are not connected to a PIA region that supports port forwarding'
  fi

  echo $PORTFORWARDJSON

  #trim VPN forwarded port from JSON
  PORT=$(echo $PORTFORWARDJSON | grep -oE '[0-9]+')
  # echo $PORT

  #change transmission port on the fly
  echo "Changing transmission's port..."

  SESSIONID=$(curl -u "${TRANSUSER}:${TRANSPASS}" ${TRANSHOST}:9091/transmission/rpc --silent | grep -oE "X-Transmission-Session-Id: ([^<]+)" | awk -F:\  '{print $2}')
  echo "SessionID: ${SESSIONID}"

  DATA='{"method": "session-set", "arguments": { "peer-port" :'$PORT' } }'

  curl -u "$TRANSUSER:$TRANSPASS" http://${TRANSHOST}:9091/transmission/rpc -d "$DATA" -H "X-Transmission-Session-Id: $SESSIONID"
}

exit 0
