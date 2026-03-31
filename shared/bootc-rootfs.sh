#!/usr/bin/env bash

set -xeuo pipefail

rm -rf /boot /home /root /usr/local /srv /opt /mnt /var /usr/lib/sysimage/log /usr/lib/sysimage/cache/pacman/pkg

mkdir -p /sysroot /boot /usr/lib/ostree /var

ln -sT sysroot/ostree /ostree && ln -sT var/roothome /root && ln -sT var/srv /srv && ln -sT var/opt /opt && ln -sT var/mnt /mnt && ln -sT var/home /home && ln -sT ../var/usrlocal /usr/local

echo "$(for dir in opt home srv mnt usrlocal ; do echo "d /var/$dir 0755 root root -" ; done)" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf"

printf "d /var/roothome 0700 root root -\nd /run/media 0755 root root -" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf"

# Container images do not normally ship `/etc/hosts`, because runtimes inject it.
# A booted VM or bare-metal install does not get that injection, so install a
# small repair service for deployments that may have a missing or empty file.
install -D -m 0755 /ctx/shared/ensure-default-hosts.sh /usr/libexec/bootcrew-ensure-default-hosts
install -D -m 0644 /ctx/shared/bootcrew-ensure-hosts.service /usr/lib/systemd/system/bootcrew-ensure-hosts.service
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sfr /usr/lib/systemd/system/bootcrew-ensure-hosts.service /etc/systemd/system/multi-user.target.wants/bootcrew-ensure-hosts.service

printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' | tee "/usr/lib/ostree/prepare-root.conf"
