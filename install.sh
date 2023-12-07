#!/usr/bin/env sh
export EPS_BASE_URL=${EPS_BASE_URL:-https://raw.githubusercontent.com/ej52/proxmox-scripts/main}
export EPS_CT_INSTALL=false

CLR_RD="\033[0;31m"
CLR_RDB="\033[1;31m"
CLR_CYB="\033[1;36m"
CLR="\033[m"

log_error () {
  printf "${CLR_RDB}✘ ${CLR_RD}$1${CLR}\n"
  exit 1
}

while [ "$#" -gt 0 ]; do
  case $1 in
    --app) 
      EPS_APP_NAME="$2"
      shift;;
    --cleanup)
      EPS_CLEANUP=true
      ;;
    *)
      log_error "Unrecognized option: ${CLR_CYB}$1${CLR}";;
  esac
  shift
done

EPS_APP_NAME=${EPS_APP_NAME:-}
export EPS_CLEANUP=${EPS_CLEANUP:-false}

if [ -z "$EPS_APP_NAME" ]; then
  log_error "No application provided"
fi

export EPS_APP_CONFIG=$(wget --no-cache -qO- $EPS_BASE_URL/apps/$EPS_APP_NAME/config.sh)
if [ $? -gt 0 ]; then
  log_error "No config found for ${CLR_CYB}$EPS_APP_NAME${CLR}"
fi

EPS_APP_INSTALL=$(wget --no-cache -qO- $EPS_BASE_URL/apps/$EPS_APP_NAME/install.sh)
if [ $? -gt 0 ]; then
  log_error "No install script found for ${CLR_CYB}$EPS_APP_NAME${CLR}"
fi

export EPS_OS_NAME=$(uname)
export EPS_OS_DISTRO=$(awk -F'=' '/^ID=/{ print $NF }' /etc/os-release)

if [ "$EPS_OS_NAME" != "Linux" ]; then
  log_error "OS not supported: ${CLR_CYB}$EPS_OS_NAME${CLR}"
fi

if [ "$EPS_OS_DISTRO" = "alpine" ]; then
  [ "$(command -v bash)" ] || apk add bash >/dev/null
fi

_utilDistro=$EPS_OS_DISTRO
if [ "$EPS_OS_DISTRO" = "ubuntu" ]; then
  _utilDistro="debian"
fi

export EPS_UTILS_COMMON=$(wget --no-cache -qO- $EPS_BASE_URL/utils/common.sh)
export EPS_UTILS_DISTRO=$(wget --no-cache -qO- $EPS_BASE_URL/utils/${_utilDistro}.sh)
bash -c "$EPS_APP_INSTALL"

