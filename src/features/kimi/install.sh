#!/bin/bash
set -e

# Kimi Code CLI — Moonshot AI's agentic coding assistant
# Installs globally via npm.

VERSION="${VERSION:-"latest"}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/kimi"

echo "Installing Kimi Code CLI (version: ${VERSION})..."

# Install curl and npm if not available
if ! command -v curl &> /dev/null; then
    apt-get update -y && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
fi

if ! command -v npm &> /dev/null; then
    echo "Error: npm is required to install Kimi Code CLI. Add the node feature before this one." >&2
    exit 1
fi

# Install Kimi Code CLI globally via npm
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    npm install -g --ignore-scripts @moonshot-ai/kimi-code
else
    npm install -g --ignore-scripts @moonshot-ai/kimi-code@"${VERSION}"
fi

# Locate the installed binary and copy it to /usr/local/bin
KIMI_BIN="$(command -v kimi || true)"
if [[ -z "$KIMI_BIN" ]]; then
    NPM_GLOBAL_BIN="$(npm bin -g 2>/dev/null || true)"
    if [[ ! -d "$NPM_GLOBAL_BIN" ]]; then
        NPM_GLOBAL_BIN="$(npm config get prefix 2>/dev/null || true)/bin"
    fi
    KIMI_BIN="$NPM_GLOBAL_BIN/kimi"
fi

if [[ ! -x "$KIMI_BIN" ]]; then
    echo "Kimi Code CLI installation failed: binary not found at $KIMI_BIN" >&2
    exit 1
fi

cp "$KIMI_BIN" /usr/local/bin/kimi
chmod +x /usr/local/bin/kimi
echo "Kimi Code CLI copied to /usr/local/bin/kimi"

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.kimi to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        target="$REMOTE_USER_HOME/.kimi"
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
    echo "Kimi Code configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v kimi >/dev/null 2>&1; then
    OUT=$(kimi --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "Kimi Code CLI version: ${OUT}"
    else
        echo "Kimi Code CLI: version check skipped (exit ${RC})"
    fi
else
    echo "Kimi Code CLI: binary not on PATH; skipping version check"
fi
set -e

echo "Kimi Code CLI installed successfully!"
