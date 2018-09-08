#!/bin/sh

#/usr/bin/with-contenv bash

/etc/transmission/start.sh "$@"
[ ! -f /opt/tinyproxy/start.sh ] || /opt/tinyproxy/start.sh

# `flexget daemon` runs all tasks in the config every hour by default, for more
# options see https://flexget.com/Plugins/Daemon/scheduler.
#
# `--autoreload-config` reloads the config *before* running the tasks, not
# when the configuration actually changes.
#

s6-setuidgid abc /usr/bin/flexget \
    -c /config/flexget/config.yml \
    --loglevel "${FLEXGET_LOG_LEVEL:-debug}" \
    daemon start --autoreload-config
