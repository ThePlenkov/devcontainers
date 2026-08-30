#!/bin/bash
set -e

# Claude Code CLI — Anthropic's terminal coding agent
# Installs the @anthropic-ai/claude-code npm package globally.

VERSION="${VERSION:-"latest"}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/claude-code"

echo "Installing Claude Code CLI (version: ${VERSION})..."

# Ensure npm is available
if ! command -v npm &> /dev/null; then
    echo "Error: npm is required to install Claude Code. Add the node feature before this one." >&2
    exit 1
fi

# Install Claude Code globally
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    npm install -g @anthropic-ai/claude-code
else
    npm install -g @anthropic-ai/claude-code@"${VERSION}"
fi

# Locate and link the binary to /usr/local/bin
CLAUDE_BIN="$(command -v claude || true)"
if [[ -z "$CLAUDE_BIN" ]]; then
    NPM_GLOBAL_BIN="$(npm bin -g 2>/dev/null || true)"
    if [[ ! -d "$NPM_GLOBAL_BIN" ]]; then
        NPM_GLOBAL_BIN="$(npm config get prefix 2>/dev/null || true)/bin"
    fi
    CLAUDE_BIN="$NPM_GLOBAL_BIN/claude"
fi

if [[ -x "$CLAUDE_BIN" ]]; then
    ln -sf "$CLAUDE_BIN" /usr/local/bin/claude
    echo "Claude Code linked to /usr/local/bin/claude"
else
    echo "Error: Claude Code binary not found at $CLAUDE_BIN" >&2
    exit 1
fi

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.claude to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        target="$REMOTE_USER_HOME/.claude"
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
    echo "Claude Code configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v claude >/dev/null 2>&1; then
    OUT=$(claude --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "Claude Code version: ${OUT}"
    else
        echo "Claude Code: version check skipped (exit ${RC})"
    fi
fi
set -e

echo "Claude Code CLI installed successfully!"
