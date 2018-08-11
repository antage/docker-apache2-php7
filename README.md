# apache2-php7

Apache 2.x + mod\_php 7.x

Based on debian:stable.

## Building

Just run `make`.

## Volumes

* `/var/lib/php/sessions` (tmpfs is recommended)
* `/tmp/apache2-coredumps` (optional)
* `/var/log/apache2`
* `/var/www`

## Exposed ports

* 8080/tcp

## Environment variables

* `CREATE_USER_UID`
* `CREATE_USER_GID`
* `CREATE_SYMLINKS` (for example: "/var/www/dir1>/var/dir1,/var/www/dir2>/var/dir2")
* `APACHE_COREDUMP`
* `APACHE_RUN_USER`
* `APACHE_RUN_GROUP`
* `APACHE_MODS`
* `APACHE_DOCUMENT_ROOT` (/var/www/html by default)
* `APACHE_SERVER_NAME` (hostname by default)
* `APACHE_ALLOW_OVERRIDE` ('None' by default)
* `APACHE_ALLOW_ENCODED_SLASHES` ('Off' by default)
* `APACHE_MAX_REQUEST_WORKERS` (32 by default)
* `APACHE_MAX_CONNECTIONS_PER_CHILD` (1024 by default)
* `APACHE_DISABLE_ACCESS_LOG` (empty by default)
* `PHP_MODS`
* `PHP_TIMEZONE` ('UTC' by default)
* `PHP_SMTP` - MTA SMTP IP-address/hostname
* `PHP_SMTP_FROM` - default `From` header for mail.
* `PHP_MBSTRING_FUNC_OVERLOAD` - `mbstring.func_overload` (0 by default).
* `PHP_NEWRELIC_LICENSE_KEY` - Newrelic agent license key (empty and disabled by default).
* `PHP_NEWRELIC_APPNAME` - Newrelic application name (empty by default).
* `PHP_NEWRELIC_FRAMEWORK` - Newrelic framework name ('no_framework' by default).
* `PHP_NEWRELIC_PORT` - newrelic-daemon socket path or port number ('/run/newrelic/newrelic.sock' by default).

## Required variables

Following variables must be defined to run the container:

* `PHP_SMTP`
* `PHP_SMTP_FROM`
