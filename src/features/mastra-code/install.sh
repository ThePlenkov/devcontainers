#!/bin/bash
set -e

# Mastra Code CLI — agentic coding assistant
# Installs globally via npm.

VERSION="${VERSION:-"latest"}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/mastra-code"

echo "Installing Mastra Code CLI (version: ${VERSION})..."

# Install npm if not available
if ! command -v npm &> /dev/null; then
    echo "Error: npm is required to install Mastra Code CLI. Add the node feature before this one." >&2
    exit 1
fi

# Install Mastra Code CLI globally via npm
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    npm install -g --ignore-scripts mastracode
else
    npm install -g --ignore-scripts mastracode@"${VERSION}"
fi
npm rebuild -g mastracode 2>&1 || { echo "Error: mastra-code native binary setup failed" >&2; exit 1; }

# Locate the installed binary from npm's global bin directory (not PATH)
NPM_GLOBAL_BIN="$(npm config get prefix 2>/dev/null || true)/bin"
MASTRACODE_BIN="$NPM_GLOBAL_BIN/mastracode"

if [[ ! -x "$MASTRACODE_BIN" ]]; then
    echo "Mastra Code CLI installation failed: binary not found at $MASTRACODE_BIN" >&2
    exit 1
fi

if [[ -n "$MASTRACODE_BIN" && "$MASTRACODE_BIN" != "/usr/local/bin/mastracode" ]]; then
    ln -sf "$MASTRACODE_BIN" /usr/local/bin/mastracode
fi
echo "Mastra Code CLI linked to /usr/local/bin/mastracode"

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.config/mastracode to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        target="$REMOTE_USER_HOME/.config/mastracode"
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
    echo "Mastra Code configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v mastracode >/dev/null 2>&1; then
    OUT=$(mastracode --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "Mastra Code CLI version: ${OUT}"
    else
        echo "Mastra Code CLI: version check skipped (exit ${RC})"
    fi
else
    echo "Mastra Code CLI: binary not on PATH; skipping version check"
fi
set -e

echo "Mastra Code CLI installed successfully!"
