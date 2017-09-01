FROM debian:stretch-slim

MAINTAINER Arvind Mohan "arvind@dreamjwell.com"

ENV DEBIAN_FRONTEND noninteractive

ENV NGINX_VERSION 1.13.3-1~stretch
ENV NJS_VERSION   1.13.3.0.1.11-1~stretch
ENV PHP_ROOT_DIR /app
ENV PHP_VERSION 7.0
ENV MYSQL_MAJOR 5.7
ENV MYSQL_VERSION 5.7.19-1debian9
ENV MYSQL_ROOT_PASSWORD my-secret-pw
ENV MYSQL_DATADIR /var/lib/mysql
ENV MYSQL_RUN_USER mysql
ENV MYSQL_RUN_GROUP mysql

RUN groupadd -r $MYSQL_RUN_GROUP && \
    useradd -r -g $MYSQL_RUN_GROUP $MYSQL_RUN_USER

RUN apt-get update && apt-get install --no-install-recommends \
    --no-install-suggests -y    \
    gnupg2                      \
    wget                        \
    ca-certificates             \
    dirmngr                     \
    gosu                        \
    supervisor                  \
    pwgen                       \
    openssl                     \
    perl                        \
    curl                        \
    git                         \
    nginx                       \
    gettext-base

COPY tools/mysql_pubkey.asc /mysql_pubkey.asc
RUN set -ex; \
	key='A4A9406876FCBD3C456770C88C718D3B5072E1F5'; \
	gpg --import /mysql_pubkey.asc; \
    gpg --export "$key" > /etc/apt/trusted.gpg.d/mysql.gpg; \
	apt-key list > /dev/null

RUN echo "deb http://repo.mysql.com/apt/debian/ stretch mysql-${MYSQL_MAJOR}" \
    > /etc/apt/sources.list.d/mysql.list

RUN { \
		echo mysql-community-server mysql-community-server/data-dir select ''; \
		echo mysql-community-server mysql-community-server/root-pass password ''; \
		echo mysql-community-server mysql-community-server/re-root-pass password ''; \
		echo mysql-community-server mysql-community-server/remove-test-db select false; \
	} | debconf-set-selections                      \
    && apt-get update                               \
    && apt-get install --no-install-recommends -y   \
        mysql-server="${MYSQL_VERSION}"             \
        php${PHP_VERSION}                           \
        php${PHP_VERSION}-cli                       \
        php${PHP_VERSION}-fpm                       \
        php${PHP_VERSION}-common                    \
        php${PHP_VERSION}-mysql                     \
        php${PHP_VERSION}-mbstring                  \
        php${PHP_VERSION}-mcrypt                    \
        php${PHP_VERSION}-bcmath                    \
        php${PHP_VERSION}-xml                       \
        php${PHP_VERSION}-json                      \
        php${PHP_VERSION}-gd                        \
        php${PHP_VERSION}-curl                      \
        php${PHP_VERSION}-bz2                       \
		php${PHP_VERSION}-zip                       \
		php${PHP_VERSION}-apcu                      \
		libphp${PHP_VERSION}-embed                  \
    && rm -rf /var/lib/apt/lists/*                  \
    && rm -rf $MYSQL_DATADIR                        \
    && mkdir -p $MYSQL_DATADIR /var/run/mysqld      \
    && chown -R $MYSQL_RUN_USER:$MYSQL_RUN_GROUP    \
                $MYSQL_DATADIR /var/run/mysqld      \
    # ensure that /var/run/mysqld (used for socket and lock files) is writable
    # regardless of the UID our mysqld instance ends up having at runtime
    && chmod 777 /var/run/mysqld

# comment out a few problematic configuration values
# don't reverse lookup hostnames, they are usually another container
RUN sed -Ei 's/^(bind-address|log)/#&/' /etc/mysql/mysql.conf.d/mysqld.cnf \
	&& echo '[mysqld]\nskip-host-cache\nskip-name-resolve' > /etc/mysql/conf.d/docker.cnf

COPY setup ${PHP_ROOT_DIR}/setup
COPY tools/*.sh /usr/local/bin/
COPY tools/supervisord.conf /etc/supervisor/conf.d/
COPY tools/installer ${PHP_ROOT_DIR}/composer-setup.php
COPY tools/adminer-*.php ${PHP_ROOT_DIR}/adminer/index.php
COPY tools/nginx.conf /etc/nginx/sites-available/default
COPY tools/php-fpm.conf /etc/php/${PHP_VERSION}/fpm/pool.d/www

RUN chmod 644 ${PHP_ROOT_DIR}/adminer/index.php
RUN php ${PHP_ROOT_DIR}/composer-setup.php --install-dir=/usr/bin \
    --filename=composer && rm ${PHP_ROOT_DIR}/composer-setup.php

RUN mkdir -p /run/php

VOLUME ${MYSQL_DATADIR}
WORKDIR ${PHP_ROOT_DIR}

ENTRYPOINT ["entrypoint.sh"]

EXPOSE 80
EXPOSE 3306

STOPSIGNAL SIGTERM

CMD ["mysqld"]
