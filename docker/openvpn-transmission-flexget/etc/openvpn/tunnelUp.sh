#!/bin/sh

#/usr/bin/with-contenv bash

/etc/transmission/start.sh "$@"
[ ! -f /opt/tinyproxy/start.sh ] || /opt/tinyproxy/start.sh

# `--autoreload-config` reloads the config *before* running the tasks, not
# when the configuration actually changes.
#
/usr/bin/flexget \
    -c /config/flexget/config.yml \
    daemon start -d --autoreload-config
