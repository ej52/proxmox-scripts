#!/usr/bin/env sh
export EPS_BASE_URL=https://raw.githubusercontent.com/ej52/proxmox-scripts/main
export EPS_CT_INSTALL=false

export EPS_UTILS=$(wget --no-cache -qO- $EPS_BASE_URL/utils/common.sh)
source <(echo -n "$EPS_UTILS")

while [ "$#" -gt 0 ]; do
  case $1 in
    --app) 
      EPS_APP_NAME="$2"
      shift;;
    --cleanup)
      EPS_CLEANUP=true
      ;;
    *)
      log "error" "Unrecognized option: ${CLR_CYB}$1${CLR}" "" 1;;
  esac
  shift
done

EPS_APP_NAME=${EPS_APP_NAME:-}
export EPS_CLEANUP=${EPS_CLEANUP:-false}

if [ -z "$EPS_APP_NAME" ]; then
  log "error" "No application provided" "" 1
fi

export EPS_APP_CONFIG=$(wget --no-cache -qO- $EPS_BASE_URL/apps/$EPS_APP_NAME/config.sh)
if [ $? -gt 0 ]; then
  log "error" "No config found for ${CLR_CYB}$EPS_APP_NAME${CLR}" "" 1
fi

EPS_APP_INSTALL=$(wget --no-cache -qO- $EPS_BASE_URL/apps/$EPS_APP_NAME/install.sh)
if [ $? -gt 0 ]; then
  log "error" "No install script found for ${CLR_CYB}$EPS_APP_NAME${CLR}" "" 1
fi

EPS_OS_NAME=$(os_name)
export EPS_OS_DISTRO=$(os_distro)

source <(echo -n "$EPS_APP_CONFIG")
pms_header
pms_check_os

if [ "$EPS_OS_DISTRO" = "alpine" ]; then
  [ "$(command -v bash)" ] || apk add bash >/dev/null
fi

trap - ERR
bash -c "$EPS_APP_INSTALL"

