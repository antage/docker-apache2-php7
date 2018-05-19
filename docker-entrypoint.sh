#!/bin/bash
set -e

if [ "$CREATE_USER_UID" -a "$CREATE_USER_GID" ]; then
    echo "Create 'site-owner' group with GID=$CREATE_USER_GID"
    groupadd -g $CREATE_USER_GID site-owner
    echo "Add 'www-data' user to group 'site-owner'"
    usermod -a -G site-owner www-data
    echo "Create 'site-owner' user with UID=$CREATE_USER_UID, GID=$CREATE_USER_GID"
    useradd -d /var/www -g $CREATE_USER_GID -s /bin/false -M -N -u $CREATE_USER_UID site-owner
fi

if [ -n "$CREATE_SYMLINKS" ]; then
    for link in ${CREATE_SYMLINKS//,/ }; do
        TARGET=${link%>*}
        TARGET_DIR=${TARGET%/*}
        FROM=${link#*>}
        echo "Creating symlink from '${FROM}' to '${TARGET}'"
        if [ ! -d $TARGET_DIR ]; then
            echo -e "\tcreating directory '${TARGET_DIR}'"
            mkdir -p $TARGET_DIR
        fi
        ln -sf $FROM $TARGET
    done
fi

export PHP_TIMEZONE="${PHP_TIMEZONE:-UTC}"
for mod in $(echo $PHP_MODS | tr ',' ' '); do
    echo "Enabling PHP 7.x module '$mod'."
    phpenmod -s ALL $mod
done

if [ -n "$PHP_NEWRELIC_LICENSE_KEY" -a -n "$PHP_NEWRELIC_APPNAME" ]; then
    phpenmod -s apache2 newrelic
fi

export APACHE_SERVER_NAME="${APACHE_SERVER_NAME:-$(hostname)}"
export APACHE_DOCUMENT_ROOT="${APACHE_DOCUMENT_ROOT:-/var/www/html}"

echo "Updating apache/php configuration files."
/usr/local/bin/confd -onetime -backend env

if [ "$1" = 'apache2' ]; then
    if [ -n "$APACHE_COREDUMP" ]; then
        a2enconf coredump
    fi

    for mod in $( echo $APACHE_MODS | tr ',' ' '); do
        a2enmod -q $mod
    done

    echo "Starting Apache 2.x in foreground."
    exec /usr/bin/setpriv --inh-caps -sys_ptrace --bounding-set -sys_ptrace /usr/sbin/apache2 -D FOREGROUND
fi

exec "$@"
