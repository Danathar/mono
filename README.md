# Bootcrew

Bootcrew is a monorepo for building and publishing distro-specific [`bootc`](https://github.com/bootc-dev/bootc) images. The intended workflow is:

1. Start from a supported distro image in this repo.
2. Customize its `Containerfile` and any package lists or service settings in that distro directory.
3. Build a container image locally.
4. Either generate a bootable disk image locally or publish the container image from your own fork.
5. Install that image to a VM or disk, then update installed systems with `bootc switch`.

## Supported Images

Ready for use:

- Arch Linux
- Debian

Not ready / experimental:

- Ubuntu
- openSUSE Tumbleweed

Only Arch and Debian are currently maintained as supported user-facing images in this repo. Ubuntu and openSUSE files are present as in-progress work and should not be treated as ready-to-use images.

| Image | Status | Published architecture(s) | Default build result | CI status | Docs |
| --- | --- | --- | --- | --- | --- |
| Arch Linux | Ready | `amd64` | KDE desktop image | push, pull request, schedule | [arch/README.md](arch/README.md) |
| Debian | Ready | `amd64` | Base / CLI image | push, pull request, schedule | [debian/README.md](debian/README.md) |
| Ubuntu | Experimental | not supported yet | present in repo only | manual workflow only | none |
| openSUSE Tumbleweed | Experimental | not supported yet | present in repo only | manual workflow only | none |

## What This Repo Actually Does

- `just build <image>` builds a container image locally.
- `just disk-image <image> [tag]` creates `./bootable.img` by running `bootc install to-disk` inside that image.
- Writing `bootable.img` to a VM disk or physical disk is a separate deployment step.
- `bootc switch <image-ref>` is for a system that is already installed and running.

Important:

- The documented and tested path in this repo uses rootful Podman.
- The default images are bootable, but they do not create a loginable user for you.
- `root` is locked by default in the ready images.
- If you want first-boot access, follow the access-image flow in the Arch or Debian README before you try to boot the result.

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
- package lists or distro-specific files under that image directory
- the matching GitHub workflow if they want to rename the published image or change CI behavior

Most users should not need to touch the shared helper scripts unless they intentionally want to change the underlying bootc filesystem layout or build pipeline.

## Quick Start

Debian base image:

```bash
just build debian
```

Arch KDE image:

```bash
just build arch
```

If you already have another credential injection method, you can turn either one into `bootable.img` directly:

```bash
just disk-image debian
just disk-image arch
```

For a first boot you can actually log into, follow the access-image flow in:

- [arch/README.md](arch/README.md)
- [debian/README.md](debian/README.md)

## Using This Repo As A Fork

For supported images, the recommended pattern is:

1. Fork this repository.
2. Pick either Arch or Debian as your starting point.
3. Remove or disable workflows you do not plan to maintain.
4. Make your image changes in that distro directory.
5. Build locally once to validate the result.
6. Push to a branch to run CI validation.
7. Merge to your default branch to publish updated images to your own GHCR namespace.

If you only want one maintained image in your fork, keep only that image directory and that image's workflow. This keeps the fork simpler and avoids burning CI time on images you do not use.

Do not treat Ubuntu or openSUSE as drop-in alternatives yet. Their files are present, but they are not in the same supported state as Arch and Debian.

## Publishing And CI Behavior

For the supported images in this repo today:

- branch pushes and pull requests build for validation
- publishing happens only on default-branch, non-pull-request runs
- scheduled workflows rebuild and republish the current default-branch image
- published images go to `ghcr.io/<repo-owner>/<image-name>:latest`

Examples:

- `ghcr.io/<your-user>/arch-bootc:latest`
- `ghcr.io/<your-user>/debian-bootc:latest`

Before relying on publishing from your fork, check all of these:

- GitHub Actions is enabled on the fork
- the workflow you want is still present and enabled
- you understand that merging to the default branch is what publishes
- you have decided whether your GHCR package should stay private or be made public
- if you keep signing enabled, you have configured the `SIGNING_SECRET` repository secret

Markdown-only changes do not trigger the Arch and Debian build workflows.
