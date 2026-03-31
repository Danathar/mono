# Arch Linux Bootc

Supported Arch-based `bootc` image from this repository.

This is the most featureful ready image in the repo. Its default build and published output is a KDE desktop image built on top of a smaller Arch bootc base.

## What This Image Is

- status: supported and ready for use in this repo
- published architecture: `amd64`
- default and published stage: `kde`
- optional local-only stage: `base`

If you want a CLI-only Arch image, you can build the `base` stage locally. The default GitHub workflow publishes the KDE stage, not the base stage.

## Before You Start

Run all commands from the repository root.

The documented path assumes:

- rootful Podman
- `just`
- enough free disk space for image builds and `bootable.img`

Important first-boot behavior:

- the default image does not create a normal user
- `root` is locked by default
- `just disk-image arch` creates a bootable disk image, but not one you can automatically log into

If you want first-boot access, use the access-image flow below or bring your own credential injection strategy.

## Naming Convention Used By `just`

The local recipes use a split between image name and tag:

- `just build arch` builds the local container image `arch-bootc:latest`
- `just disk-image arch with-access` installs `arch-bootc:with-access`
- `just disk-image 'ghcr.io/<your-user>/arch' with-access` installs `ghcr.io/<your-user>/arch-bootc:with-access`

`just disk-image` appends `-bootc` internally, so when you use a fully qualified image name you pass the repository path without the `-bootc` suffix.

## Included Changes

Base image changes:

- CPU microcode: `intel-ucode`, `amd-ucode`
- Hardware utilities: `fwupd`, `smartmontools`
- CLI utilities: `wget`, `curl`, `rsync`, `vim`, `openssh`, `git`
- Container tooling: `podman`, `skopeo`, `distrobox`
- Filesystem utilities: `btrfs-progs`, `xfsprogs`, `e2fsprogs`, `dosfstools`, `ntfs-3g`
- `NetworkManager`, enabled for first-boot networking
- `firewalld`, enabled
- `sudo`
- Homebrew integration via `ublue-os/brew`, pre-configured for a UID `1000` user
- `nano` removed

KDE stage changes:

- KDE Plasma desktop with graphical login
- full KDE applications suite
- Vulkan, Mesa, and VA-API drivers
- fonts, codecs, Bluetooth, printing, and archive tools
- `firefox`, `flatpak`, `konsole`, `xdg-user-dirs`
- Flathub remote configured system-wide

## Build Locally

Build the default KDE image:

```bash
just build arch
```

Build the CLI-only base stage:

```bash
just build arch base
```

This validates and tags a local container image. It does not create a VM, disk image, user account, or first-boot credentials.

If you want a build log:

```bash
just build arch 2>&1 | tee build.log
```

## Recommended: Create An Access-Enabled Image For First Boot

Pick the base image reference you want to extend:

- local build: `arch-bootc:latest`
- published image from your fork: `ghcr.io/<your-user>/arch-bootc:latest`

Then build a temporary derived image that sets a root password and creates one admin user:

```bash
ROOT_HASH="$(openssl passwd -6 '<temporary-root-password>')"
USER_HASH="$(openssl passwd -6 '<temporary-user-password>')"

cat > Containerfile.access <<'EOF'
FROM <base-image>
ARG ROOT_HASH
ARG USERNAME
ARG USER_HASH
RUN echo "root:${ROOT_HASH}" | chpasswd -e && \
    install -d -m 0755 /var/home && \
    useradd -m -d "/var/home/${USERNAME}" -u 1000 -G wheel -s /bin/bash "${USERNAME}" && \
    echo "${USERNAME}:${USER_HASH}" | chpasswd -e && \
    mkdir -p /etc/sudoers.d && \
    echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel && \
    chmod 0440 /etc/sudoers.d/10-wheel
EOF
```

Build that derived image with rootful Podman:

```bash
# Only needed if you are using a private GHCR base image.
sudo podman login ghcr.io

# If you built the base image locally, replace <base-image> with arch-bootc:latest
# before running this command.
sudo podman build \
  --build-arg ROOT_HASH="${ROOT_HASH}" \
  --build-arg USERNAME='<username>' \
  --build-arg USER_HASH="${USER_HASH}" \
  -t ghcr.io/<your-user>/arch-bootc:with-access \
  -f Containerfile.access .
```

Turn that image into a bootable disk image:

```bash
truncate -s 100G bootable.img
just disk-image 'ghcr.io/<your-user>/arch' with-access
```

Notes:

- `truncate -s 100G bootable.img` creates a sparse file at `./bootable.img`
- if `bootable.img` does not exist, `just disk-image` creates a default `20G` sparse file for you
- `just disk-image` bind-mounts the current directory as `/data` and runs `bootc install to-disk --via-loopback /data/bootable.img`
- you do not need to push the `with-access` tag first if it already exists in the rootful Podman store
- use `sudo podman build` so the derived image lands in the same rootful store used by `just disk-image`

Treat the `with-access` image as temporary and rotate or remove both passwords after first boot.

## Minimal Disk-Image Flow

Only use these if you already have another way to get into the system after installation.

From the locally built image:

```bash
just disk-image arch
```

From a published image:

```bash
sudo podman login ghcr.io
just disk-image 'ghcr.io/<your-user>/arch' latest
```

## Create A VM

First generate `bootable.img` using the recommended access-image flow above or another credential strategy.

Convert the raw disk image to qcow2:

```bash
mkdir -p output
qemu-img convert -f raw -O qcow2 -S 4k bootable.img output/arch-bootc-100g.qcow2
```

Launch it with `virt-install`:

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

## Install On Bare Metal

1. Generate `bootable.img` using the recommended access-image flow above.
2. Confirm the target disk carefully.
3. Write the image to disk.

Identify the disk:

```bash
sudo lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL
```

Write the image:

```bash
sudo dd if=bootable.img of=/dev/nvme0n1 bs=16M status=progress oflag=direct conv=fsync
sync
```

`dd` erases the target disk completely. Double-check `of=` before you run it. Keep Secure Boot disabled unless you manage your own signed boot chain.

## First Boot And Credentials

If you used the access-image flow:

- log in with the temporary root or user password
- rotate or remove those passwords immediately
- keep the first user at UID `1000` if you want the preconfigured Homebrew integration

If you used a plain image without pre-created credentials, you need some other root access path before you can create a user. Once you have root access:

```bash
useradd -m -u 1000 -G wheel -s /bin/bash <username>
echo '<username>:<password>' | chpasswd
mkdir -p /etc/sudoers.d
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel
```

## Updating Installed Systems

Once the system is installed, update it by switching to your published image and rebooting:

```bash
bootc switch ghcr.io/<your-user>/arch-bootc:latest
reboot
```

Your local users and host state persist across image updates under `/etc` and `/var/home`.

## Why The Arch Image Works

This image includes a few Arch-specific compatibility steps that are easy to break if you remove them:

- `bootc` is built from upstream source because Arch does not currently ship it as a ready package for this workflow
- pacman paths under `/var` are remapped into `/usr/lib/sysimage` to fit the immutable bootc layout
- Arch's `NoExtract` defaults are disabled so language and help files can be installed normally
- `glibc` is reinstalled to restore locale files stripped from the base container
- the initramfs is rebuilt with the `bootc` dracut module
- the final root filesystem is normalized into the bootc / ostree layout with composefs enabled
- the required `containers.bootc=1` label is applied

If you change those compatibility steps, `bootc install` or `bootc switch` may stop behaving correctly.
