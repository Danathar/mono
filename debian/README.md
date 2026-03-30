# Debian Bootc

> **Note:** This image was created primarily using directed AI, though its contents have been manually tested and inspected. Special thanks to the upstream repository [bootcrew/mono](https://github.com/bootcrew/mono) for the foundational bootstrapping work.

Reference [Debian](https://www.debian.org/) (unstable) container image preconfigured for [bootc](https://github.com/bootc-dev/bootc) usage.

## Goal

Use this image as your own bootc image source, build locally, boot it in a VM, create your own user, and later update installed systems with `bootc switch`.

*Unlike a traditional Linux distribution where you install packages on a live system, you manage this system by editing the `Containerfile`, building a new container image, and instructing your host to boot from that image.*

## Current Customizations

This image includes the following opinionated changes:

### Base image

- Hardware utilities (`fwupd` for firmware, `smartmontools` for drive health)
- CLI utilities (`wget`, `curl`, `rsync`, `vim`, `openssh-server`, `git`)
- Container tooling (`podman`, `skopeo`, `distrobox`)
- Expanded filesystem support (`btrfs-progs`, `xfsprogs`, `e2fsprogs`, `dosfstools`, `ntfs-3g`)
- `NetworkManager` installed and enabled for first-boot DHCP
- `firewalld` installed and enabled
- `sudo` installed
- Root password is locked by default for security (configure via cloud-init, SSH keys, or a temporary derived image)
- Homebrew integration via `ublue-os/brew` (pre-configured to extract on first boot for UID 1000)

### KDE desktop layer (built on top of base)

- KDE Plasma desktop + SDDM display manager enabled (graphical login by default)
- KDE standard application suite via `kde-standard`
- Mesa Vulkan drivers
- Essential fonts (`fonts-noto`, `fonts-noto-cjk`, `fonts-noto-color-emoji`)
- GStreamer media codecs (`gstreamer1.0-plugins-*`, `gstreamer1.0-libav`)
- Bluetooth support installed and enabled (`bluez`)
- Archiving tools (`unzip`, `unrar`, `p7zip-full`)
- Network discovery / mDNS configured and enabled (`avahi-daemon`, `libnss-mdns`)
- Printing stack installed and enabled (`cups`, `cups-pdf`)
- `power-profiles-daemon` installed and enabled
- `xdg-user-dirs`, `firefox-esr`, `flatpak`, `konsole` installed
- Flathub remote pre-configured system-wide

## Building

From the repository root:

**Build the KDE desktop image (default, last stage):**
```bash
just build debian
```

**Build the base image only (CLI, no desktop):**
```bash
just build debian base
```

**Recommended: generate a bootable disk image from the published GHCR image with a temporary `root` password and one pre-created admin user:**

```bash
sudo podman login ghcr.io  # only needed if the package is private
ROOT_HASH="$(openssl passwd -6 '<temporary-root-password>')"
USER_HASH="$(openssl passwd -6 '<temporary-user-password>')"
cat > Containerfile.access <<'EOF'
FROM ghcr.io/<your-user>/debian-bootc:latest
ARG ROOT_HASH
ARG USERNAME
ARG USER_HASH
RUN echo "root:${ROOT_HASH}" | chpasswd -e && \
    useradd -m -u 1000 -G sudo -s /bin/bash "${USERNAME}" && \
    echo "${USERNAME}:${USER_HASH}" | chpasswd -e
EOF

sudo podman build \
  --build-arg ROOT_HASH="${ROOT_HASH}" \
  --build-arg USERNAME='<username>' \
  --build-arg USER_HASH="${USER_HASH}" \
  -t ghcr.io/<your-user>/debian-bootc:with-access \
  -f Containerfile.access .

truncate -s 100G bootable.img
just disk-image 'ghcr.io/<your-user>/debian' with-access
```

`just disk-image` appends `-bootc` internally, so use `ghcr.io/<your-user>/debian` here, not `ghcr.io/<your-user>/debian-bootc`.

Use `sudo podman build` so the derived image lands in the rootful Podman store that `just disk-image` uses. Treat that `with-access` image as temporary and remove or rotate both passwords after first boot.

**If you do not want pre-created credentials, you can still generate a disk image directly:**
```bash
just disk-image debian
```

Or from the published GHCR image:
```bash
sudo podman login ghcr.io  # only needed if the package is private
just disk-image 'ghcr.io/<your-user>/debian' latest
```

## Creating a VM

### 1. Generate the disk image

```bash
# Run the recommended access-image flow from the "Building" section first.
# That produces bootable.img with a temporary root password and one admin user.
mkdir -p output
qemu-img convert -f raw -O qcow2 -S 4k bootable.img output/debian-bootc-100g.qcow2
```

### 2. Launch with virt-install

```bash
virt-install \
  --connect qemu:///session \
  --name debian-bootc-local \
  --memory 8192 \
  --vcpus 10 \
  --cpu host-passthrough \
  --import \
  --disk path=/absolute/path/to/output/debian-bootc-100g.qcow2,format=qcow2,bus=virtio \
  --network user,model=virtio \
  --graphics spice \
  --video virtio \
  --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=no \
  --osinfo linux2024 \
  --noautoconsole
```

To recreate the VM:
```bash
virsh -c qemu:///session destroy debian-bootc-local || true
virsh -c qemu:///session undefine debian-bootc-local --nvram || true
```

## Installing on Bare Metal

1. Generate `bootable.img` using the recommended access-image flow from the "Building" section.

2. Identify the target disk (example: `/dev/nvme0n1`):
```bash
sudo lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL
```

3. Write the image to disk:
```bash
sudo dd if=bootable.img of=/dev/nvme0n1 bs=16M status=progress oflag=direct conv=fsync
sync
```

> `dd` erases the target disk completely. Double-check `of=` before running. Keep Secure Boot disabled unless you manage your own signed boot chain.

## Post-Installation / First Boot

> The recommended flow in the "Building" section pre-creates `root` plus one admin user. Rotate or remove those temporary passwords after first boot.

If you used a plain image without pre-created credentials, and you have root access (for example via an injected SSH key or live media), create your own admin account:

```bash
# Ensure the user has UID 1000 to use the pre-configured Homebrew
useradd -m -u 1000 -G sudo -s /bin/bash <username>
echo '<username>:<password>' | chpasswd
```

## Updating Installed Systems

Once installed, switch to your published image and reboot:

```bash
bootc switch ghcr.io/<your-user>/debian-bootc:latest
reboot
```

Your local users and host state persist across image updates (`/etc`, `/var/home`).
