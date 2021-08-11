#!/usr/bin/env bash
set -euo pipefail
trap trapexit EXIT SIGTERM

TEMPDIR=$(mktemp -d)
TEMPLOG="$TEMPDIR/tmplog"
TEMPERR="$TEMPDIR/tmperr"
LASTCMD=""
WGETOPT="-t 1 -T 15 -q"
NPMURL="https://github.com/jc21/nginx-proxy-manager"

cd $TEMPDIR
touch $TEMPLOG

# Helpers
log() {
  logs=$(cat $TEMPLOG | sed -e "s/34/32/g" | sed -e "s/info/success/g");
  clear && printf "\033c\e[3J$logs\n\e[34m[info] $*\e[0m\n" | tee $TEMPLOG;
}
runcmd() {
  LASTCMD=$(grep -n "$*" "$0" | sed "s/[[:blank:]]*runcmd//");
  if [[ "$#" -eq 1 ]]; then
    eval "$@" 2>$TEMPERR;
  else
    $@ 2>$TEMPERR;
  fi
}
trapexit() {
  status=$?

  if [[ $status -eq 0 ]]; then
    logs=$(cat $TEMPLOG | sed -e "s/34/32/g" | sed -e "s/info/success/g")
    clear && printf "\033c\e[3J$logs\n";
  elif [[ -s $TEMPERR ]]; then
    logs=$(cat $TEMPLOG | sed -e "s/34/31/g" | sed -e "s/info/error/g")
    err=$(cat $TEMPERR | sed $'s,\x1b\\[[0-9;]*[a-zA-Z],,g' | rev | cut -d':' -f1 | rev | cut -d' ' -f2-)
    clear && printf "\033c\e[3J$logs\e[33m\n$0: line $LASTCMD\n\e[33;2;3m$err\e[0m\n"
  else
    printf "\e[33muncaught error occurred\n\e[0m"
  fi

  # Cleanup
  apt-get remove --purge -y build-essential python3-dev git -qq &>/dev/null
  apt-get autoremove -y -qq &>/dev/null
  apt-get clean
  rm -rf $TEMPDIR
  rm -rf /root/.cache
}

# Check for previous install
if [ -f /lib/systemd/system/npm.service ]; then
  log "Stopping services"
  systemctl stop openresty
  systemctl stop npm

  # Cleanup for new install
  log "Cleaning old files"
  rm -rf /app \
  /var/www/html \
  /etc/nginx \
  /var/log/nginx \
  /var/lib/nginx \
  /var/cache/nginx &>/dev/null
  
  # Install dependencies
  log "Installing dependencies"
  echo "fs.file-max = 65535" > /etc/sysctl.conf
  # runcmd apt-get update
  runcmd apt-get -y install --no-install-recommends wget gnupg openssl ca-certificates apache2-utils logrotate build-essential python3-dev git lsb-release
  pip3 install --upgrade setuptools
  pip3 install --upgrade pip
  
else
  # Install dependencies
  log "Installing dependencies"
  echo "fs.file-max = 65535" > /etc/sysctl.conf
  runcmd apt-get update
  runcmd apt-get -y install --no-install-recommends wget gnupg openssl ca-certificates apache2-utils logrotate build-essential python3-dev git lsb-release

  # Install Python
  log "Installing python"
  runcmd apt-get install -y -q --no-install-recommends python3 python3-pip python3-venv
  pip3 install --upgrade setuptools
  pip3 install --upgrade pip
  python3 -m venv /opt/certbot/
  if [ "$(getconf LONG_BIT)" = "32" ]; then
    runcmd python3 -m pip install --no-cache-dir -U cryptography==3.3.2
  fi
  runcmd python3 -m pip install --no-cache-dir cffi certbot

  # Install openresty
  log "Installing openresty"
  wget -O - https://openresty.org/package/pubkey.gpg | apt-key add -
  _distro_release=$(lsb_release -sc)
  _distro_release=$(wget $WGETOPT "http://openresty.org/package/debian/dists/" -O - | grep -o "$_distro_release" | head -n1 || true)
  echo "deb [trusted=yes] http://openresty.org/package/debian ${_distro_release:-focal} openresty" | tee /etc/apt/sources.list.d/openresty.list
  runcmd apt-get update && apt-get install -y -q --no-install-recommends openresty

  # Install nodejs
  log "Installing nodejs"
  runcmd wget -O - https://deb.nodesource.com/setup_14.x | bash -
  runcmd apt-get install -y -q --no-install-recommends nodejs
  runcmd npm install --global yarn
fi

# Get latest version information for nginx-proxy-manager
log "Checking for latest NPM release"
runcmd 'wget $WGETOPT -O ./_latest_release $NPMURL/releases/latest'
_latest_version=$(basename $(cat ./_latest_release | grep -wo "jc21/.*.tar.gz") .tar.gz | cut -d'v' -f2)

# Download nginx-proxy-manager source
log "Downloading NPM v$_latest_version"
runcmd 'wget $WGETOPT -c $NPMURL/archive/v$_latest_version.tar.gz -O - | tar -xz'
cd ./nginx-proxy-manager-$_latest_version

log "Setting up enviroment"
# Crate required symbolic links
ln -sf /usr/bin/python3 /usr/bin/python
ln -sf /usr/bin/certbot /opt/certbot/bin/certbot
ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/sbin/nginx
ln -sf /usr/local/openresty/nginx/ /etc/nginx

# Update NPM version in package.json files
sed -i "s+0.0.0+#$_latest_version+g" backend/package.json
sed -i "s+0.0.0+#$_latest_version+g" frontend/package.json

# Fix nginx config files for use with openresty defaults
sed -i 's+^daemon+#daemon+g' docker/rootfs/etc/nginx/nginx.conf
NGINX_CONFS=$(find "$(pwd)" -type f -name "*.conf")
for NGINX_CONF in $NGINX_CONFS; do
  sed -i 's+include conf.d+include /etc/nginx/conf.d+g' "$NGINX_CONF"
done

# Copy runtime files
mkdir -p /var/www/html /etc/nginx/logs
cp -r docker/rootfs/var/www/html/* /var/www/html/
cp -r docker/rootfs/etc/nginx/* /etc/nginx/
cp docker/rootfs/etc/letsencrypt.ini /etc/letsencrypt.ini
cp docker/rootfs/etc/logrotate.d/nginx-proxy-manager /etc/logrotate.d/nginx-proxy-manager
ln -sf /etc/nginx/nginx.conf /etc/nginx/conf/nginx.conf
rm -f /etc/nginx/conf.d/dev.conf

# Create required folders
mkdir -p /tmp/nginx/body \
/run/nginx \
/data/nginx \
/data/custom_ssl \
/data/logs \
/data/access \
/data/nginx/default_host \
/data/nginx/default_www \
/data/nginx/proxy_host \
/data/nginx/redirection_host \
/data/nginx/stream \
/data/nginx/dead_host \
/data/nginx/temp \
/var/lib/nginx/cache/public \
/var/lib/nginx/cache/private \
/var/cache/nginx/proxy_temp

chmod -R 777 /var/cache/nginx
chown root /tmp/nginx

# Dynamically generate resolvers file, if resolver is IPv6, enclose in `[]`
# thanks @tfmm
echo resolver "$(awk 'BEGIN{ORS=" "} $1=="nameserver" {print ($2 ~ ":")? "["$2"]": $2}' /etc/resolv.conf);" > /etc/nginx/conf.d/include/resolvers.conf

# Generate dummy self-signed certificate.
if [ ! -f /data/nginx/dummycert.pem ] || [ ! -f /data/nginx/dummykey.pem ]; then
  log "Generating dummy SSL certificate"
  runcmd 'openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -subj "/O=Nginx Proxy Manager/OU=Dummy Certificate/CN=localhost" -keyout /data/nginx/dummykey.pem -out /data/nginx/dummycert.pem'
fi

# Copy app files
mkdir -p /app/global /app/frontend/images
cp -r backend/* /app
cp -r global/* /app/global

# Build the frontend
log "Building frontend"
cd ./frontend
export NODE_ENV=development
runcmd yarn install --network-timeout=30000
runcmd yarn build
cp -r dist/* /app/frontend
cp -r app-images/* /app/frontend/images

# Initialize backend
log "Initializing backend"
rm -rf /app/config/default.json &>/dev/null
if [ ! -f /app/config/production.json ]; then
cat << 'EOF' > /app/config/production.json
{
  "database": {
    "engine": "knex-native",
    "knex": {
      "client": "sqlite3",
      "connection": {
        "filename": "/data/database.sqlite"
      }
    }
  }
}
EOF
fi
cd /app
export NODE_ENV=development
runcmd yarn install --network-timeout=30000

# Create NPM service
log "Creating NPM service"
cat << 'EOF' > /lib/systemd/system/npm.service
[Unit]
Description=Nginx Proxy Manager
After=network.target
Wants=openresty.service

[Service]
Type=simple
Environment=NODE_ENV=production
ExecStartPre=-mkdir -p /tmp/nginx/body /data/letsencrypt-acme-challenge
ExecStart=/usr/bin/node index.js --abort_on_uncaught_exception --max_old_space_size=250
WorkingDirectory=/app
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable npm

# Start services
log "Starting services"
runcmd systemctl start openresty
runcmd systemctl start npm

IP=$(ip a s dev eth0 | sed -n '/inet / s/\// /p' | awk '{print $2}')
log "Installation complete

\e[0mNginx Proxy Manager should be reachable at the following URL.

      http://${IP}:81
"
