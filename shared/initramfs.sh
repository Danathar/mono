#!/usr/bin/env bash

# The initramfs is the tiny early-boot environment loaded before the real root
# filesystem is mounted. We rebuild it so it always includes the bootc logic.
set -xeuo pipefail

# Dracut reads drop-in configuration from this directory.
mkdir -p /usr/lib/dracut/dracut.conf.d/

# Different distros package systemd units in slightly different places.
# These overrides make dracut look where this image layout expects them.
printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf

# Build a generic, reproducible initramfs and explicitly include the `bootc`
# dracut module. `hostonly=no` avoids baking the image to one machine's hardware.
printf 'reproducible=yes\nhostonly=no\ncompress=zstd\nadd_dracutmodules+=" bootc "' | tee "/usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-container-build.conf"

# Write the initramfs next to the newest installed kernel's module directory so
# the boot loader can find a matching kernel/initramfs pair.
dracut --force "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)/initramfs.img"
