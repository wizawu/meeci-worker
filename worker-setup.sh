#!/bin/bash

if [[ `whoami` != root ]]; then
    echo "Need to be root."
    exit 1
fi

set -x -e

apt-get install -y --no-install-recommends \
                luajit lua-socket git wget wput systemd

if [[ ! `cat /proc/1/comm` == systemd ]]; then
    echo "Reboot the system with systemd and re-run this setup."
    exit 2
fi

mkdir -p /var/lib/meeci/worker/logs/build
mkdir -p /var/lib/meeci/worker/logs/container

chmod a+x ./worker.lua

set +x

echo "Now you can start the worker with: sudo MEECI_HOST=192.168.0.1 ./worker.lua"
echo "Replace the IP address above with the actual one."
