#!/bin/bash
set -e

# Cursor Agent CLI Installation Script

REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-$(eval echo ~$REMOTE_USER)}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/cursor"
SHARE_CONFIG="${SHARECONFIG:-false}"

echo "Installing Cursor Agent CLI for user $REMOTE_USER..."

# Ensure curl is available
if ! command -v curl &> /dev/null; then
    apt-get update -y && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
fi

if ! id -u "$REMOTE_USER" >/dev/null 2>&1; then
    echo "Error: remote user '$REMOTE_USER' does not exist." >&2
    exit 1
fi

# Run the official installer as the remote user so the agent is installed
# under the home directory and not as root.
su -s /bin/bash - "$REMOTE_USER" -c \
    'NO_COLOR=1 /bin/bash -c "$(curl --proto =https -fsSL https://cursor.com/install)"'

# Expose Cursor agent binaries system-wide
for bin in agent cursor-agent; do
    if [[ -x "$REMOTE_USER_HOME/.local/bin/$bin" ]]; then
        ln -sfn "$REMOTE_USER_HOME/.local/bin/$bin" "/usr/local/bin/$bin"
    fi
done

# Link the cursor binary itself, guarding against self-link
CURSOR_BIN="$REMOTE_USER_HOME/.local/bin/cursor"
if [[ -n "$CURSOR_BIN" && -x "$CURSOR_BIN" && "$CURSOR_BIN" != "/usr/local/bin/cursor" ]]; then
    ln -sf "$CURSOR_BIN" /usr/local/bin/cursor
fi

# Shared agent config for Cursor
if [[ "$SHARE_CONFIG" == "true" ]]; then
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:$REMOTE_USER" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        if [[ -e "$REMOTE_USER_HOME/.cursor" ]] && [[ ! -L "$REMOTE_USER_HOME/.cursor" ]]; then
            mv "$REMOTE_USER_HOME/.cursor" "$AGENT_DIR/legacy-cursor"
        fi
        rm -f "$REMOTE_USER_HOME/.cursor"
        su -s /bin/bash - "$REMOTE_USER" -c "ln -sfn '$AGENT_DIR' '$REMOTE_USER_HOME/.cursor'" 2>/dev/null || true
    fi

    # Only export CURSOR_CONFIG_DIR when shareConfig is enabled
    cat > /etc/profile.d/cursor.sh << EOF
export CURSOR_CONFIG_DIR="$AGENT_DIR"
EOF
    chmod +x /etc/profile.d/cursor.sh
else
    # shareConfig is false — remove any pre-existing profile.d script
    # so CURSOR_CONFIG_DIR is not set unconditionally.
    if [[ -f /etc/profile.d/cursor.sh ]] && grep -q "CURSOR_CONFIG_DIR\|cursor.*AGENT_DIR\|Cursor.*feature" /etc/profile.d/cursor.sh 2>/dev/null; then
        rm -f /etc/profile.d/cursor.sh
    fi

    # Remove legacy ~/.cursor symlink if it points to this feature's AGENT_DIR
    if [[ -L "$REMOTE_USER_HOME/.cursor" ]]; then
        link_dest=$(readlink "$REMOTE_USER_HOME/.cursor" 2>/dev/null || true)
        if [[ "$link_dest" == "$AGENT_DIR" ]]; then
            rm -f "$REMOTE_USER_HOME/.cursor"
        fi
    fi
fi

echo "Cursor Agent CLI installed successfully!"
