#!/usr/bin/env bash

set -e
buildlog="$(mktemp)"
echo -n "Building containers..."

duration="${1}"

build_error() {
  cat "${buildlog}"
  exit 1
}

docker compose build --progress=plain >"${buildlog}" 2>&1 || build_error

echo " done"

TERM=xterm-256color time docker compose up --abort-on-container-exit &

if [[ -n "${duration}" ]]; then
  sleep "${duration}"

  docker compose --progress=plain down
fi
