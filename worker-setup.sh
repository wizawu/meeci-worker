#!/bin/bash

set -e

if [[ `whoami` != "root" ]]; then
    echo "Must run $0 as root"
    exit 1
fi

# step 1: install dependencies
apt-get install -y --no-install-recommends \
                lua5.2 lua-socket systemd wget wput

# step 2: 
if [[ ! `cat /proc/1/comm` == systemd ]]; then
    echo "Reboot the system with systemd and re-run this setup"
    exit 2
fi

# step 3: create directories
mkdir -p /var/lib/meeci/worker/container/logs
mkdir -p /var/lib/meeci/worker/build/logs

echo "$0 exited without errors"
exit 0
