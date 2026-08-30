#!/bin/bash
set -e

# GitHub Copilot CLI — GitHub's standalone terminal AI agent
# Installs the @github/copilot npm package globally.

VERSION="${VERSION:-"latest"}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/copilot"

echo "Installing GitHub Copilot CLI (version: ${VERSION})..."

# Ensure npm is available
if ! command -v npm &> /dev/null; then
    echo "Error: npm is required to install Copilot CLI. Add the node feature before this one." >&2
    exit 1
fi

# Install Copilot CLI globally
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    npm install -g --ignore-scripts @github/copilot
else
    npm install -g --ignore-scripts @github/copilot@"${VERSION}"
fi
npm rebuild -g @github/copilot 2>/dev/null || true

# Locate and link the binary to /usr/local/bin
NPM_GLOBAL_BIN="$(npm config get prefix 2>/dev/null || true)/bin"
COPILOT_BIN="$NPM_GLOBAL_BIN/copilot"

if [[ -x "$COPILOT_BIN" ]]; then
    if [[ -n "$COPILOT_BIN" && "$COPILOT_BIN" != "/usr/local/bin/copilot" ]]; then
        ln -sf "$COPILOT_BIN" /usr/local/bin/copilot
    fi
    echo "Copilot CLI linked to /usr/local/bin/copilot"
else
    echo "Error: Copilot CLI binary not found at $COPILOT_BIN" >&2
    exit 1
fi

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.copilot to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        target="$REMOTE_USER_HOME/.copilot"
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
    echo "Copilot CLI configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v copilot >/dev/null 2>&1; then
    OUT=$(copilot --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "Copilot CLI version: ${OUT}"
    else
        echo "Copilot CLI: version check skipped (exit ${RC})"
    fi
fi
set -e

echo "GitHub Copilot CLI installed successfully!"
echo "Note: Set COPILOT_GITHUB_TOKEN or GH_TOKEN for non-interactive authentication."
