#!/bin/bash
set -e

# Kilo CLI installation script for Devcontainers.

REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-$(eval echo ~$REMOTE_USER)}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/kilo"
HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"

echo "Installing Kilo CLI and dependencies..."

# Install apt-level dependency for notifications
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y libnotify-bin
    rm -rf /var/lib/apt/lists/*
else
    echo "Warning: apt-get not available; skipping libnotify-bin install" >&2
fi

# Install Kilo via Homebrew if not already present
export PATH="$HOMEBREW_PREFIX/bin:$PATH"
if ! command -v kilo &> /dev/null; then
    if command -v brew &> /dev/null; then
        su -s /bin/bash - "$REMOTE_USER" -c \
            "export PATH='$HOMEBREW_PREFIX/bin:\$PATH'; brew install Kilo-Org/tap/kilo"
    else
        echo "Error: Homebrew not found. The homebrew feature must be installed first." >&2
        exit 1
    fi
fi

# Expose kilo globally
if [ -x "$HOMEBREW_PREFIX/bin/kilo" ]; then
    ln -sf "$HOMEBREW_PREFIX/bin/kilo" /usr/local/bin/kilo
fi

# Shared agent config for Kilo
mkdir -p "$AGENT_DIR"
if id -u "$REMOTE_USER" >/dev/null 2>&1; then
    chown -R "$REMOTE_USER:$REMOTE_USER" "$AGENT_DIR"
fi

if [ -d "$REMOTE_USER_HOME" ]; then
    for target in "$REMOTE_USER_HOME/.kilo" "$REMOTE_USER_HOME/.config/kilo"; do
        if [ -e "$target" ] && [ ! -L "$target" ]; then
            mv "$target" "$AGENT_DIR/$(basename "$target")-legacy"
        fi
        parent=$(dirname "$target")
        mkdir -p "$parent"
        rm -f "$target"
        if id -u "$REMOTE_USER" >/dev/null 2>&1; then
            chown "$REMOTE_USER:$REMOTE_USER" "$parent" 2>/dev/null || true
            su -s /bin/bash - "$REMOTE_USER" -c "ln -sfn '$AGENT_DIR' '$target'" 2>/dev/null || true
        else
            ln -sfn "$AGENT_DIR" "$target"
        fi
    done
fi

echo "Kilo CLI installed successfully!"
