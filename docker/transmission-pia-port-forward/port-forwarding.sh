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
  TRANSHOST=localhost

  echo 'Loading port forward assignment information...'
  PORT=`cat /data/forwarded_port`

  #change transmission port on the fly
  echo "Changing transmission's port to ${PORT}..."

  SESSIONID=$(curl ${TRANSHOST}:9091/transmission/rpc --silent | grep -oE "X-Transmission-Session-Id: ([^<]+)" | awk -F:\  '{print $2}')
  echo "SessionID: ${SESSIONID}"

  DATA='{"method": "session-set", "arguments": { "peer-port" :'$PORT' } }'

  curl -u "$TRANSUSER:$TRANSPASS" http://${TRANSHOST}:9091/transmission/rpc -d "$DATA" -H "X-Transmission-Session-Id: $SESSIONID"
}

PROGRAM=`basename $0`
VERSION=2.1

while test $# -gt 0
do
  case $1 in
  --usage | --help | -h )
    usage_and_exit 0
    ;;
  --version | -v )
    version
    exit 0
    ;;
  *)
    error_and_usage "Unrecognized option: $1"
    ;;
  esac
  shift
done

port_forward_assignment

exit 0
