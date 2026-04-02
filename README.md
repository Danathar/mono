# Bootcrew

Bootcrew is a monorepo for building and publishing distro-specific [`bootc`](https://github.com/bootc-dev/bootc) images. These are minimal container images intended as a base to build upon for your own use case, similar to the work from the [Fedora Bootc Base Images](https://docs.fedoraproject.org/en-US/bootc/base-images/) and [Universal Blue](http://universal-blue.org/).

The intended workflow is:

1. Start from a distro image in this repo.
2. Customize its `Containerfile` with additional packages and services.
3. Build a container image locally.
4. Either generate a bootable disk image locally or publish the container image from your own fork.
5. Install that image to a VM or disk, then update installed systems with `bootc switch`.

## Available Images

| Image | Published architecture(s) | CI triggers |
| --- | --- | --- |
| Arch Linux | `amd64` | push, pull request, schedule |
| Debian | `amd64`, `arm64` | push, pull request, schedule |
| Ubuntu | `amd64`, `arm64` | push, pull request, schedule |
| openSUSE Tumbleweed | `amd64`, `arm64` | push, pull request, schedule |

All images are base / CLI images. None include a desktop environment, display manager, or user-facing services by default.

## What This Repo Actually Does

- `just build <image>` builds a container image locally.
- `just disk-image <image> [tag]` creates `./bootable.img` by running `bootc install to-disk` inside that image.
- Writing `bootable.img` to a VM disk or physical disk is a separate deployment step.
- `bootc switch <image-ref>` is for a system that is already installed and running.

Important:

- The documented and tested path in this repo uses rootful Podman.
- The default images are bootable, but they do not create a loginable user for you.
- `root` is either locked or has no password depending on the base container image; neither upstream Containerfile sets one.
- If you want first-boot access, use the access-image flow below before you try to boot the result.

## Objective

None of these should need to exist. Ideally all of these projects would directly publish `(project-name)-bootc` images, or at least provide a `bootc` package or bundle for it. The images in this repo aim to be as small and basic as possible to minimize maintenance burden and make it easier to upstream any efforts from them.

## Prerequisites

Required for local use:

- Linux host
- rootful Podman
- `just`
- enough free disk space for container builds and `bootable.img`
- network access during builds

Required for GitHub publishing:

- a GitHub fork of this repo
- GitHub Actions enabled on that fork
- permission to publish to GHCR under your namespace

Optional:

- `openssl` for creating password hashes in temporary access images
- `qemu-img`, `virt-install`, and `virsh` for local VM testing

Builds are not fully pinned. The shared build helper clones upstream `bootc` at build time, so scheduled rebuilds can pick up both distro package changes and new upstream `bootc` commits.

## What You Are Expected To Customize

Most users should customize only:

- the distro `Containerfile`
- distro-specific files under that image directory
- the matching GitHub workflow if they want to rename the published image or change CI behavior

Most users should not need to touch the shared helper scripts unless they intentionally want to change the underlying bootc filesystem layout or build pipeline.

## Quick Start

Build a base image:

```bash
just build debian
just build arch
just build ubuntu
just build opensuse
```

If you already have another credential injection method, you can turn any of them into `bootable.img` directly:

```bash
just disk-image debian
just disk-image arch
just disk-image ubuntu
just disk-image opensuse
```

For a first boot you can actually log into, use the access-image flow below.

## Create An Access-Enabled Image For First Boot

Pick the base image reference you want to extend:

- local build: `<image>-bootc:latest` (e.g. `debian-bootc:latest`)
- published image from your fork: `ghcr.io/<your-user>/<image>-bootc:latest`

Then build a temporary derived image that sets a root password and creates one admin user.

For Debian-based images (Debian, Ubuntu):

```bash
ROOT_HASH="$(openssl passwd -6 '<temporary-root-password>')"
USER_HASH="$(openssl passwd -6 '<temporary-user-password>')"

cat > Containerfile.access <<'EOF'
FROM <base-image>
ARG ROOT_HASH
ARG USERNAME
ARG USER_HASH
RUN apt update -y && apt install -y sudo && apt clean -y && \
    echo "root:${ROOT_HASH}" | chpasswd -e && \
    install -d -m 0755 /var/home && \
    useradd -m -d "/var/home/${USERNAME}" -u 1000 -G sudo -s /bin/bash "${USERNAME}" && \
    echo "${USERNAME}:${USER_HASH}" | chpasswd -e
EOF
```

For Arch:

```bash
ROOT_HASH="$(openssl passwd -6 '<temporary-root-password>')"
USER_HASH="$(openssl passwd -6 '<temporary-user-password>')"

cat > Containerfile.access <<'EOF'
FROM <base-image>
ARG ROOT_HASH
ARG USERNAME
ARG USER_HASH
RUN pacman -Syu --noconfirm sudo && \
    echo "root:${ROOT_HASH}" | chpasswd -e && \
    install -d -m 0755 /var/home && \
    useradd -m -d "/var/home/${USERNAME}" -u 1000 -G wheel -s /bin/bash "${USERNAME}" && \
    echo "${USERNAME}:${USER_HASH}" | chpasswd -e && \
    mkdir -p /etc/sudoers.d && \
    echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel && \
    chmod 0440 /etc/sudoers.d/10-wheel
EOF
```

For openSUSE:

```bash
ROOT_HASH="$(openssl passwd -6 '<temporary-root-password>')"
USER_HASH="$(openssl passwd -6 '<temporary-user-password>')"

cat > Containerfile.access <<'EOF'
FROM <base-image>
ARG ROOT_HASH
ARG USERNAME
ARG USER_HASH
RUN zypper install -y sudo && \
    echo "root:${ROOT_HASH}" | chpasswd -e && \
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

# If you built the base image locally, replace <base-image> with e.g. debian-bootc:latest
# before running this command.
# If this fails on a Fedora or other SELinux-enforcing host, retry with:
#   --security-opt label=disable
sudo podman build \
  --build-arg ROOT_HASH="${ROOT_HASH}" \
  --build-arg USERNAME='<username>' \
  --build-arg USER_HASH="${USER_HASH}" \
  -t ghcr.io/<your-user>/<image>-bootc:with-access \
  -f Containerfile.access .
```

Turn that image into a bootable disk image:

```bash
truncate -s 100G bootable.img
just disk-image 'ghcr.io/<your-user>/<image>' with-access
```

Notes:

- `truncate -s 100G bootable.img` creates a sparse file at `./bootable.img`
- if `bootable.img` does not exist, `just disk-image` creates a default `20G` preallocated file for you via `fallocate`
- `just disk-image` bind-mounts the current directory as `/data` and runs `bootc install to-disk --via-loopback /data/bootable.img`
- you do not need to push the `with-access` tag first if it already exists in the rootful Podman store
- use `sudo podman build` so the derived image lands in the same rootful store used by `just disk-image`
- on Fedora and other SELinux-enforcing hosts, `sudo podman build --security-opt label=disable ...` may be needed for this temporary access-image build
- the base images do not include `sudo`, so the examples above install it in the access layer

Treat the `with-access` image as temporary and rotate or remove both passwords after first boot.

## Create A VM

First generate `bootable.img` using the access-image flow above or another credential strategy.

Convert the raw disk image to qcow2:

```bash
mkdir -p output
qemu-img convert -f raw -O qcow2 -S 4k bootable.img output/bootc-100g.qcow2
```

Launch it with `virt-install`:

```bash
virt-install \
  --connect qemu:///session \
  --name bootc-local \
  --memory 8192 \
  --vcpus 10 \
  --cpu host-passthrough \
  --import \
  --disk path=/absolute/path/to/output/bootc-100g.qcow2,format=qcow2,bus=virtio \
  --network user,model=virtio \
  --graphics spice \
  --video virtio \
  --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=no \
  --osinfo linux2024 \
  --noautoconsole
```

To recreate the VM:

```bash
virsh -c qemu:///session destroy bootc-local || true
virsh -c qemu:///session undefine bootc-local --nvram || true
```

Then run the `virt-install` command again.

## Install On Bare Metal

1. Generate `bootable.img` using the access-image flow above.
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
- if you installed `ghcr.io/<your-user>/<image>-bootc:with-access`, switch to your normal image after first login:

```bash
sudo bootc switch ghcr.io/<your-user>/<image>-bootc:latest
sudo reboot
```

`with-access` is meant only for first boot and initial access. After the reboot, the system should track your normal published image.

## Updating Installed Systems

Once the system is installed, update it by switching to your published image and rebooting:

```bash
sudo bootc switch ghcr.io/<your-user>/<image>-bootc:latest
sudo reboot
```

Your local users and host state persist across image updates under `/etc` and `/var/home`.

## Using This Repo As A Fork

The recommended pattern is:

1. Fork this repository.
2. Pick a distro as your starting point.
3. Remove or disable workflows you do not plan to maintain.
4. Make your image changes in that distro directory.
5. Build locally once to validate the result.
6. Push to a branch to run CI validation.
7. Merge to your default branch to publish updated images to your own GHCR namespace.

If you only want one maintained image in your fork, keep only that image directory and that image's workflow. This keeps the fork simpler and avoids burning CI time on images you do not use.

## Publishing And CI Behavior

For the images in this repo today:

- branch pushes and pull requests build for validation
- publishing happens only on default-branch, non-pull-request runs
- scheduled workflows rebuild and republish the current default-branch image
- published images go to `ghcr.io/<repo-owner>/<image-name>:latest`

Examples:

- `ghcr.io/<your-user>/arch-bootc:latest`
- `ghcr.io/<your-user>/debian-bootc:latest`
- `ghcr.io/<your-user>/ubuntu-bootc:latest`
- `ghcr.io/<your-user>/opensuse-bootc:latest`

Before relying on publishing from your fork, check all of these:

- GitHub Actions is enabled on the fork
- the workflow you want is still present and enabled
- you understand that merging to the default branch is what publishes
- you have decided whether your GHCR package should stay private or be made public
- if you keep signing enabled, you have configured the `SIGNING_SECRET` repository secret
