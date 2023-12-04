#!/usr/bin/env bash
os_arch() {
  printf $(apk --print-arch)
}

os_codename() {
  printf $(os_version)
}

os_version() {
  VERSION_ID=$(awk -F'=' '/^VERSION_ID=/{ print $NF }' /etc/os-release)
  printf ${VERSION_ID%.*}
}

pkg_update() {
  apk update -q >$__OUTPUT
}

pkg_upgrade() {
  apk upgrade -q >$__OUTPUT
}

pkg_add() {
  apk add -q -u $@ >$__OUTPUT
}

pkg_del() {
  apk del -q --purge $@ >$__OUTPUT
}

pkg_clean() {
  rm -rf /var/cache/apk/* >$__OUTPUT
}

svc_add() {
  rc-update add $@ boot >$__OUTPUT
  rc-service $@ stop &>$__OUTPUT
  sleep 2
  rc-service $@ start >$__OUTPUT
}

svc_start() {
  rc-service $@ start >$__OUTPUT
}

svc_stop() {
  rc-service $@ stop >$__OUTPUT
}