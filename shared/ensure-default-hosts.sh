#!/usr/bin/env bash

set -euo pipefail

# Preserve any real local customization, but repair missing or blank files.
if [ -e /etc/hosts ] && grep -q '[^[:space:]]' /etc/hosts; then
    exit 0
fi

if [ -e /usr/etc/hosts ] && grep -q '[^[:space:]]' /usr/etc/hosts; then
    install -m 0644 /usr/etc/hosts /etc/hosts
    exit 0
fi

cat > /etc/hosts <<'EOF'
127.0.0.1 localhost localhost.localdomain localhost4 localhost4.localdomain4
::1 localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF
