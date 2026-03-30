# Bootcrew

This is a monorepo for all the Bootcrew images! These are multiple different container images made for usage with [`bootc`](https://github.com/bootc-dev/bootc), they can be used as a base to build upon and make your own full images for your usecase, similar to the work from the [Fedora Bootc Base Images](https://docs.fedoraproject.org/en-US/bootc/base-images/) and [Universal Blue](http://universal-blue.org/).

## Image Documentation

- [Arch Linux](arch/README.md)
- [Debian](debian/README.md)

## Building and Running

In order to get a running system you can run `just build (subdirectory)`, then generate a disk image with `just disk-image (subdirectory)` for any of the images to be used.

## Using this repo as a fork

If you want to make your own version of one of these images, the recommended approach is:

1. Fork this repository to your own GitHub account.
2. Pick the image directory you want to customize, such as `ubuntu/`, `debian/`, `arch/`, or `opensuse/`.
3. Make your changes in that image directory.
4. Build it locally once to validate your changes.
5. Push your changes to your fork and let GitHub Actions build and publish updated images for you.

### Important: by default, a fork will build all images

This repository contains separate GitHub Actions workflows for multiple images. If you fork the repo as-is, pushes and scheduled workflow runs can build all image variants, not only the one you changed.

If you only want your fork to build one image, keep only the workflow for the image you care about and remove or disable the others.

For example, if you only want to build the Ubuntu image, keep:

- `.github/workflows/build-ubuntu.yaml`

and remove or disable:

- `.github/workflows/build-arch.yaml`
- `.github/workflows/build-debian.yaml`
- `.github/workflows/build-opensuse.yaml`

### Scheduled rebuilds

If your goal is to stay up to date over time, you do not need to keep rebuilding locally.

The intended pattern is:

- build locally once for validation
- use GitHub Actions in your fork for ongoing rebuilds
- consume the published image from your GitHub Container Registry namespace

The workflows in this repo are already configured to run on a schedule, so once your fork is set up the scheduled builds can keep your published image refreshed.

### Publishing from your fork

The reusable workflow publishes images to the GitHub Container Registry for the current repository owner. That means when run from your fork, the image is published under your own namespace rather than the upstream `bootcrew` namespace.

If your GitHub username is `your-username` and you keep the Ubuntu image name unchanged, the published image would look like:

`ghcr.io/your-username/ubuntu-bootc:latest`

### Recommended setup for a single-image fork

If you only want one maintained image in your fork, a good setup is:

1. Keep only the image directory you want to customize.
2. Keep only that image's workflow.
3. Optionally rename the image in the workflow so the published package name is specific to your project.
4. Let scheduled GitHub Actions rebuild and republish it.

This keeps the fork simple and avoids wasting CI time building images you do not use.

### Objective

None of these should need to exist, ideally all of these projects would directly publish `(project-name)-bootc` images, or at least provide a `bootc` package or bundle for it. We aim to make our images as small and basic as possible to minimize maintenance burden and make it easier to upstream any effors from them..