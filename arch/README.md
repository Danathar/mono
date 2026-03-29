# Arch Linux Bootc

> **Note:** This image was created primarily using directed AI, though its contents have been manually tested and inspected. Special thanks to the upstream repository [bootcrew/arch-bootc](https://github.com/bootcrew/arch-bootc) for the foundational bootstrapping work.

Reference [Arch Linux](https://archlinux.org/) container image preconfigured for [bootc](https://github.com/bootc-dev/bootc) usage.

## Goal

Use this image as your own bootc image source, build locally, boot it in a VM, create your own user, and later update installed systems with `bootc switch`.

*Unlike a traditional Linux distribution where you install packages on a live system, you manage this system by editing the `Containerfile`, building a new container image, and instructing your host to boot from that image.*

## Current Customizations

This image includes the following opinionated changes:

### Base image

- CPU microcode (`intel-ucode`, `amd-ucode`)
- Hardware utilities (`fwupd` for firmware, `smartmontools` for drive health)
- CLI utilities (`wget`, `curl`, `rsync`, `vim`, `openssh`, `git`)
- Container tooling (`podman`, `skopeo`, `distrobox`)
- Expanded filesystem support (`btrfs-progs`, `xfsprogs`, `e2fsprogs`, `dosfstools`, `ntfs-3g`)
- `NetworkManager` installed and enabled for first-boot DHCP
- `firewalld` installed and enabled (for NetworkManager zone integration)
- `sudo` installed (`visudo` included)
- Hardcoded root password is locked for security (configure via cloud-init or SSH keys)
- Homebrew integration via `ublue-os/brew` (pre-configured to extract on first boot for UID 1000)
- `nano` removed from the image

### KDE desktop layer (built on top of base)

- KDE Plasma desktop + Plasma Login Manager enabled (graphical login by default)
- Full KDE applications suite via `kde-applications-meta`
- Vulkan and Mesa drivers (`vulkan-radeon`, `vulkan-intel`, `vulkan-mesa-layers`, `libva-intel-driver`, `libva-mesa-driver`)
- Essential fonts (`noto-fonts`, `noto-fonts-emoji`, `noto-fonts-cjk`)
- GStreamer media codecs (`gst-plugins-*`, `gst-libav`)
- Bluetooth support installed and enabled (`bluez`, `bluez-utils`)
- Archiving tools (`unzip`, `unrar`, `p7zip`)
- Network discovery / mDNS configured and enabled (`avahi`, `nss-mdns`)
- Printing stack installed and enabled (`cups`, `cups-pdf`)
- `power-profiles-daemon` installed and enabled (for KDE power management)
- `xdg-user-dirs`, `firefox`, `flatpak`, `konsole` installed
- Flathub remote pre-configured system-wide

## Building

From the repository root:

**Build the KDE desktop image (default, last stage):**
```bash
just build arch
```

**Build the base image only (CLI, no desktop):**
```bash
just build arch base
```

**Generate a bootable disk image:**
```bash
just disk-image arch
```

If you want log files you can tail:
```bash
just build arch 2>&1 | tee build.log
```

## Creating a VM

### 1. Build a disk image

```bash
truncate -s 100G bootable.img
just disk-image arch
mkdir -p output
qemu-img convert -f raw -O qcow2 -S 4k bootable.img output/arch-bootc-100g.qcow2
```

### 2. Launch with virt-install

```bash
virt-install \
  --connect qemu:///session \
  --name arch-bootc-local \
  --memory 8192 \
  --vcpus 10 \
  --cpu host-passthrough \
  --import \
  --disk path=/absolute/path/to/output/arch-bootc-100g.qcow2,format=qcow2,bus=virtio \
  --network user,model=virtio \
  --graphics spice \
  --video virtio \
  --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=no \
  --osinfo linux2024 \
  --noautoconsole
```

To recreate the VM:
```bash
virsh -c qemu:///session destroy arch-bootc-local || true
virsh -c qemu:///session undefine arch-bootc-local --nvram || true
```

Then run the `virt-install` command again.

## Installing on Bare Metal

1. Build the container image and generate a bootable raw disk image:
```bash
just build arch
truncate -s 100G bootable.img
just disk-image arch
```

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

4. Reboot and boot from that disk.
   - On the first boot after installation, the system will prompt you to select your timezone before proceeding to the graphical login.
   - Because it boots directly into the graphical login screen, you will need to switch to a virtual console (usually `Ctrl`+`Alt`+`F3`) and log in as `root`.
   - Add your user using the commands detailed in the "Post-Installation" section below.

## Post-Installation / First Boot

> The root account is locked by default. Configure user accounts via cloud-init, standard users in your builder tool, or inject an SSH key during image generation.

If you have root access (e.g. via virtual console or live media), create your own admin account:

```bash
# Ensure the user has UID 1000 to use the pre-configured Homebrew
useradd -m -u 1000 -G wheel -s /bin/bash <username>
echo '<username>:<password>' | chpasswd
mkdir -p /etc/sudoers.d
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel
```

## Updating Installed Systems

Once installed, switch to your published image and reboot:

```bash
bootc switch ghcr.io/<your-user>/arch-bootc:latest
reboot
```

Your local users and host state persist across image updates (`/etc`, `/var/home`).

## Upstream Compatibility Work (Why This Image Works)

This project inherits key bootstrapping work from the upstream `bootcrew/arch-bootc` approach:

- `bootc` is built from upstream source during image build because Arch official repos do not currently ship `bootc`.
- Arch container base fixes are applied:
  - pacman `/var` paths are relocated into `/usr/lib/sysimage` for bootc-style immutable layout behavior
  - `NoExtract` rules are disabled so language/help content can be installed normally
  - `glibc` is reinstalled to restore missing locale files from the base container
- Initramfs and boot integration are prepared with `dracut` config for `ostree` + `bootc` modules.
- Bootc/ostree filesystem layout and symlink structure is enforced (`/sysroot`, `/ostree`, `/var/home`, etc.) with composefs enabled.
- Required metadata label is set for bootc-compatible images: `containers.bootc=1`.

If you remove or change these compatibility steps, `bootc install/switch` behavior may break or become inconsistent.
