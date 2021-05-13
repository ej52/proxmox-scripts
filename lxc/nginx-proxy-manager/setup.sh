#!/usr/bin/env sh
set -euo pipefail
trap 'rm -rf $TMP' EXIT SIGINT SIGTERM

TMP=/tmp/npm_install.sh
URL=https://raw.githubusercontent.com/ej52/proxmox/main/lxc/nginx-proxy-manager/install.sh

rm -rf $TMP
wget -q -O "$TMP" "$URL"

chmod +x "$TMP"
sh "$TMP"

