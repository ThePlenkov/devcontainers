#!/bin/bash
set -e

# Cline CLI — open-source agentic coding assistant
# Installs globally via npm.

VERSION="${VERSION:-"latest"}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/cline"

echo "Installing Cline CLI (version: ${VERSION})..."

if ! command -v npm &> /dev/null; then
    echo "Error: npm is required to install Cline CLI. Add the node feature before this one." >&2
    exit 1
fi

# Install Cline CLI globally via npm
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    npm install -g --ignore-scripts cline
else
    npm install -g --ignore-scripts cline@"${VERSION}"
fi
npm rebuild -g @anthropic-ai/cline 2>/dev/null || true

# Locate the installed binary and copy it to /usr/local/bin
NPM_GLOBAL_BIN="$(npm config get prefix 2>/dev/null || true)/bin"
CLINE_BIN="$NPM_GLOBAL_BIN/cline"

if [[ ! -x "$CLINE_BIN" ]]; then
    echo "Cline CLI installation failed: binary not found at $CLINE_BIN" >&2
    exit 1
fi

if [[ -n "$CLINE_BIN" && "$CLINE_BIN" != "/usr/local/bin/cline" ]]; then
    ln -sf "$CLINE_BIN" /usr/local/bin/cline
fi
echo "Cline CLI linked to /usr/local/bin/cline"

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.cline to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        target="$REMOTE_USER_HOME/.cline"
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
    echo "Cline configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v cline >/dev/null 2>&1; then
    OUT=$(cline --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "Cline CLI version: ${OUT}"
    else
        echo "Cline CLI: version check skipped (exit ${RC})"
    fi
else
    echo "Cline CLI: binary not on PATH; skipping version check"
fi
set -e

echo "Cline CLI installed successfully!"
