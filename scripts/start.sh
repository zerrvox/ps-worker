#!/bin/bash

# Disable Strict Host checking for non interactive git clones

mkdir -p -m 0700 /root/.ssh
echo -e "Host *\n\tStrictHostKeyChecking no\n" >> /root/.ssh/config

if [ ! -z "$SSH_KEY" ]; then
 echo $SSH_KEY > /root/.ssh/id_rsa.base64
 base64 -d /root/.ssh/id_rsa.base64 > /root/.ssh/id_rsa
 chmod 600 /root/.ssh/id_rsa
fi

# Setup git variables
if [ ! -z "$GIT_EMAIL" ]; then
 git config --global user.email "$GIT_EMAIL"
fi
if [ ! -z "$GIT_NAME" ]; then
 git config --global user.name "$GIT_NAME"
 git config --global push.default simple
fi

git config --global http.postBuffer 1048576000

# Dont pull code down if the .git folder exists
if [ ! -d "/data/.git" ]; then
 # Pull down code from git for our site!
 if [ ! -z "$GIT_REPO" ]; then
   # Remove the test index file
   rm -Rf /data/*
   if [ ! -z "$GIT_BRANCH" ]; then
     if [ -z "$GIT_USERNAME" ] && [ -z "$GIT_PERSONAL_TOKEN" ]; then
       git clone -b $GIT_BRANCH $GIT_REPO /data || exit 1
     else
       git clone -b ${GIT_BRANCH} https://${GIT_USERNAME}:${GIT_PERSONAL_TOKEN}@${GIT_REPO} /data || exit 1
     fi
   else
     if [ -z "$GIT_USERNAME" ] && [ -z "$GIT_PERSONAL_TOKEN" ]; then
       git clone $GIT_REPO /data || exit 1
     else
       git clone https://${GIT_USERNAME}:${GIT_PERSONAL_TOKEN}@${GIT_REPO} /data || exit 1
     fi
   fi
   #chown -Rf worker.worker /data
 fi
fi

# Always chown webroot for better mounting
#chown -Rf worker.worker /data

# Composer
if [ -f /var/www/html/composer.json ];
then
    cd /var/www/html
    /usr/bin/composer install --no-interaction --no-dev --optimize-autoloader
fi

# Add new relic if key is present
if [ -n "$NEW_RELIC_LICENSE_KEY" ]; then
    echo -e "[program:nrsysmond]\ncommand=nrsysmond -c /etc/newrelic/nrsysmond.cfg -l /dev/stdout -f\nautostart=true\nautorestart=true\npriority=0\nstdout_events_enabled=true\nstderr_events_enabled=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nstderr_logfile=/dev/stderr\nstderr_logfile_maxbytes=0\n" >> /etc/supervisord.conf
fi

# Create workers in supervisord
cd /data
workers=""
if [ -f boot ];
then
    workers=$(/bin/bash ./boot)
else
    workers=$(php app/console melin:systemeventlistener:launch -e worker)
    workers="$workers
    $(php app/console melin:eventhandler:launch -e worker)
    $(php app/console melin:systemevents:launch -e worker)"
fi

if [ "$workers" == "" ];
then
    echo "No workers to launch. Quitting"
    exit 1
fi

i=1
while read job; do
    job=$(echo $job | perl -pe 's/\\/\\\\/g' )

    if [ "x$job" != "x" ]; then
        echo -e "[program:worker$i]\ncommand=$job\nautostart=true\nautorestart=true\npriority=0\nstdout_events_enabled=true\nstderr_events_enabled=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nstderr_logfile=/dev/stderr\nstderr_logfile_maxbytes=0\n" >> /etc/supervisord.conf
        let i=i+1
    fi
done <<< "$workers"

if [ -f /data/WorkerBoot ]; then
    while read line; do
      job=`echo $line | awk '{ $1=""; print $0}'`

      if [ "x$job" != "x" ]; then
          echo -e "[program:worker$i]\ncommand=$job\nautostart=true\nautorestart=true\npriority=0\nstdout_events_enabled=true\nstderr_events_enabled=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nstderr_logfile=/dev/stderr\nstderr_logfile_maxbytes=0\n" >> /etc/supervisord.conf
          let i=i+1
      fi
    done < /data/WorkerBoot
fi

build_id=0
if [ -f /data/build_version ];
then
    build_id=$(cat /data/build_version)
fi
cd /data
php app/console newrelic:notify-deployment --revision="$build_id" -e prod
php app/console melin:clientmessaging:newdeployment -e prod
php app/console melin:cloudinary:upload -e prod

# Start supervisord and services
/usr/bin/supervisord -n -c /etc/supervisord.conf
