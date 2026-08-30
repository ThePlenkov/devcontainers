#!/bin/bash
set -e

# Qwen Code CLI — Alibaba's agentic coding assistant
# Installs globally via npm.

VERSION="${VERSION:-"latest"}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/qwen-code"

echo "Installing Qwen Code CLI (version: ${VERSION})..."

# Ensure npm is available
if ! command -v npm &> /dev/null; then
    echo "Error: npm is required to install Qwen Code CLI. Add the node feature before this one." >&2
    exit 1
fi

# Install Qwen Code CLI globally via npm
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    npm install -g --ignore-scripts @qwen-code/qwen-code
else
    npm install -g --ignore-scripts @qwen-code/qwen-code@"${VERSION}"
fi

# Locate the installed binary from npm's global bin directory (not PATH)
NPM_GLOBAL_BIN="$(npm bin -g 2>/dev/null || true)"
if [[ ! -d "$NPM_GLOBAL_BIN" ]]; then
    NPM_GLOBAL_BIN="$(npm config get prefix 2>/dev/null || true)/bin"
fi
QWEN_BIN="$NPM_GLOBAL_BIN/qwen"

if [[ ! -x "$QWEN_BIN" ]]; then
    echo "Qwen Code CLI installation failed: binary not found at $QWEN_BIN" >&2
    exit 1
fi

ln -sf "$QWEN_BIN" /usr/local/bin/qwen
echo "Qwen Code CLI linked to /usr/local/bin/qwen"

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.qwen to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        target="$REMOTE_USER_HOME/.qwen"
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
    echo "Qwen Code configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v qwen >/dev/null 2>&1; then
    OUT=$(qwen --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "Qwen Code CLI version: ${OUT}"
    else
        echo "Qwen Code CLI: version check skipped (exit ${RC})"
    fi
else
    echo "Qwen Code CLI: binary not on PATH; skipping version check"
fi
set -e

echo "Qwen Code CLI installed successfully!"
