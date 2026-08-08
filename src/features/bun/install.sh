#!/bin/bash
set -e

# Bun JavaScript Runtime Installation Script

REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"

echo "Verifying Bun JavaScript runtime..."

export PATH="$HOMEBREW_PREFIX/bin:$PATH"

if ! command -v bun &> /dev/null; then
    echo "Bun not found; installing via Homebrew..."
    if command -v brew &> /dev/null; then
        su -s /bin/bash - "$REMOTE_USER" -c \
            "export PATH='$HOMEBREW_PREFIX/bin:\$PATH'; brew install oven-sh/bun/bun"
    else
        echo "Error: Homebrew not found. The homebrew feature must be installed first." >&2
        exit 1
    fi
fi

# Expose bun binary globally
if [ -x "$HOMEBREW_PREFIX/bin/bun" ]; then
    ln -sf "$HOMEBREW_PREFIX/bin/bun" /usr/local/bin/bun
fi

echo "Bun installed successfully!"
bun --version
