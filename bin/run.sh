#!/usr/bin/env bash

echo -n "Building containers..."
docker compose build --progress=plain >/dev/null 2>&1
echo " done"
time docker compose up --abort-on-container-exit
