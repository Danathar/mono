# Bootcrew

Bootcrew publishes minimal, bootable [`bootc`](https://github.com/bootc-dev/bootc) container images for multiple Linux distributions. Each image is a standard OCI container that can be installed as a bootable disk image and updated in place by pulling a newer version of the container — no traditional package upgrades or reinstalls. You can use them directly or as a base to build your own images.

## Objective

None of these should need to exist. Ideally all of these projects would directly publish `(project-name)-bootc` images, or at least provide a `bootc` package or bundle for it. These images aim to be as small and basic as possible to minimize maintenance burden and make it easier to upstream any efforts from them.

## Table Of Contents

- [Published Images](#published-images)
- [Quick Start](#quick-start)
- [Create A VM](#create-a-vm)
- [Install On Bare Metal](#install-on-bare-metal)
- [Updating Installed Systems](#updating-installed-systems)
- [Building Your Own Image](#building-your-own-image)
- [Building The Images From Source](#building-the-images-from-source)
- [Forking This Repo](#forking-this-repo)
- [SELinux Hosts](#selinux-hosts)

## Published Images

| Image | Base | Reference | Architecture(s) |
| --- | --- | --- | --- |
| Arch Linux | `archlinux:latest` | `ghcr.io/bootcrew/arch-bootc:latest` | `amd64` |
| Debian | `debian:unstable` | `ghcr.io/bootcrew/debian-bootc:latest` | `amd64`, `arm64` |
| Ubuntu | `ubuntu:questing` | `ghcr.io/bootcrew/ubuntu-bootc:latest` | `amd64`, `arm64` |
| openSUSE Tumbleweed | `opensuse/tumbleweed:latest` | `ghcr.io/bootcrew/opensuse-bootc:latest` | `amd64`, `arm64` |

These images are experimental. All images are base / CLI images. None include a desktop environment, display manager, or user-facing services. They are intended as a starting point — add what you need in your own image. Expect local console access only unless you add services such as SSH in your own image.

Each image builds `bootc` from the upstream [bootc-dev/bootc](https://github.com/bootc-dev/bootc) source rather than using a distro-packaged version. Images are rebuilt weekly (every Tuesday) to pick up distro package updates and new upstream `bootc` commits. In addition to `:latest`, each build is tagged with a date stamp (e.g. `:latest.20260401`, `:20260401`) so you can pin to a specific build.

### Verifying Images

Published images are signed with [cosign](https://docs.sigstore.dev/cosign/). The public key is in `cosign.pub` at the root of this repository. To verify an image before using it:

```bash
cosign verify --key cosign.pub ghcr.io/bootcrew/debian-bootc:latest
```

## Quick Start

Pull a published image and generate a bootable disk image with [bootc-image-builder](https://github.com/osbuild/bootc-image-builder):

You need rootful `podman` on the build host (the builder runs as `sudo podman run`).

If the Linux environment running Podman uses SELinux in `Enforcing` mode, see [SELinux Hosts](#selinux-hosts) before running the builder.

Create a `config.toml` with a local user plus a temporary `root` password. `bootc-image-builder` reads this file at disk-image build time and bakes the users into the image, so they are available on first boot:

```toml
[[customizations.user]]
name = "<username>"
password = "<temporary-password>"

[[customizations.user]]
name = "root"
password = "<temporary-root-password>"
```

On the published images, the regular user gets you console login on first boot, and the temporary `root` password gives you immediate admin access via `su -` or direct root console login. Change that `root` password after first boot, or remove it entirely if you do not want to keep password-based root access. If you prefer a non-root admin user with `sudo`, start with [Building Your Own Image](#building-your-own-image) and add that in your own image.

```bash
sudo podman pull ghcr.io/bootcrew/debian-bootc:latest

mkdir -p output

sudo podman run \
  --rm -it --privileged \
  --security-opt label=type:unconfined_t \
  -v ./config.toml:/config.toml:ro \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  ghcr.io/bootcrew/debian-bootc:latest
```

This creates `output/qcow2/disk.qcow2` ready to boot in a VM, with the configured user available for console login on first boot.

| Type | Use case |
| --- | --- |
| `qcow2` | QEMU / libvirt VMs (default) |
| `raw` | Direct disk write or loopback mount |

If you are just getting started, use `qcow2` for most VMs, or `raw` for bare metal and for VM storage on copy-on-write filesystems such as ZFS or Btrfs. You can specify multiple types in one run, for example `--type qcow2 --type raw`.

Replace `debian-bootc` with any image from the table above. If you use `--type raw`, [Install On Bare Metal](#install-on-bare-metal) below shows how to locate and write the generated `disk.raw`. For other output types, follow the upstream [bootc-image-builder](https://github.com/osbuild/bootc-image-builder) docs.

If the Linux environment running Podman does not have SELinux enabled, you can leave out the `--security-opt label=type:unconfined_t` line from the example commands below. Keeping it there usually still works, but it only matters on SELinux-enabled hosts.

## Create A VM

This section assumes you already generated a `qcow2` image and created a first-boot user via `config.toml`. If not, start with [Quick Start](#quick-start) for published images or [Building Your Own Image](#building-your-own-image) for a derived image.

You need `virt-install`, `libvirt`, `qemu`, and UEFI firmware (e.g. OVMF / `edk2-ovmf`) available on the host.

After generating a qcow2 image:

```bash
virt-install \
  --connect qemu:///session \
  --name bootc-local \
  --memory 8192 \
  --vcpus 4 \
  --cpu host-passthrough \
  --import \
  --disk path=output/qcow2/disk.qcow2,format=qcow2,bus=virtio \
  --network user,model=virtio \
  --graphics spice \
  --video virtio \
  --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=no \
  --osinfo linux2024 \
  --noautoconsole
```

The `--noautoconsole` flag returns you to your shell after the VM starts. To attach to the VM console:

```bash
virt-viewer --connect qemu:///session bootc-local
```

Log in with the user you added in `config.toml`.

To recreate the VM:

```bash
virsh -c qemu:///session destroy bootc-local || true
virsh -c qemu:///session undefine bootc-local --nvram || true
```

Then run the `virt-install` command again.

## Install On Bare Metal

This section assumes you already generated a `raw` image and created a first-boot user via `config.toml`. If not, start with [Quick Start](#quick-start) for published images or [Building Your Own Image](#building-your-own-image) for a derived image.

Generate a raw disk image using the same builder command from [Quick Start](#quick-start), but with `--type raw` instead of `--type qcow2`:

```bash
sudo podman run \
  --rm -it --privileged \
  --security-opt label=type:unconfined_t \
  -v ./config.toml:/config.toml:ro \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type raw \
  ghcr.io/bootcrew/debian-bootc:latest
```

Identify the target disk:

```bash
sudo lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL
```

Locate the generated raw image:

```bash
find output -type f -name 'disk.raw'
```

To write that image onto the target machine, boot the machine from some other operating system first, such as a live USB environment. Do not boot from the disk you are about to overwrite.

You also need the generated `disk.raw` available from that environment, for example on a second USB drive, an external disk, or over the network.

Write the image:

```bash
sudo dd if=output/raw/disk.raw of=/dev/nvme0n1 bs=16M status=progress oflag=direct conv=fsync
sync
```

Replace `output/raw/disk.raw` with the exact path reported by `find` if your builder version uses a different layout.

`dd` erases the target disk completely. Double-check `of=` before you run it. Keep Secure Boot disabled unless you manage your own signed boot chain.

## Updating Installed Systems

This section is for systems that are already installed from one of these images. If you still need to build, boot, or install an image, start with [Quick Start](#quick-start), [Create A VM](#create-a-vm), or [Install On Bare Metal](#install-on-bare-metal).

Once a system is installed, pull a newer version of the same image with `bootc upgrade`:

```bash
sudo bootc upgrade
sudo reboot
```

To change to a different image entirely, use `bootc switch`. This changes the source image for all future updates. If you want to switch to an image from your own custom repository, see [Building Your Own Image](#building-your-own-image) below:

```bash
sudo bootc switch ghcr.io/bootcrew/arch-bootc:latest
sudo reboot
```

Your local users and host state persist across both upgrades and switches. The system keeps `/etc` and `/var/home` intact while replacing the OS image underneath.

## Building Your Own Image

You can use any Bootcrew image as a `FROM` base in your own Containerfile. This is the right path if you want remote access, extra packages, or opinionated defaults.

If you only want to use a published image as-is, go back to [Quick Start](#quick-start) instead.

You can do this from any Linux host with Podman. You do not need to install one of these images first.

One straightforward flow looks like this:

1. Create a `Containerfile` for your derived image.

```dockerfile
FROM ghcr.io/bootcrew/debian-bootc:latest

RUN apt update -y && \
    apt install -y sudo openssh-server && \
    systemctl enable ssh && \
    apt clean -y
```

This example starts from Debian and adds SSH so the SSH key in `config.toml` can actually be used after first boot. Replace `debian-bootc` with any published Bootcrew image if you want to start from a different distro.

Package and service names vary by distro: Debian and Ubuntu typically use `openssh-server` and `ssh`, while Arch Linux and openSUSE typically use `openssh` and `sshd`.

2. Create a `config.toml` for first boot so the installed system is immediately usable. Start with the same `config.toml` pattern from [Quick Start](#quick-start). If you want a non-root admin user instead of relying on the temporary `root` password, add `groups = ["sudo"]` or `groups = ["wheel"]` to match how your image configures `sudo`. If your derived image installs and enables SSH, you can also add a `key = "ssh-rsa AAAA... user@host"` line under the same `[[customizations.user]]` entry.

3. Build your derived image locally.

```bash
sudo podman build -t my-server:latest -f Containerfile .
```

4. Generate a bootable disk image from that local container image.

```bash
mkdir -p output

sudo podman run \
  --rm -it --privileged \
  --security-opt label=type:unconfined_t \
  -v ./config.toml:/config.toml:ro \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  localhost/my-server:latest
```

bootc-image-builder resolves image references from the mounted `/var/lib/containers/storage`, so locally-built images are found automatically. Change `--type qcow2` to `--type raw` if you want a bare-metal image instead of a VM image.

5. Boot or install it.

Follow [Create A VM](#create-a-vm) for `qcow2` output or [Install On Bare Metal](#install-on-bare-metal) for `raw` output to actually boot and install your custom image.

## Building The Images From Source

If you want to rebuild the Bootcrew base images locally rather than consume the published ones, use this section:

Prerequisites:

- Linux host
- rootful Podman
- `just`

```bash
git clone https://github.com/bootcrew/mono.git
cd mono
just build debian
just build arch
just build ubuntu
just build opensuse
```

This builds the container images locally. Turn a local image into a disk image with bootc-image-builder:

```bash
sudo podman run \
  --rm -it --privileged \
  --security-opt label=type:unconfined_t \
  -v ./config.toml:/config.toml:ro \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  localhost/debian-bootc:latest
```

Replace `localhost/debian-bootc:latest` with the local image you built. Then follow [Create A VM](#create-a-vm) for `qcow2` output or [Install On Bare Metal](#install-on-bare-metal) for `raw` output.

## Forking This Repo

If you want to publish and maintain your own fork in GHCR with GitHub Actions rather than only customize images locally, use this section:

1. Fork this repository.
2. Pick the distro images you want to maintain.
3. Remove or disable workflows you do not plan to use.
4. Make your changes in the relevant distro directory.
5. Build locally to validate.
6. Push to a branch to run CI validation.
7. Merge to your default branch to publish to your own GHCR namespace.

Published images go to `ghcr.io/<your-user>/<image-name>:latest`. Before relying on publishing:

- GitHub Actions must be enabled on the fork
- the workflow you want must be present and enabled
- merging to the default branch is what triggers publishing
- the workflows sign published images with cosign by default — you must configure the `SIGNING_SECRET` repository secret with a cosign private key, or publishing will fail. To disable signing, remove the signing steps from the workflows

Helpful references:

- Fork a repository: <https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo>
- Disabling and enabling a workflow: <https://docs.github.com/en/actions/how-tos/manage-workflow-runs/disable-and-enable-workflows>
- Working with the Container registry (`ghcr.io`): <https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry>
- Using secrets in GitHub Actions: <https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets>
- Cosign key generation for `SIGNING_SECRET`: <https://docs.sigstore.dev/cosign/key_management/signing_with_self-managed_keys/>

## SELinux Hosts

If SELinux is `Permissive`, `Disabled`, or not present in the Linux environment running Podman, you can usually skip this section.

Check whether you need the extra host policy package:

```bash
getenforce
```

If that prints `Enforcing`, install `osbuild-selinux` before running `bootc-image-builder`. This is the host SELinux policy that allows the builder to do the mount and image-construction work it needs. Without it, builds on enforcing systems often fail with SELinux permission errors even when the container is run as `--privileged`.

If your distro does not ship that exact package name, install the equivalent osbuild SELinux policy package for your host. If it is unavailable in your configured repos, use a different build host or add it to the image you use as your build host.

```bash
# Package-based hosts
sudo dnf install -y osbuild-selinux

# rpm-ostree / bootc hosts such as Fedora Atomic or Universal Blue
sudo rpm-ostree install osbuild-selinux
sudo systemctl reboot
```

You can of course temporarily disable SELinux with `sudo setenforce 0` and later turn it back on with `sudo setenforce 1`, but that would make Dan Walsh cry! ;) See [stopdisablingselinux.com](https://stopdisablingselinux.com/).
