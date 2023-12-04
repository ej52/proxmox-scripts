# Color variables
CLR_RD="\033[0;31m"
CLR_RDB="\033[1;31m"
CLR_GN="\033[0;32m"
CLR_GNB="\033[1;32m"
CLR_YL="\033[0;33m"
CLR_YLB="\033[1;33m"
CLR_CY="\033[0;36m"
CLR_CYB="\033[1;36m"
CLR="\033[m"

# Helper variables
__OUTPUT=/dev/null
__SPIN_PID=0
__LAST_LINE=0
__STEP_NAME=""
__STEP_BUSY=""
__STEP_DONE=""

os_name() {
  printf $(uname)
}

os_distro() {
  printf $(awk -F'=' '/^ID=/{ print $NF }' /etc/os-release)
}

os_fetch() {
  wget -t 3 -T 30 -q $@
}

os_ip() {
  printf $(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1)
}

pms_bootstrap() {
  set -Eeuo pipefail

  stty -echo
  printf "\033[?25l"

  if [ "$EPS_CT_INSTALL" = false ]; then
    TEMP_DIR=$(mktemp -d)
    pushd $TEMP_DIR >$__OUTPUT
  fi
}

pms_header() {
  log "info" "${EPS_APP_NAME:-Unknown}\n"
}

pms_check_os() {
  local _os=${1:-$EPS_OS_NAME}
  local _distro=${2:-$EPS_OS_DISTRO}
  local _supported=false

  if [ "$_os" != "Linux" ]; then
    log "error" "OS not supported: ${CLR_CYB}$_os${CLR}" "" 1
  fi

  for d in $EPS_SUPPORTED_DISTROS; do
    if [ "$d" = "$_distro" ]; then
      _supported=true
      break;
    fi
  done

  if [ "$_supported" = false ]; then
    log "error" "OS distribution not supported: ${CLR_CYB}$_distro${CLR}\n\n${CLR_YL}Supported distributions:${CLR} ${CLR_YLB}$EPS_SUPPORTED_DISTROS${CLR}" "" 1
  fi
}

pms_settraps() {
  trap '__trap_error ${BASH_LINENO:-"$LINENO"} ${FUNCNAME:-"$BASH_COMMAND"}' ERR 
  trap __trap_interrupt SIGHUP SIGINT SIGQUIT
  trap __trap_exit EXIT
}

pms_cleartraps() {
  trap - EXIT ERR SIGHUP SIGINT SIGQUIT
}

log () {
  local type=${1:-"info"}
  local message="$2"
  local clear=${3:-}
  local exit_code=${4:-0}

  case $type in
    info)
      printf "${clear}${CLR_CYB}ℹ ${CLR_CY}${message}${CLR}\n";;
    success)
      printf "${clear}${CLR_GNB}✔ ${CLR_GN}${message}${CLR}\n";;
    warn)
      printf "${clear}${CLR_YLB}! ${CLR_YL}${message}${CLR}\n";;
    error)
      printf "${clear}${CLR_RDB}✘ ${CLR_RD}${message}${CLR}\n";;
    *)
      ;;
  esac

  if [ $exit_code -gt 0 ]; then
    exit $exit_code
  fi
}

step_start() {
  step_end

  __STEP_NAME=${1:-}
  __STEP_BUSY=${2:-${__STEP_BUSY}}
  __STEP_DONE=${3:-${__STEP_DONE}}
  __LAST_LINE=$(__row)

  log "info" "${__STEP_BUSY} ${__STEP_NAME}"
  __start_spinner &

  __SPIN_PID=$!
  disown
}

step_end() {
  __stop_spinner
  if [ -z "$__STEP_NAME" ]; then
    return 0
  fi

  local message=${1:-}
  local exit_code=${2:-0}

  if [ -z "$message" ]; then
    message="$__STEP_NAME $__STEP_DONE"
    if [ "$exit_code" -gt 0 ]; then
      message="$__STEP_NAME not $__STEP_DONE"
    fi
  fi

  if [ "$exit_code" -gt 0 ]; then
    log "error" "$message ${CLR_RD}" $(__clr)
    exit $exit_code
  else
    log "success" "$message ${CLR_GN}" $(__clr)
  fi

  __STEP_NAME=""
  __LAST_LINE=0
}

__start_spinner() {
  local marks="⁘ ⁙"

  while :; do
    for mark in $marks; do
      printf "$(__clr '1K')${CLR_CYB}$mark${CLR}\n"
      sleep 0.35
    done
  done
}

__stop_spinner() {
  if [ "$__SPIN_PID" -gt 0 ]; then
    kill $__SPIN_PID &>$__OUTPUT
    __SPIN_PID=0
  fi
}

__row() {
  local COL
  local ROW
  IFS=';' read -sdR -p $'\E[6n' ROW COL
  printf "${ROW#*[}"
}

__clr() {
  __LAST_LINE=${__LAST_LINE:-$(__row)}
  local end=${1:-"0J"}
  local row=${2:-$__LAST_LINE}
  local col=${3:-1}

  printf "\r\033[${row};${col}H\033[${end}"
}

__trap_exit() {
  trap - ERR

  __stop_spinner &>$__OUTPUT

  if [ "$EPS_CT_INSTALL" = false ]; then
    popd &>$__OUTPUT
    rm -rf $TEMP_DIR &>$__OUTPUT
  fi
  
  printf "\033[?25h"
  stty sane
}

__trap_interrupt()  {
  local exit_code="$?"
  trap - ERR
  stty sane
  printf "\033[?25h"

  [ -z "$__STEP_NAME" ] || log "warn" "$__STEP_NAME ${CLR_YL}not completely $__STEP_DONE${CLR}" $(__clr)
  printf "\n${CLR_YLB}[TERMINATED]${CLR} process terminated with exit code ${CLR_YLB}$exit_code${CLR}\n"
}

__trap_error() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local row=$(__row)

  [ -z "$__STEP_NAME" ] || log "error" "$__STEP_NAME ${CLR_RD}not $__STEP_DONE" $(__clr 'K')
  printf "$(__clr '' $row)\n${CLR_RDB}[ERROR]${CLR} on line ${CLR_RDB}$line_number${CLR} with exit code ${CLR_RDB}$exit_code${CLR} while executing command ${CLR_YLB}$command${CLR}\n"
}
