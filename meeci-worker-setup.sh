#!/bin/bash

set -e

if [[ `whoami` != "root" ]]; then
    echo "Must be run as root."
    exit 1
fi

apt-get install -y \
                systemd \
                libmemcached-dev \
                libsystemd-daemon-dev

grub="/etc/default/grub"
opt="GRUB_CMDLINE_LINUX_DEFAULT"
regex="GRUB_CMDLINE_LINUX_DEFAULT=\".*init=/lib/systemd/systemd.*\""

if [[ -z `grep -x $regex $grub` ]]; then
    echo -ne "\nModify" $grub "line "
    echo `grep -n $opt $grub`
    echo -n to: `grep $opt $grub`
    echo -e "\b init=/lib/systemd/systemd\""
    echo -n "with editor(nano, vi, ...): "
    read editor
    $editor $grub
fi

echo -n "Reboot now? (Y/n) "
read -N 1 ans

case $ans in
    Y ) echo reboot;;
    * ) echo -e "\nPlease reboot later."
esac

exit 0
