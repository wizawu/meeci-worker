#!/bin/bash

set -e

if [[ `whoami` != 'root' ]]; then
    echo 'Must be run as root.'
    exit 1
fi

apt-get install -y systemd

grub='/etc/default/grub'
regexp='GRUB_CMDLINE_LINUX_DEFAULT=".*init=/lib/systemd/systemd.*"'

if [[ -z `grep -x $regexp $grub` ]]; then
    echo -ne '\nModify' $grub 'line '
    echo `grep -n GRUB_CMDLINE_LINUX_DEFAULT $grub`
    echo -n to: `grep GRUB_CMDLINE_LINUX_DEFAULT $grub`
    echo -e '\b init=/lib/systemd/systemd"'
    echo -n 'with editor(nano, vi, ...): '
    read editor
    $editor $grub
fi

echo -n 'Reboot now? (Y/n) '
read -N 1 rb

case $rb in
    Y ) echo reboot;;
    * ) echo -e '\nPlease reboot later.'
esac

exit 0
