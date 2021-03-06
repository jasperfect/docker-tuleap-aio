#!/bin/bash

set -x

TULEAP_INSTALL_TIME="false"
if [ ! -f /data/etc/tuleap/conf/local.inc ]; then
    TULEAP_INSTALL_TIME="true"

    # If tuleap directory is not in data, assume it's first boot and move
    # everything in the mounted dir
    ./boot-install.sh
fi

# Fix path
./boot-fixpath.sh

# Allow configuration update at boot time
./boot-update-config.sh

source mysql-utils.sh

start_mysql

if [ "$TULEAP_INSTALL_TIME" == "false" ]; then
    # It seems there is no way to have nscd in foreground
    /usr/sbin/nscd

    # DB upgrade (after config as we might depends on it)
    ./boot-upgrade.sh
fi

# Activate backend/crontab
/etc/init.d/tuleap start

stop_mysql

exec supervisord -n
