#!/bin/sh

/etc/transmission/stop.sh
[ ! -f /opt/tinyproxy/stop.sh ] || /opt/tinyproxy/stop.sh
s6-setuidgid abc /usr/bin/flexget daemon stop
