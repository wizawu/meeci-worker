#!/bin/bash

set -e

if [[ `whoami` != "root" ]]; then
    echo "Must be run as root."
    exit 1
fi

# Step 1: install dependencies
apt-get install -y \
                systemd \
                libmemcached-dev \
                libsystemd-daemon-dev \
                openssh-client

# Step 2: generate SSH key for root
if [[ ! -f ~/.ssh/id_rsa.pub ]]; then
    ssh-keygen -t rsa
fi

# Step 3: install your key on Meeci host
echo -n "Enter Meeci host IP: "
read host
ssh-copy-id meeci@$host

# Step 4: append "init=/lib/systemd/systemd"(without quotes) to the value of
#         GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub
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
    echo "Reboot to enable systemd."
fi

echo "Exit without errors."
exit 0
