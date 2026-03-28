#!/usr/bin/env bash

# This script rewrites a normal distro filesystem into the layout bootc expects.
# It is destructive on purpose, so strict shell settings are important here.
set -xeuo pipefail

# Remove paths that should not remain as ordinary writable directories in a bootc
# image. They will be recreated under `/var` or `/sysroot` in a controlled way.
rm -rf /boot /home /root /usr/local /srv /opt /mnt /var /usr/lib/sysimage/log /usr/lib/sysimage/cache/pacman/pkg

# Create the minimal directory skeleton needed by ostree/bootc.
mkdir -p /sysroot /boot /usr/lib/ostree /var

# Replace familiar top-level paths with symlinks into their bootc-managed homes.
# For example, `/home` becomes `/var/home`, which is where user data should live.
ln -sT sysroot/ostree /ostree && ln -sT var/roothome /root && ln -sT var/srv /srv && ln -sT var/opt /opt && ln -sT var/mnt /mnt && ln -sT var/home /home && ln -sT ../var/usrlocal /usr/local

# systemd-tmpfiles recreates these directories at boot if they are missing.
echo "$(for dir in opt home srv mnt usrlocal ; do echo "d /var/$dir 0755 root root -" ; done)" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf"

# Root's home stays private, while `/run/media` is a common mount point for removable media.
printf "d /var/roothome 0700 root root -\nd /run/media 0755 root root -" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf"

# Tell ostree to use composefs and keep the deployed sysroot read-only.
printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' | tee "/usr/lib/ostree/prepare-root.conf"
