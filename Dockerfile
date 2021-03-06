FROM debian:jessie-slim

MAINTAINER Andreas Krüger <ak@patientsky.com>

ENV php_conf /etc/php/7.1/cli/php.ini
ENV DEBIAN_FRONTEND noninteractive
ENV composer_hash 55d6ead61b29c7bdee5cccfb50076874187bd9f21f65d8991d46ec5cc90518f447387fb9f76ebae1fbbacf329e583e30

RUN apt-get update \
    && apt-get install -y -q --no-install-recommends \
    apt-transport-https \
    lsb-release \
    wget \
    curl \
    apt-utils \
    ca-certificates

RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF

RUN echo "deb http://download.mono-project.com/repo/debian wheezy/snapshots 4.6.2/main" > /etc/apt/sources.list.d/mono-xamarin.list \
  && echo "deb http://download.mono-project.com/repo/debian wheezy-apache24-compat main" | tee -a /etc/apt/sources.list.d/mono-xamarin.list \
  && echo "deb http://download.mono-project.com/repo/debian wheezy-libjpeg62-compat main" | tee -a /etc/apt/sources.list.d/mono-xamarin.list \
  && apt-get update \
  && apt-get install -y --force-yes binutils mono-complete ca-certificates-mono fsharp

RUN wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg && \
    echo "deb https://packages.sury.org/php/ jessie main" > /etc/apt/sources.list.d/php.list

RUN echo 'deb http://apt.newrelic.com/debian/ newrelic non-free' | tee /etc/apt/sources.list.d/newrelic.list && \
    wget -O- https://download.newrelic.com/548C16BF.gpg | apt-key add -

RUN apt-get update \
    && apt-get install -y -q --no-install-recommends \
    php7.1-cli \
    php7.1-mysql \
    php7.1-bcmath \
    php7.1-gd \
    php7.1-curl \
    php7.1-json \
    php7.1-mcrypt \
    php7.1-cli \
    php7.1-apcu \
    php7.1-imagick \
    php7.1-intl \
    php7.1-opcache \
    php7.1-mongodb \
    php7.1-mbstring \
    php7.1-xml \
    php7.1-zip \
    php-igbinary \
    supervisor \
    openssh-client \
    newrelic-php5 \
    newrelic-sysmond \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/*

RUN mkdir -p /var/log/supervisor

ADD conf/supervisord.conf /etc/supervisord.conf

#RUN useradd -ms /bin/bash worker

# tweak php and php-cli config
RUN sed -i \
        -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" \
        -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 100M/g" \
        -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" \
        -e "s/variables_order = \"GPCS\"/variables_order = \"EGPCS\"/g" \
        -e "s/;error_log\s*=\s*syslog/error_log = \/dev\/stdout/g" \
        -e "s/memory_limit\s*=\s*128M/memory_limit = 3072M/g" \
        -e "s/;date.timezone\s*=/date.timezone = Europe\/Oslo/g" \
        -e "s/max_execution_time\s*=\s*30/max_execution_time = 300/g" \
        -e "s/max_input_time\s*=\s*60/max_input_time = 300/g" \
        -e "s/default_socket_timeout\s*=\s*60/default_socket_timeout = 300/g" \
        ${php_conf}

# Cleanup some files and remove comments
RUN find /etc/php/7.1/cli/conf.d -name "*.ini" -exec sed -i -re '/^[[:blank:]]*(\/\/|#|;)/d;s/#.*//' {} \; && \
    find /etc/php/7.1/cli/conf.d -name "*.ini" -exec sed -i -re '/^$/d' {} \;

# Configure php opcode cache
RUN echo "opcache.enable=1" >> /etc/php/7.1/cli/conf.d/10-opcache.ini && \
    echo "opcache.enable_cli=1" >> /etc/php/7.1/cli/conf.d/10-opcache.ini && \
    echo "opcache.validate_timestamps=0" >> /etc/php/7.1/cli/conf.d/10-opcache.ini && \
    echo "opcache.max_accelerated_files=1000000" >> /etc/php/7.1/cli/conf.d/10-opcache.ini && \
    echo "opcache.memory_consumption=1024" >> /etc/php/7.1/cli/conf.d/10-opcache.ini && \
    echo "opcache.interned_strings_buffer=8" >> /etc/php/7.1/cli/conf.d/10-opcache.ini && \
    echo "opcache.revalidate_freq=60" >> /etc/php/7.1/cli/conf.d/10-opcache.ini

# Add Scripts
ADD scripts/start.sh /start.sh
RUN chmod 755 /start.sh

RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
    php -r "if (hash_file('SHA384', 'composer-setup.php') === '${composer_hash}') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" && \
    php composer-setup.php --install-dir=/usr/bin --filename=composer && \
    php -r "unlink('composer-setup.php');"

CMD ["/start.sh"]
