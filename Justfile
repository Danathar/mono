# These variables let the same recipes work in local development and CI.
# Callers can override them with environment variables instead of editing this file.
image_name := env("BUILD_IMAGE_NAME", "")
image_tag := env("BUILD_IMAGE_TAG", "latest")
base_dir := env("BUILD_BASE_DIR", ".")
filesystem := env("BUILD_FILESYSTEM", "ext4")
selinux := env("BUILD_SELINUX", "true")

# SELinux-aware bind mounts need `:Z` relabeling and a more permissive label option.
# On hosts without SELinux, the simpler bind mounts are enough.
options := if selinux == "true" { "-v /var/lib/containers:/var/lib/containers:Z -v /etc/containers:/etc/containers:Z -v /sys/fs/selinux:/sys/fs/selinux --security-opt label=type:unconfined_t" } else { "-v /var/lib/containers:/var/lib/containers -v /etc/containers:/etc/containers" }

# Prefer Podman because these images rely on features common in rootful system-image
# workflows, but fall back to Docker so the recipes still work on more machines.
container_runtime := env("CONTAINER_RUNTIME", `command -v podman >/dev/null 2>&1 && echo podman || echo docker`)

# Build a distro directory such as `ubuntu/` or `debian/` into a local
# `*-bootc:latest` image.  An optional target selects a specific stage from
# multi-stage Containerfiles (e.g. `just build arch kde`).
build $image_name=image_name target="":
    # Building these system images often needs rootful container runtime access.
    sudo {{container_runtime}} build -f {{image_name}}/Containerfile {{ if target != "" { "--target " + target } else { "" } }} -t "${image_name}-bootc:latest" .

# Run the built image and forward arbitrary `bootc` subcommands into it.
# Reuses host devices and container storage so `bootc install` can create
# loop devices and disk images from inside the container.
bootc $image_name=image_name $image_tag=image_tag *ARGS:
    sudo {{container_runtime}} run \
        --rm --privileged --pid=host \
        -it \
        {{options}} \
        -v /dev:/dev \
        -e RUST_LOG=debug \
        -v "{{base_dir}}:/data" \
        "${image_name}-bootc:${image_tag}" bootc {{ARGS}}

# Turn the container image into a bootable disk image file on the host.
disk-image $image_name=image_name $image_tag=image_tag $base_dir=base_dir $filesystem=filesystem:
    #!/usr/bin/env bash
    # Create a sparse 20 GiB file once and reuse it for later test installs.
    if [ ! -e "${base_dir}/bootable.img" ] ; then
        fallocate -l 20G "${base_dir}/bootable.img"
    fi
    # `bootc install to-disk` writes a full bootable OS into the image file.
    # `--via-loopback` treats the file as a block device and `--wipe` allows reruns.
    just bootc $image_name $image_tag install to-disk --composefs-backend --via-loopback /data/bootable.img --filesystem "${filesystem}" --wipe --bootloader systemd

# Rechunk the image into a layer layout that is friendlier for OSTree-style
# distribution and deduplication.
rechunk $image_name=image_name:
    #!/usr/bin/env bash
    # `chunkah` expects the image configuration as JSON in this environment variable.
    export CHUNKAH_CONFIG_STR="$(podman inspect "${image_name}-bootc")"
    # Pipeline summary:
    # 1. mount the local image into `chunkah`
    # 2. rebuild it with chunk-friendly layers
    # 3. load the rebuilt image back into Podman
    # 4. extract the temporary image ID
    # 5. retag that result back to the original local image name
    podman run --rm "--mount=type=image,src=${image_name}-bootc,dest=/chunkah" -e CHUNKAH_CONFIG_STR quay.io/jlebon/chunkah build --label ostree.bootable=1 --compressed --max-layers 128 | \
        podman load | \
        sort -n | \
        head -n1 | \
        cut -d, -f2 | \
        cut -d: -f3 | \
        xargs -I{} podman tag {} "${image_name}-bootc"
