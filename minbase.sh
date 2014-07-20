#!/bin/bash

if [[ ! `whoami` == root ]]; then
    echo "Need to be root."
    exit 1
fi

set -x -e

DIR='./container'
mkdir -p $DIR

debootstrap --arch=amd64 --variant=minbase jessie $DIR http://mirrors.163.com/debian
systemd-nspawn -D $DIR bash -c 'set -e; echo "export DEBIAN_FRONTEND=noninteractive" >> /etc/profile; echo -e "APT::Get::Assume-Yes \"true\";\nAPT::Get::force-yes \"true\";\nquiet 1;" >> /etc/apt/apt.conf.d/11forceyes; apt-get update; apt-get install --fix-missing procps; apt-get clean'

TAR='meeci-minbase.tgz'
tar -C $DIR -zcf $TAR .
rm -rf $DIR
chmod 644 $TAR

set +x

echo "Created $TAR"
ls -lh $TAR
