#!/usr/bin/env bash

# `-e` exits on the first failure.
# `-x` prints commands so logs are easy to follow.
# `-u` treats unset variables as errors.
# `pipefail` makes pipelines fail if any stage fails.
set -xeuo pipefail

# This script runs inside the builder stage of each Containerfile.
# Cloning into the current directory keeps the build isolated from the final image.
git clone "https://github.com/bootc-dev/bootc.git" .

# Install into `/output` instead of `/` so the final image can copy in only the
# compiled artifacts and not the full builder environment.
make bin install-all DESTDIR=/output
