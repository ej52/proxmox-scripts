#!/usr/bin/env bash

pms_header() {
  clear
  cat <<"EOF"
    _   __      _               ____                           __  ___                                 
   / | / /___ _(_)___  _  __   / __ \_________ __  ____  __   /  |/  /___ _____  ____ _____ ____  _____
  /  |/ / __  / / __ \| |/_/  / /_/ / ___/ __ \| |/_/ / / /  / /|_/ / __  / __ \/ __  / __  / _ \/ ___/
 / /|  / /_/ / / / / />  <   / ____/ /  / /_/ />  </ /_/ /  / /  / / /_/ / / / / /_/ / /_/ /  __/ /    
/_/ |_/\__, /_/_/ /_/_/|_|  /_/   /_/   \____/_/|_|\__, /  /_/  /_/\__,_/_/ /_/\__,_/\__, /\___/_/     
      /____/                                      /____/                            /____/             
 
EOF
}

EPS_SUPPORTED_DISTROS="alpine debian ubuntu"
# Override default CT settings
EPS_CT_CPU_CORES=${EPS_CT_CPU_CORES:-1}
EPS_CT_DISK_SIZE=${EPS_CT_DISK_SIZE:-4}
EPS_CT_MEMORY=${EPS_CT_MEMORY:-512}
EPS_CT_SWAP=${EPS_CT_SWAP:-0}
# NPM package versions
NODE_VERSION="v16.20.2"
YARN_VERSION="1.22.19"
RUST_VERSION="1.76.0"

EPS_SERVICE_FILE=/etc/init.d/npm
EPS_SERVICE_DATA="#!/sbin/openrc-run\ndescription=\"Nginx Proxy Manager\"\n\ncommand=\"/usr/local/bin/node\"\ncommand_args=\"index.js --abort_on_uncaught_exception --max_old_space_size=250\"\ncommand_background=\"yes\"\ndirectory=\"/app\"\n\npidfile=\"/var/run/npm.pid\"\noutput_log=\"/var/log/npm.log\"\nerror_log=\"/var/log/npm.err\"\n\ndepends () {\n  before openresty\n}\n\nstart_pre() {\n  mkdir -p /tmp/nginx/body /data/letsencrypt-acme-challenge\n  export NODE_ENV=production\n}\n\nstop() {\n  pkill -9 -f node\n  return 0\n}\n\nrestart() {\n  \$0 stop\n  \$0 start\n}"
EPS_DEPENDENCIES="gcc g++ make musl-dev openssl-dev git libffi-dev python3-dev"

if [ "$EPS_OS_DISTRO" = "debian" -o "$EPS_OS_DISTRO" = "ubuntu" ]; then
  EPS_SERVICE_FILE=/lib/systemd/system/npm.service
  EPS_SERVICE_DATA="[Unit]\nDescription=Nginx Proxy Manager\nAfter=network.target\nWants=openresty.service\n\n[Service]\nType=simple\nEnvironment=NODE_ENV=production\nExecStartPre=-/bin/mkdir -p /tmp/nginx/body /data/letsencrypt-acme-challenge\nExecStart=/usr/local/bin/node index.js --abort_on_uncaught_exception --max_old_space_size=250\nWorkingDirectory=/app\nRestart=on-failure\n\n[Install]\nWantedBy=multi-user.target"
  EPS_DEPENDENCIES="build-essential libssl-dev git libffi-dev python3-dev"
fi

lxc_checks() {
  if [ "$EPS_CT_DISK_SIZE" -lt 4 ]; then
    log "warn" "This LXC container requires at least 4GB of disk space" 1
  fi
}
