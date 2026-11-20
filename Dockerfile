# PHP 7.3.31 (Debian buster 7.3.31-1~deb10u7) built from the official source
# package with the security patches listed in security/series applied on top.
#
#   builder  - compiles the php7.3 source debs (dpkg-buildpackage)
#   (final)  - full runtime stack: apache2 + built php7.3 + extensions
#
# Buster is EOL, both stages use archive.debian.org.

FROM debian:buster AS builder

ENV DEBIAN_FRONTEND=noninteractive
RUN \
    printf 'deb [check-valid-until=no] http://archive.debian.org/debian buster main\ndeb-src [check-valid-until=no] http://archive.debian.org/debian buster main\ndeb [check-valid-until=no] http://archive.debian.org/debian-security buster/updates main\ndeb-src [check-valid-until=no] http://archive.debian.org/debian-security buster/updates main\n' > /etc/apt/sources.list \
    && apt-get -y -q update \
    && apt-get -y -q --no-install-recommends install \
        ca-certificates \
        dpkg-dev \
        fakeroot \
        quilt \
        wget \
    && apt-get -y -q build-dep php7.3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Official buster-security source package (7.3.31-1~deb10u7), sha256-verified.
RUN \
    mkdir -p /build/php7.3/src \
    && cd /build/php7.3/src \
    && wget \
        http://archive.debian.org/debian-security/pool/updates/main/p/php7.3/php7.3_7.3.31.orig.tar.xz \
        http://archive.debian.org/debian-security/pool/updates/main/p/php7.3/php7.3_7.3.31-1~deb10u7.debian.tar.xz \
        http://archive.debian.org/debian-security/pool/updates/main/p/php7.3/php7.3_7.3.31-1~deb10u7.dsc \
    && ls -la \
    && echo "d1aa8f44595d01ac061ff340354d95e146d6152f70e799b44d6b8654fb45cbcc  php7.3_7.3.31.orig.tar.xz" | sha256sum -c - \
    && echo "54a61d282eee61599400be8cf7eb8eff3474ad8be20e84ba22aa9d80fef3907a  php7.3_7.3.31-1~deb10u7.debian.tar.xz" | sha256sum -c - \
    # manual unpack: the dsc carries an inline PGP signature and the fresh
    # container has no uploader key, so dpkg-source -x would refuse
    && tar xJf php7.3_7.3.31.orig.tar.xz \
    && mv php-7.3.31 php7.3-7.3.31 \
    && tar xJf php7.3_7.3.31-1~deb10u7.debian.tar.xz -C php7.3-7.3.31 \
    && test -f php7.3-7.3.31/debian/patches/series

# security/series is appended to debian/patches/series in order, so
# dpkg-buildpackage (3.0 quilt) applies it after the Debian patches.
COPY security/ /build/php7.3/security/
RUN \
    cd /build/php7.3/src/php7.3-7.3.31 \
    && while read -r patch_name; do \
        case "$patch_name" in ''|'#'*) continue ;; esac; \
        cp "/build/php7.3/security/$patch_name" debian/patches/ \
        && echo "$patch_name" >> debian/patches/series; \
    done < /build/php7.3/security/series \
    && dpkg-buildpackage -us -uc -b -d -j"$(nproc)" \
    && mv ../*.deb /build/php7.3/

# ---------------------------------------------------------------------------

FROM debian:buster

ENV DEBIAN_FRONTEND=noninteractive
RUN \
    printf 'deb [check-valid-until=no] http://archive.debian.org/debian buster main\ndeb [check-valid-until=no] http://archive.debian.org/debian-security buster/updates main\n' > /etc/apt/sources.list \
    && apt-get -y -q update \
    && apt-get -y -q --no-install-recommends install apt-transport-https curl ca-certificates gnupg \
    && echo "deb http://apt.newrelic.com/debian/ newrelic non-free" > /etc/apt/sources.list.d/newrelic.list \
    && curl -s https://download.newrelic.com/548C16BF.gpg | apt-key add - \
    && apt-get -y -q update

# Base runtime stack (no php7.3-* here: they come from the builder stage).
RUN \
    apt-get -y -q --no-install-recommends install \
        util-linux \
        curl \
        locales \
        imagemagick \
        libmagickcore-6.q16-6-extra \
        msmtp-mta \
        apache2 \
        libapr1-dbg \
        libaprutil1-dbg \
        gdb \
        ffmpeg \
        ghostscript \
        wget \
        pngquant \
        jpegoptim \
        optipng \
        gosu \
        unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm /var/log/dpkg.log \
    && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen \
    && dpkg-reconfigure locales \
    && rm /var/www/html/index.html \
    && rmdir /var/www/html

# ImageTragick hardening: the buster policy is replaced by ours (see
# security/imagemagick-policy.xml and security/README.md).
COPY security/imagemagick-policy.xml /etc/ImageMagick-6/policy.xml

# PHP 7.3.31 built from source (builder stage), all packages of the source
# build: common/cli/opcache/xml/curl/gd/intl/xsl/zip/mysql/pgsql/xmlrpc/dev/
# libapache2-mod-php7.3/embed/etc. apt resolves the inter-deb order itself
# (dpkg -i would not: the php7.3 metapackage sorts before its deps).
COPY --from=builder /build/php7.3/*.deb /tmp/debs/
RUN \
    apt-get update \
    && apt-get -y -q --no-install-recommends install /tmp/debs/*.deb \
    && apt-get -y -q --no-install-recommends install \
        php7.3-xdebug \
        php-igbinary \
        php-redis \
        php-imagick \
        php-pear \
        php7.3-memcache \
        php7.3-mongo \
        php7.3-amqp \
        php7.3-apcu \
        newrelic-php5 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm /tmp/debs/*.deb \
    && rm /var/log/dpkg.log

# ionCube loader (7.3), confd, composer
RUN \
    curl -#L http://downloads3.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz -o /tmp/ioncube.tar.gz \
    && tar xzf /tmp/ioncube.tar.gz -C /tmp/ \
    && install -m 0644 \
        /tmp/ioncube/ioncube_loader_lin_$(php -r 'printf("%s.%s", PHP_MAJOR_VERSION, PHP_MINOR_VERSION);').so \
        $(php -r 'printf("%s", PHP_EXTENSION_DIR);')/ioncube_loader.so \
    && rm -rf /tmp/ioncube \
    && rm /tmp/ioncube.tar.gz \
    && echo "; configuration for php ionCube loader module\n; priority=00\nzend_extension=ioncube_loader.so" > /etc/php/7.3/mods-available/ioncube_loader.ini \
    && curl -#L https://github.com/kelseyhightower/confd/releases/download/v0.11.0/confd-0.11.0-linux-amd64 -o /usr/local/bin/confd \
    && chmod 755 /usr/local/bin/confd \
    && mkdir -p /etc/confd/conf.d \
    && mkdir -p /etc/confd/templates \
    && touch /etc/confd/confd.toml \
    && curl -o /usr/local/bin/composer https://getcomposer.org/download/1.8.6/composer.phar \
    && chown root:root /usr/local/bin/composer \
    && chmod 0755 /usr/local/bin/composer

RUN \
    rm /etc/php/7.3/apache2/conf.d/* \
    && rm /etc/php/7.3/cli/conf.d/* \
    && phpenmod -s ALL opcache \
    && rm /etc/apache2/conf-enabled/* \
    && rm /etc/apache2/mods-enabled/* \
    && a2enmod mpm_prefork rewrite php7.3 env dir auth_basic authn_file authz_user authz_host access_compat \
    && rm /etc/apache2/sites-enabled/000-default.conf \
    && rm /var/run/newrelic-daemon.pid

COPY Rediska-0.5.10.tgz /tmp/Rediska-0.5.10.tar.gz
RUN phpenmod -s cli xml \
    && pear install /tmp/Rediska-0.5.10.tar.gz \
    && rm /tmp/Rediska-0.5.10.tar.gz \
    && phpdismod -s cli xml

EXPOSE 8080

ENV LANG=C
ENV APACHE_LOCK_DIR         /var/lock/apache2
ENV APACHE_RUN_DIR          /var/run/apache2
ENV APACHE_PID_FILE         ${APACHE_RUN_DIR}/apache2.pid
ENV APACHE_LOG_DIR          /var/log/apache2
ENV APACHE_RUN_USER         www-data
ENV APACHE_RUN_GROUP        www-data
ENV APACHE_START_SERVERS       2
ENV APACHE_MIN_SPARE_SERVERS   2
ENV APACHE_MAX_SPARE_SERVERS   8
ENV APACHE_MAX_REQUEST_WORKERS 32
ENV APACHE_MAX_CONNECTIONS_PER_CHILD 1024
ENV APACHE_ALLOW_OVERRIDE   None
ENV APACHE_ALLOW_ENCODED_SLASHES Off
ENV PHP_TIMEZONE            UTC
ENV PHP_MBSTRING_FUNC_OVERLOAD 0
ENV PHP_NEWRELIC_LICENSE_KEY    ""
ENV PHP_NEWRELIC_APPNAME        ""
ENV PHP_NEWRELIC_FRAMEWORK      "no_framework"
ENV PHP_NEWRELIC_PORT           "/run/newrelic/newrelic.sock"

COPY apache2-coredumps.conf /etc/security/limits.d/apache2-coredumps.conf
RUN mkdir /tmp/apache2-coredumps && chown ${APACHE_RUN_USER}:${APACHE_RUN_GROUP} /tmp/apache2-coredumps && chmod 700 /tmp/apache2-coredumps
COPY apache2-conf/coredump.conf /etc/apache2/conf-available/coredump.conf
COPY apache2-conf/charset.conf /etc/apache2/conf-available/charset.conf
COPY apache2-conf/security.conf /etc/apache2/conf-available/security.conf
COPY .gdbinit /root/.gdbinit

COPY opcache_bitrix.blacklist /etc/php/7.3/opcache_bitrix.blacklist

COPY confd/php.cli.toml /etc/confd/conf.d/
COPY confd/templates/php.cli.ini.tmpl /etc/confd/templates/
COPY confd/php.apache2.toml /etc/confd/conf.d/
COPY confd/templates/php.apache2.ini.tmpl /etc/confd/templates/
COPY confd/apache2.toml /etc/confd/conf.d/
COPY confd/templates/apache2.conf.tmpl /etc/confd/templates/
COPY confd/mpm_prefork.toml /etc/confd/conf.d/
COPY confd/templates/mpm_prefork.conf.tmpl /etc/confd/templates/
COPY confd/newrelic.toml /etc/confd/conf.d/
COPY confd/templates/newrelic.ini.tmpl /etc/confd/templates/
RUN /usr/local/bin/confd -onetime -backend env
COPY confd/msmtprc.toml /etc/confd/conf.d/
COPY confd/templates/msmtprc.tmpl /etc/confd/templates/

COPY ports.conf /etc/apache2/ports.conf

COPY apache2-mods/php7.3.conf /etc/apache2/mods-available/php7.3.conf
COPY apache2-mods/mime.conf /etc/apache2/mods-available/mime.conf
COPY apache2-mods/alias.conf /etc/apache2/mods-available/alias.conf
COPY apache2-mods/autoindex.conf /etc/apache2/mods-available/autoindex.conf

COPY apache2-mods/remoteip.conf /etc/apache2/mods-available/remoteip.conf
RUN a2enmod remoteip

RUN a2enconf charset
RUN a2enconf security

COPY docker-entrypoint.sh /

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["apache2"]
