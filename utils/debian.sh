#!/usr/bin/env bash
os_arch() {
  printf $(dpkg --print-architecture)
}

os_codename() {
  printf $(awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release)
}

os_version() {
  printf $(awk -F'=' '/^VERSION_ID=/{ print $NF }' /etc/os-release)
}

pkg_update() {
  apt-get -y -qq update >$__OUTPUT
}

pkg_upgrade() {
   apt-get -y -qq upgrade >$__OUTPUT
}

pkg_add() {
  apt-get -y -qq --no-install-recommends install $@ >$__OUTPUT
}

pkg_del() {
  apt-get -y -qq purge $@ >$__OUTPUT
}

pkg_clean() {
  apt-get -y -qq autoremove >$__OUTPUT
  apt-get clean >$__OUTPUT
}

svc_add() {
  systemctl daemon-reload >$__OUTPUT
  systemctl stop $@ &>$__OUTPUT
  sleep 2
  systemctl enable --now $@ >$__OUTPUT
}

svc_start() {
  systemctl start $@ >$__OUTPUT
}

svc_stop() {
  systemctl stop $@ >$__OUTPUT
}