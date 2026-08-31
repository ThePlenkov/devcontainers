#!/bin/bash
set -e

# OpenAI Codex CLI Installation Script (non-interactive)

VERSION=${VERSION:-"latest"}

REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/codex"
SHARE_CONFIG="${SHARECONFIG:-false}"

echo "Installing OpenAI Codex CLI (version: ${VERSION})..."

# Install curl and npm if not available
if ! command -v curl &> /dev/null; then
    apt-get update -y && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
fi

if ! command -v npm &> /dev/null; then
    echo "Error: npm is required to install Codex CLI. Add the node feature before this one." >&2
    exit 1
fi

# Install Codex CLI globally via npm
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    npm install -g --ignore-scripts @openai/codex
else
    npm install -g --ignore-scripts @openai/codex@"${VERSION}"
fi
npm rebuild -g @openai/codex 2>&1 || { echo "Error: codex native binary setup failed" >&2; exit 1; }

# Locate the installed binary and copy it to /usr/local/bin for system-wide access
NPM_GLOBAL_BIN="$(npm config get prefix 2>/dev/null || true)/bin"
CODEX_BIN="$NPM_GLOBAL_BIN/codex"

if [[ ! -x "$CODEX_BIN" ]]; then
    echo "Codex CLI installation failed: binary not found at $CODEX_BIN" >&2
    exit 1
fi

if [[ -n "$CODEX_BIN" && "$CODEX_BIN" != "/usr/local/bin/codex" ]]; then
    ln -sf "$CODEX_BIN" /usr/local/bin/codex
fi
echo "Codex CLI linked to /usr/local/bin/codex"

# Shared agent config
if [[ "$SHARE_CONFIG" == "true" ]]; then
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        for target in "$REMOTE_USER_HOME/.codex" "$REMOTE_USER_HOME/.config/codex"; do
            if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
                mv "$target" "$AGENT_DIR/$(basename "$target")-legacy"
            fi
            parent=$(dirname "$target")
            mkdir -p "$parent"
            rm -f "$target"
            if id -u "$REMOTE_USER" >/dev/null 2>&1; then
                chown "$REMOTE_USER:" "$parent" 2>/dev/null || true
                su -s /bin/bash - "$REMOTE_USER" -c "ln -sfn '$AGENT_DIR' '$target'" 2>/dev/null || true
            else
                ln -sfn "$AGENT_DIR" "$target"
            fi
        done
    fi
fi

# Stale link cleanup when shareConfig is false: remove symlinks that point
# to $AGENT_DIR from a previous shareConfig=true run.
if [[ "$SHARE_CONFIG" != "true" ]]; then
    for old_target in "$REMOTE_USER_HOME/.codex" "$REMOTE_USER_HOME/.config/codex"; do
        if [[ -L "$old_target" ]]; then
            link_dest=$(readlink "$old_target" 2>/dev/null || true)
            if [[ "$link_dest" == "$AGENT_DIR" ]]; then
                rm -f "$old_target"
            fi
        fi
    done
fi

# Verify installation (don't let version-check failures abort the build)
set +e
if command -v codex >/dev/null 2>&1; then
    OUT=$(codex --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "Codex CLI version: ${OUT}"
    else
        echo "Codex CLI: version check skipped (exit ${RC})"
    fi
else
    echo "Codex CLI: binary not on PATH; skipping version check"
fi
set -e

echo "OpenAI Codex CLI installed successfully!"
