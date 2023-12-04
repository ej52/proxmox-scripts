#!/usr/bin/env bash
export EPS_BASE_URL=https://raw.githubusercontent.com/ej52/proxmox-scripts/main
export EPS_CT_INSTALL=true

export EPS_UTILS=$(wget --no-cache -qO- $EPS_BASE_URL/utils/common.sh)
source <(echo -n "$EPS_UTILS")
pms_bootstrap
pms_settraps

while [ "$#" -gt 0 ]; do
  case $1 in
    --app) 
      EPS_APP_NAME=$2
      shift;;
    --id)
      EPS_CT_ID=$2
      shift;;
    --os)
      EPS_OS_DISTRO=$2;
      shift;;
    --os-version)
      EPS_OS_VERSION=$2;
      shift;;
    --bridge)
      EPS_CT_NETWORK_BRIDGE=$2
      shift;;
    --cores)
      EPS_CT_CPU_CORES=$2
      shift;;
    --disksize)
      EPS_CT_DISK_SIZE=$2
      shift;;
    --hostname)
      EPS_CT_HOSTNAME=$2
      shift;;
    --memory)
      EPS_CT_MEMORY=$2
      shift;;
    --storage)
      EPS_CT_STORAGE_CONTAINER=$2
      shift;;
    --templates)
      EPS_CT_STORAGE_TEMPLATES=$2
      shift;;
    --swap)
      EPS_CT_SWAP=$2
      shift;;
    --cleanup) 
      EPS_CLEANUP=true;;
    *)
      log "error" "Unrecognized option: ${CLR_CYB}$1${CLR}" "" 1;;
  esac
  shift
done

EPS_APP_NAME=${EPS_APP_NAME:-}
if [ -z "$EPS_APP_NAME" ]; then
  log "error" "No application provided" "" 1
fi

export EPS_APP_CONFIG=$(wget --no-cache -qO- $EPS_BASE_URL/apps/$EPS_APP_NAME/config.sh)
if [ $? -gt 0 ]; then
  log "error" "Application config not found for ${CLR_CYB}$EPS_APP_NAME${CLR}" "" 1
fi

EPS_APP_INSTALL=$(wget --no-cache -qO- $EPS_BASE_URL/apps/$EPS_APP_NAME/install.sh)
if [ $? -gt 0 ]; then
  log "error" "No install script found for ${CLR_CYB}$EPS_APP_NAME${CLR}" "" 1
fi

EPS_CT_ID=${EPS_CT_ID:-$(pvesh get /cluster/nextid)}
EPS_CT_HOSTNAME=${EPS_CT_HOSTNAME:-${EPS_APP_NAME}}
EPS_CT_NETWORK_BRIDGE=${EPS_CT_NETWORK_BRIDGE:-vmbr0}
EPS_CT_STORAGE_CONTAINER=${EPS_CT_STORAGE_CONTAINER:-local-lvm}
EPS_CT_STORAGE_TEMPLATES=${EPS_CT_STORAGE_TEMPLATES:-local}
export EPS_OS_DISTRO=${EPS_OS_DISTRO:-alpine}
EPS_OS_VERSION=${EPS_OS_VERSION:-}
export EPS_CLEANUP=${EPS_CLEANUP:-false}
EPS_CT_CPU_CORES=${EPS_CT_CPU_CORES:-1}
EPS_CT_DISK_SIZE=${EPS_CT_DISK_SIZE:-4}
EPS_CT_MEMORY=${EPS_CT_MEMORY:-512}
EPS_CT_SWAP=${EPS_CT_SWAP:-0}

[ "$EPS_CT_ID" -ge 100 ] || log "error" "ID cannot be less than 100" "" 1
if pct status $EPS_CT_ID &>$__OUTPUT; then
  log "error" "ID is already in use: ${CLR_CYB}$EPS_CT_ID${CLR}" "" 1
fi

source <(echo -n "$EPS_APP_CONFIG")
pms_header

EPS_OS_NAME=$(os_name)
pms_check_os

[ "$EPS_CT_DISK_SIZE" -ge 0 ] 2>$__OUTPUT || log "error" "Disk Size should be a vaild integer" "" 1
lxc_checks

log "info" "Container will be created using the following settings.

  Application:          ${CLR_CYB}$EPS_APP_NAME${CLR_CY}
  OS Distribution:      ${CLR_CYB}$EPS_OS_DISTRO${CLR_CY}
  OS Version:           ${CLR_CYB}${EPS_OS_VERSION:-latest}${CLR_CY}
  Container ID:         ${CLR_CYB}$EPS_CT_ID${CLR_CY}
  Container Hostname:   ${CLR_CYB}$EPS_CT_HOSTNAME${CLR_CY}
  Allocated Cores:      ${CLR_CYB}$EPS_CT_CPU_CORES${CLR_CY}
  Allocated Memory:     ${CLR_CYB}$EPS_CT_MEMORY${CLR_CY}
  Allocated Swap:       ${CLR_CYB}$EPS_CT_SWAP${CLR_CY}
  Allocated Disk Size:  ${CLR_CYB}$EPS_CT_DISK_SIZE${CLR_CY}
  Network Bridge:       ${CLR_CYB}$EPS_CT_NETWORK_BRIDGE${CLR_CY}
  Container Storage:    ${CLR_CYB}$EPS_CT_STORAGE_CONTAINER${CLR_CY}
  Template Storage:     ${CLR_CYB}$EPS_CT_STORAGE_TEMPLATES${CLR_CY}
  Script Cleanup:       ${CLR_CYB}$EPS_CLEANUP${CLR_CY}

${CLR_YLB}If you want to abort, hit ctrl+c within 10 seconds...${CLR}"
sleep 10
pms_header

step_start "LXC templates" "Checking" "OK"
  _template=""

  _templates_downloaded=($(pveam list $EPS_CT_STORAGE_TEMPLATES | grep -Eo "$EPS_OS_DISTRO.*\.(gz|xz|zst)" || true))
  if [ ${#_templates_downloaded[@]} -gt 0 ]; then
    for t in ${_templates_downloaded[*]}; do
      if [ "${t%\-*}" = "$EPS_OS_DISTRO-$EPS_OS_VERSION" ]; then
        _template=$t
        break;
      fi
    done
  fi

  if [ -z $_template ]; then
    pveam update &>$__OUTPUT

    _templates_available=($(pveam available -section system | grep -Eo "$EPS_OS_DISTRO.*\.(gz|xz|zst)" | sort -r -t - -k 2 -V))
    if [ ${#_templates_available[@]} -gt 0 ]; then
      if [ -z $EPS_OS_VERSION ]; then
        _template=${_templates_available[0]}
      else
        for t in ${_templates_available[*]}; do
          if [ "${t%\-*}" = "$EPS_OS_DISTRO-$EPS_OS_VERSION" ]; then
            _template=$t
            break;
          fi
        done
      fi

      if [[ ! "${_templates_downloaded[*]}" =~ "$_template" ]]; then
        log "info" "Downloading LXC template: ${CLR_CYB}$_template${CLR}" $(__clr)
        sleep 3
        pveam download $EPS_CT_STORAGE_TEMPLATES $_template >$__OUTPUT
      fi
    fi
  else
    sleep 3
  fi

  if [ -z $_template ]; then
    step_end "LXC template not found for: ${CLR_CYB}${EPS_OS_DISTRO}:${EPS_OS_VERSION:-latest}${CLR}" 1
  fi

  step_end "Using LXC template: ${CLR_CYB}${_template}${CLR}"

step_start "LXC container" "Creating" "Created"
  _storage_type=$(pvesm status -storage $EPS_CT_STORAGE_CONTAINER >$__OUTPUT | awk 'NR>1 {print $2}')
  if [ "$_storage_type" = "zfspool" ]; then
    log "warn" "Some containers may not work properly due to ZFS not supporting 'fallocate'."
    sleep 3
  fi
  
  _pct_options=(
    -arch $(dpkg --print-architecture)
    -cmode shell
    -hostname $EPS_CT_HOSTNAME
    -cores $EPS_CT_CPU_CORES
    -memory $EPS_CT_MEMORY
    -net0 name=eth0,bridge=$EPS_CT_NETWORK_BRIDGE,ip=dhcp
    -onboot 1
    -ostype $EPS_OS_DISTRO
    -rootfs $EPS_CT_STORAGE_CONTAINER:${EPS_CT_DISK_SIZE:-4}
    -swap $EPS_CT_SWAP
    -tags $EPS_APP_NAME
  )
  pct create $EPS_CT_ID "$EPS_CT_STORAGE_TEMPLATES:vztmpl/$_template" ${_pct_options[@]} >$__OUTPUT
  pct start $EPS_CT_ID
  sleep 2
  if [ "$EPS_OS_DISTRO" = "alpine" ]; then
    pct exec "$EPS_CT_ID" -- ash -c "apk add bash >/dev/null"
  fi

  step_end "LXC container ${CLR_CYB}$EPS_CT_ID${CLR_GN} created successfully"

trap - ERR
lxc-attach -n $EPS_CT_ID -- bash -c "$EPS_APP_INSTALL"