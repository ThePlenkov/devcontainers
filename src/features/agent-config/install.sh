#!/bin/bash
set -e

# Shared Agent Config
# Creates the root directory used by all agent features to share config.

CONFIG_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"

mkdir -p "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"

if id -u "$REMOTE_USER" >/dev/null 2>&1; then
    chown "$REMOTE_USER:$REMOTE_USER" "$CONFIG_DIR"
fi

# Make AGENT_CONFIG_DIR available in login shells as well.
cat > /etc/profile.d/agent-config.sh << EOF
export AGENT_CONFIG_DIR="$CONFIG_DIR"
EOF
chmod +x /etc/profile.d/agent-config.sh

echo "Shared agent config directory ready at $CONFIG_DIR"
