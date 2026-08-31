#!/bin/bash
set -e

# Amp CLI — Sourcegraph's agentic coding assistant
# Installs globally via npm.

VERSION="${VERSION:-"latest"}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/amp"

echo "Installing Amp CLI (version: ${VERSION})..."

# Install curl and npm if not available
if ! command -v curl &> /dev/null; then
    apt-get update -y && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
fi

if ! command -v npm &> /dev/null; then
    echo "Error: npm is required to install Amp CLI. Add the node feature before this one." >&2
    exit 1
fi

# Install Amp CLI globally via npm
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    npm install -g --ignore-scripts @ampcode/cli
else
    npm install -g --ignore-scripts @ampcode/cli@"${VERSION}"
fi
# Explicitly run postinstall to install native binaries
npm rebuild -g @ampcode/cli 2>&1 || { echo "Error: amp native binary setup failed" >&2; exit 1; }

# Locate the installed binary from npm's global bin directory (not PATH)
NPM_GLOBAL_BIN="$(npm config get prefix 2>/dev/null || true)/bin"
AMP_BIN="$NPM_GLOBAL_BIN/amp"

if [[ ! -x "$AMP_BIN" ]]; then
    echo "Amp CLI installation failed: binary not found at $AMP_BIN" >&2
    exit 1
fi

if [[ -n "$AMP_BIN" && "$AMP_BIN" != "/usr/local/bin/amp" ]]; then
    ln -sf "$AMP_BIN" /usr/local/bin/amp
fi
echo "Amp CLI linked to /usr/local/bin/amp"

# Clean up old symlinks from previous always-on shareConfig behavior
if [[ "$SHARE_CONFIG" != "true" ]]; then
    for old_target in "$REMOTE_USER_HOME/.amp" "$REMOTE_USER_HOME/.config/amp"; do
        if [[ -L "$old_target" ]]; then
            link_dest=$(readlink "$old_target" 2>/dev/null || true)
            if [[ "$link_dest" == "$AGENT_DIR" ]]; then
                rm -f "$old_target"
            fi
        fi
    done
fi

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.amp to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        target="$REMOTE_USER_HOME/.amp"
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
    echo "Amp configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v amp >/dev/null 2>&1; then
    OUT=$(amp --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "Amp CLI version: ${OUT}"
    else
        echo "Error: Amp CLI version check failed (exit ${RC})" >&2
        exit 1
    fi
else
    echo "Error: Amp CLI binary not on PATH" >&2
    exit 1
fi
set -e

echo "Amp CLI installed successfully!"
