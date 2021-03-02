#!/usr/bin/env sh
set -e

# Helpers
function info { echo -e "\e[32m[info] $*\e[39m"; }

_temp_dir=$(mktemp -d)
cd $_temp_dir

. /etc/os-release
_alpine_version=${VERSION_ID%.*}
_npm_url="https://github.com/jc21/nginx-proxy-manager"

# add openresty repo
if [ ! -f /etc/apk/keys/admin@openresty.com-5ea678a6.rsa.pub ]; then
  wget -q -P /etc/apk/keys/ 'http://openresty.org/package/admin@openresty.com-5ea678a6.rsa.pub' &>/dev/null
  echo "http://openresty.org/package/alpine/v$_alpine_version/main" >> /etc/apk/repositories
fi
  
# Update container OS
info "Updating container OS..."
apk update >/dev/null
apk upgrade &>/dev/null

echo "fs.file-max = 65535" > /etc/sysctl.conf

# Install prerequisites
info "Installing prerequisites..."
apk add python3 git certbot jq openresty nodejs npm yarn openssl apache2-utils &>/dev/null
python3 -m ensurepip &>/dev/null

if [ -f /etc/init.d/npm ]; then
  info "Stoping services..."
  rc-service npm stop &>/dev/null
  rc-service openresty stop &>/dev/null
  sleep 2

  info "Cleaning old files..."
  # Cleanup for new install
  rm -rf /app \
  /var/www/html \
  /etc/nginx \
  /var/log/nginx \
  /var/lib/nginx \
  /var/cache/nginx &>/dev/null
fi

# Get latest version information for nginx-proxy-manager
_latest_release=$(wget "$_npm_url/releases/latest" -q -O - | grep -wo "jc21/.*.tar.gz")
_latest_version=$(basename $_latest_release .tar.gz)
_latest_version=${_latest_version#v*}

# Download nginx-proxy-manager source
info "Downloading NPM v$_latest_version..."
wget -qc $_npm_url/archive/v$_latest_version.tar.gz -O - | tar -xz

cd nginx-proxy-manager-$_latest_version

# Copy runtime files
_rootfs=docker/rootfs
mkdir -p /var/www/html && cp -r $_rootfs/var/www/html/* /var/www/html
mkdir -p /etc/nginx/logs && cp -r $_rootfs/etc/nginx/* /etc/nginx
rm -f /etc/nginx/conf.d/dev.conf
cp $_rootfs/etc/letsencrypt.ini /etc/letsencrypt.ini

# Update NPM version in package.json files
echo "`jq --arg _latest_version $_latest_version '.version=$_latest_version' backend/package.json`" > backend/package.json
echo "`jq --arg _latest_version $_latest_version '.version=$_latest_version' frontend/package.json`" > frontend/package.json

# Create required folders
mkdir -p /tmp/nginx/body \
/run/nginx \
/var/log/nginx \
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

touch /var/log/nginx/error.log && chmod 777 /var/log/nginx/error.log && chmod -R 777 /var/cache/nginx
chown root /tmp/nginx

# Dynamically generate resolvers file, if resolver is IPv6, enclose in `[]`
# thanks @tfmm
echo resolver "$(awk 'BEGIN{ORS=" "} $1=="nameserver" {print ($2 ~ ":")? "["$2"]": $2}' /etc/resolv.conf);" > /etc/nginx/conf.d/include/resolvers.conf

# Generate dummy self-signed certificate.
if [ ! -f /data/nginx/dummycert.pem ] || [ ! -f /data/nginx/dummykey.pem ]
then
  info "Generating dummy SSL certificate..."
  openssl req \
    -new \
    -newkey rsa:2048 \
    -days 3650 \
    -nodes \
    -x509 \
    -subj '/O=Nginx Proxy Manager/OU=Dummy Certificate/CN=localhost' \
    -keyout /data/nginx/dummykey.pem \
    -out /data/nginx/dummycert.pem &>/dev/null
fi

# Copy app files
mkdir -p /app/global
cp -r backend/* /app
cp -r global/* /app/global

# Build the frontend
info "Building frontend..."
mkdir -p /app/frontend/images
cd frontend
yarn install &>/dev/null
yarn build &>/dev/null
cp -r dist/* /app/frontend
cp -r app-images/* /app/frontend/images

cd /app
info "Initalizing backend..."
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
yarn install &>/dev/null

# Run setup
export NODE_ENV=production
node index.js &>/dev/null

# Create required folders
mkdir -p /data

# Update openresty config
info "Configuring openresty..."
cat << 'EOF' > /etc/conf.d/openresty
# Configuration for /etc/init.d/openresty

cfgfile=/etc/nginx/nginx.conf
app_prefix=/etc/nginx
EOF
rc-update add openresty boot &>/dev/null
rc-service openresty stop &>/dev/null

[ -f /usr/sbin/nginx ] && rm /usr/sbin/nginx
ln -s /usr/local/openresty/nginx/sbin/nginx /usr/sbin/nginx

# Create NPM service
info "Creating NPM service..."
cat << 'EOF' > /etc/init.d/npm
#!/sbin/openrc-run
description="Nginx Proxy Manager"

command="/usr/bin/node" 
command_args="index.js --abort_on_uncaught_exception --max_old_space_size=250"
command_background="yes"
directory="/app"

pidfile="/var/run/npm.pid"
output_log="/var/log/npm.log"
error_log="/var/log/npm.err"

depends () {
  before openresty
}

start_pre() {
  mkdir -p /tmp/nginx/body \
  /data/letsencrypt-acme-challenge

  export NODE_ENV=production
  udhcpc -x hostname:$HOSTNAME
}

stop() {
  pkill -9 -f node
  return 0
}

restart() {
  $0 stop
  $0 start
}
EOF
chmod a+x /etc/init.d/npm
rc-update add npm boot &>/dev/null

# Start services
info "Starting services..."
rc-service npm start &>/dev/null
rc-service openresty start &>/dev/null

# Cleanup
info "Cleaning up..."
rm -rf $_temp_dir/nginx-proxy-manager-${_latest_version} &>/dev/null
apk del git jq npm &>/dev/null
