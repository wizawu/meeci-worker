#!/bin/bash

set -e

if [[ `whoami` != "root" ]]; then
    echo "Must run $0 as root"
    exit 1
fi

# step 1: install dependencies
apt-get install -y --no-install-recommends systemd nodejs

# step 2: 
if [[ ! `cat /proc/1/comm` == systemd ]]; then
    echo "Reboot the system with systemd"
    exit 2
fi

# step 3: create directories
mkdir -p /var/lib/meeci/worker/container/logs
mkdir -p /var/lib/meeci/worker/build/logs

echo "Exit without errors"
exit 0
