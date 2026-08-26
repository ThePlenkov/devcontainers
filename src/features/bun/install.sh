#!/bin/bash
set -e

# Bun JavaScript Runtime Installation Script

REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-/home/$REMOTE_USER}"

echo "Installing Bun JavaScript runtime..."

if ! command -v bun &> /dev/null; then
    echo "Installing Bun via official installer..."
    su -s /bin/bash - "$REMOTE_USER" -c \
        "export PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH'; curl -fsSL https://bun.sh/install | bash"
fi

# Source bun env to get the binary path
BUN_BIN="$REMOTE_USER_HOME/.bun/bin/bun"
if [ -x "$BUN_BIN" ]; then
    ln -sf "$BUN_BIN" /usr/local/bin/bun
fi

echo "Bun installed successfully!"
bun --version
