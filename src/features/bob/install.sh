#!/bin/bash
set -e

# Bob Shell Installation Script

VERSION="${VERSION:-"latest"}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-$(eval echo ~$REMOTE_USER)}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/bob"
SHARE_CONFIG="${SHARECONFIG:-false}"

echo "Installing Bob Shell ${VERSION}..."

if [[ "$VERSION" = "latest" ]]; then
    npm install -g --ignore-scripts @roo-code/bob-shell
else
    npm install -g --ignore-scripts @roo-code/bob-shell@"$VERSION"
fi

if command -v bob &> /dev/null; then
    echo "Bob Shell installed successfully!"
    bob --version || true
else
    echo "Warning: Bob Shell installation completed but 'bob' command not found in PATH" >&2
fi

# Shared agent config for Bob
if [[ "$SHARE_CONFIG" == "true" ]]; then
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:$REMOTE_USER" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        for target in "$REMOTE_USER_HOME/.bob" "$REMOTE_USER_HOME/.config/bob"; do
            if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
                mv "$target" "$AGENT_DIR/$(basename "$target")-legacy"
            fi
            parent=$(dirname "$target")
            mkdir -p "$parent"
            rm -f "$target"
            if id -u "$REMOTE_USER" >/dev/null 2>&1; then
                chown "$REMOTE_USER:$REMOTE_USER" "$parent" 2>/dev/null || true
                su -s /bin/bash - "$REMOTE_USER" -c "ln -sfn '$AGENT_DIR' '$target'"
            else
                ln -sfn "$AGENT_DIR" "$target"
            fi
        done
    fi
    echo "Bob Shell configured to use $AGENT_DIR"
fi
