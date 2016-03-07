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

# Update php config
perl -pi -e "s%^short_open_tag = Off%short_open_tag = On%" /etc/php.ini
perl -pi -e "s%^;date.timezone =%date.timezone = Europe/Paris%" /etc/php.ini

# Update nscd config
perl -pi -e "s%enable-cache[\t ]+group[\t ]+yes%enable-cache group no%" /etc/nscd.conf

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
