#!/bin/bash
set -e

# OpenClaw CLI — open-source agentic coding assistant
# Installs globally via npm.

VERSION="${VERSION:-"latest"}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/openclaw"

echo "Installing OpenClaw CLI (version: ${VERSION})..."

# Install npm if not available (openclaw is installed via npm, not curl)
if ! command -v npm &> /dev/null; then
    echo "Error: npm is required to install OpenClaw CLI. Add the node feature before this one." >&2
    exit 1
fi

# Install OpenClaw CLI globally via npm
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    npm install -g --ignore-scripts openclaw@latest
else
    npm install -g --ignore-scripts openclaw@"${VERSION}"
fi
# Explicitly run postinstall to install native binaries
npm rebuild -g openclaw 2>&1 || { echo "Error: openclaw native binary setup failed" >&2; exit 1; }

# Locate the installed binary from npm's global bin directory (not PATH)
NPM_GLOBAL_BIN="$(npm config get prefix 2>/dev/null || true)/bin"
OPENCLAW_BIN="$NPM_GLOBAL_BIN/openclaw"

if [[ ! -x "$OPENCLAW_BIN" ]]; then
    echo "OpenClaw CLI installation failed: binary not found at $OPENCLAW_BIN" >&2
    exit 1
fi

if [[ -n "$OPENCLAW_BIN" && "$OPENCLAW_BIN" != "/usr/local/bin/openclaw" ]]; then
    ln -sf "$OPENCLAW_BIN" /usr/local/bin/openclaw
fi
echo "OpenClaw CLI linked to /usr/local/bin/openclaw"

# Profile.d for login shells
# Use REMOTE_USER_HOME (resolved at build time) instead of $HOME, which may be
# set to "/" on OpenShift restricted SCC.
cat > /etc/profile.d/openclaw.sh << EOF
export OPENCLAW_STATE_DIR="\${OPENCLAW_STATE_DIR:-$REMOTE_USER_HOME/.openclaw}"
EOF
chmod 0755 /etc/profile.d/openclaw.sh

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.openclaw to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        target="$REMOTE_USER_HOME/.openclaw"
        if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
            mv "$target" "$AGENT_DIR/config-legacy"
        fi
        parent=$(dirname "$target")
        mkdir -p "$parent"
        rm -f "$target"
        if id -u "$REMOTE_USER" >/dev/null 2>&1; then
            chown "$REMOTE_USER:" "$parent" 2>/dev/null || true
            su -s /bin/bash - "$REMOTE_USER" -c "ln -sfn '$AGENT_DIR' '$target'"
        else
            ln -sfn "$AGENT_DIR" "$target"
        fi
    fi
    echo "OpenClaw configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v openclaw >/dev/null 2>&1; then
    OUT=$(openclaw --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "OpenClaw CLI version: ${OUT}"
    else
        echo "OpenClaw CLI: version check skipped (exit ${RC})"
    fi
else
    echo "OpenClaw CLI: binary not on PATH; skipping version check"
fi
set -e

echo "OpenClaw CLI installed successfully!"
