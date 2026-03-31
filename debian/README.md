# Debian Bootc

Supported Debian-based `bootc` image from this repository.

This image currently tracks Debian unstable and is intended to be a small, bootable base image that you can extend with your own packages and configuration.

## What This Image Is

- status: supported and ready for use in this repo
- published architecture: `amd64`
- default and published stage: `base`
- interface style: base / CLI only

This image does not include a desktop environment or display manager.

## Before You Start

Run all commands from the repository root.

The documented path assumes:

- rootful Podman
- `just`
- enough free disk space for image builds and `bootable.img`

Important first-boot behavior:

- the default image does not create a normal user
- `root` is locked by default
- `just disk-image debian` creates a bootable disk image, but not one you can automatically log into

If you want first-boot access, use the access-image flow below or bring your own credential injection strategy.

## Naming Convention Used By `just`

The local recipes use a slightly unusual split between image name and tag:

- `just build debian` builds the local container image `debian-bootc:latest`
- `just disk-image debian with-access` installs `debian-bootc:with-access`
- `just disk-image 'ghcr.io/<your-user>/debian' with-access` installs `ghcr.io/<your-user>/debian-bootc:with-access`

`just disk-image` appends `-bootc` internally, so when you use a fully qualified image name you pass the repository path without the `-bootc` suffix.

## Included Changes

This image currently includes:

- Hardware utilities: `fwupd`, `smartmontools`
- CLI utilities: `wget`, `curl`, `rsync`, `vim`, `openssh-server`, `git`
- Container tooling: `podman`, `skopeo`, `distrobox`
- Filesystem utilities: `btrfs-progs`, `xfsprogs`, `e2fsprogs`, `dosfstools`, `ntfs-3g`
- `NetworkManager`, enabled for first-boot networking
- `firewalld`, enabled
- `sudo`
- Homebrew integration via `ublue-os/brew`, pre-configured for a UID `1000` user

## Build Locally

Build the default Debian image:

```bash
just build debian
```

Build the same published stage explicitly:

```bash
just build debian base
```

This validates and tags the local container image. It does not create a VM, disk image, user account, or first-boot credentials.

## Recommended: Create An Access-Enabled Image For First Boot

Pick the base image reference you want to extend:

- local build: `debian-bootc:latest`
- published image from your fork: `ghcr.io/<your-user>/debian-bootc:latest`

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
    useradd -m -d "/var/home/${USERNAME}" -u 1000 -G sudo -s /bin/bash "${USERNAME}" && \
    echo "${USERNAME}:${USER_HASH}" | chpasswd -e
EOF
```

Build that derived image with rootful Podman:

```bash
# Only needed if you are using a private GHCR base image.
sudo podman login ghcr.io

# If you built the base image locally, replace <base-image> with debian-bootc:latest
# before running this command.
# If this fails on a Fedora or other SELinux-enforcing host, retry with:
#   --security-opt label=disable
sudo podman build \
  --build-arg ROOT_HASH="${ROOT_HASH}" \
  --build-arg USERNAME='<username>' \
  --build-arg USER_HASH="${USER_HASH}" \
  -t ghcr.io/<your-user>/debian-bootc:with-access \
  -f Containerfile.access .
```

Turn that image into a bootable disk image:

```bash
truncate -s 100G bootable.img
just disk-image 'ghcr.io/<your-user>/debian' with-access
```

Notes:

- `truncate -s 100G bootable.img` creates a sparse file at `./bootable.img`
- if `bootable.img` does not exist, `just disk-image` creates a default `20G` sparse file for you
- `just disk-image` bind-mounts the current directory as `/data` and runs `bootc install to-disk --via-loopback /data/bootable.img`
- you do not need to push the `with-access` tag first if it already exists in the rootful Podman store
- use `sudo podman build` so the derived image lands in the same rootful store used by `just disk-image`
- on Fedora and other SELinux-enforcing hosts, `sudo podman build --security-opt label=disable ...` may be needed for this temporary access-image build

Treat the `with-access` image as temporary and rotate or remove both passwords after first boot.

## Minimal Disk-Image Flow

Only use these if you already have another way to get into the system after installation.

From the locally built image:

```bash
just disk-image debian
```

From a published image:

```bash
sudo podman login ghcr.io
just disk-image 'ghcr.io/<your-user>/debian' latest
```

## Create A VM

First generate `bootable.img` using the recommended access-image flow above or another credential strategy.

Convert the raw disk image to qcow2:

```bash
mkdir -p output
qemu-img convert -f raw -O qcow2 -S 4k bootable.img output/debian-bootc-100g.qcow2
```

Launch it with `virt-install`:

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
- if you installed `ghcr.io/<your-user>/debian-bootc:with-access`, switch to your normal image after first login:

```bash
sudo bootc switch ghcr.io/<your-user>/debian-bootc:latest
sudo reboot
```

`with-access` is meant only for first boot and initial access. After the reboot, the system should track your normal published image such as `ghcr.io/<your-user>/debian-bootc:latest`.

If you used a plain image without pre-created credentials, you need some other root access path before you can create a user. Once you have root access:

```bash
useradd -m -u 1000 -G sudo -s /bin/bash <username>
echo '<username>:<password>' | chpasswd
```

## Updating Installed Systems

Once the system is installed, update it by switching to your published image and rebooting:

```bash
sudo bootc switch ghcr.io/<your-user>/debian-bootc:latest
sudo reboot
```

Your local users and host state persist across image updates under `/etc` and `/var/home`.
