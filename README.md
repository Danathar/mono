# Bootcrew

Bootcrew publishes minimal, bootable [`bootc`](https://github.com/bootc-dev/bootc) container images for multiple Linux distributions. You can use them directly or as a base to build your own images.

## Published Images

| Image | Reference | Architecture(s) |
| --- | --- | --- |
| Arch Linux | `ghcr.io/bootcrew/arch-bootc:latest` | `amd64` |
| Debian | `ghcr.io/bootcrew/debian-bootc:latest` | `amd64`, `arm64` |
| Ubuntu | `ghcr.io/bootcrew/ubuntu-bootc:latest` | `amd64`, `arm64` |
| openSUSE Tumbleweed | `ghcr.io/bootcrew/opensuse-bootc:latest` | `amd64`, `arm64` |

All images are base / CLI images. None include a desktop environment, display manager, or user-facing services. They are intended as a starting point — add what you need in your own layer.

Images are rebuilt weekly to pick up distro package updates and new upstream `bootc` commits.

## Objective

None of these should need to exist. Ideally all of these projects would directly publish `(project-name)-bootc` images, or at least provide a `bootc` package or bundle for it. These images aim to be as small and basic as possible to minimize maintenance burden and make it easier to upstream any efforts from them.

## Quick Start

Pull a published image and generate a bootable disk image with [bootc-image-builder](https://github.com/osbuild/bootc-image-builder):

```bash
mkdir -p output

sudo podman run \
  --rm -it --privileged \
  --security-opt label=type:unconfined_t \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  ghcr.io/bootcrew/debian-bootc:latest
```

This creates `output/qcow2/disk.qcow2` ready to boot in a VM.

Replace `debian-bootc` with any image from the table above. Replace `--type qcow2` with the output format you need (see [Output Formats](#output-formats) below).

## Adding A User For First Boot

The published images do not create a loginable user. To add one, create a `config.toml` and pass it to bootc-image-builder:

```toml
[[customizations.user]]
name = "<username>"
password = "<temporary-password>"
groups = ["wheel"]
```

Then mount it when building the disk image:

```bash
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

You can also use an SSH key instead of (or in addition to) a password:

```toml
[[customizations.user]]
name = "<username>"
key = "ssh-rsa AAAA... user@host"
groups = ["wheel"]
```

For Debian and Ubuntu images, use `"sudo"` instead of `"wheel"` for the group name.

Rotate or remove temporary passwords after first boot.

## Output Formats

bootc-image-builder supports multiple output types via the `--type` flag:

| Type | Use case |
| --- | --- |
| `qcow2` | QEMU / libvirt VMs (default) |
| `raw` | Direct disk write or loopback mount |
| `vmdk` | VMware / vSphere |
| `vhd` | Hyper-V |
| `ami` | Amazon EC2 |
| `gce` | Google Compute Engine |
| `iso` | Anaconda-based installer ISO |

You can specify multiple types in one run: `--type qcow2 --type raw`.

## Create A VM

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

To recreate the VM:

```bash
virsh -c qemu:///session destroy bootc-local || true
virsh -c qemu:///session undefine bootc-local --nvram || true
```

Then run the `virt-install` command again.

## Install On Bare Metal

Generate a raw disk image:

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

Write the image:

```bash
sudo dd if=output/image/disk.raw of=/dev/nvme0n1 bs=16M status=progress oflag=direct conv=fsync
sync
```

Check the `output/` directory for the exact filename if your version of bootc-image-builder uses a different layout.

`dd` erases the target disk completely. Double-check `of=` before you run it. Keep Secure Boot disabled unless you manage your own signed boot chain.

## Updating Installed Systems

Once a system is installed, update it by pulling a newer version of the image:

```bash
sudo bootc upgrade
sudo reboot
```

Or switch to a different image entirely:

```bash
sudo bootc switch ghcr.io/bootcrew/arch-bootc:latest
sudo reboot
```

Your local users and host state persist across image updates under `/etc` and `/var/home`.

## Building Your Own Image

You can use any Bootcrew image as a `FROM` base in your own Containerfile:

```dockerfile
FROM ghcr.io/bootcrew/debian-bootc:latest

RUN apt update -y && \
    apt install -y nginx sudo openssh-server && \
    systemctl enable nginx && \
    systemctl enable ssh && \
    apt clean -y
```

Build and generate a disk image from your derived image:

```bash
sudo podman build -t my-server:latest -f Containerfile .

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

bootc-image-builder resolves image references from the mounted `/var/lib/containers/storage`, so locally-built images are found automatically.

## Building The Images From Source

If you want to build the Bootcrew images themselves rather than consuming them:

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

This builds the container images locally. To turn one into a disk image, use bootc-image-builder as described above, or use the included `just disk-image` recipe:

```bash
just disk-image debian
```

This creates `./bootable.img` via `bootc install to-disk`. Note that images built this way have no user credentials — use bootc-image-builder with a `config.toml` if you need first-boot access.

## Forking This Repo

If you want to publish your own customized images via GitHub Actions:

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
- if you keep signing enabled, configure the `SIGNING_SECRET` repository secret
