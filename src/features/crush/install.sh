#!/bin/bash
set -e

# Crush CLI — Charm's terminal-first AI coding assistant
# Installs the @charmland/crush npm package globally.

VERSION="${VERSION:-"latest"}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/crush"

echo "Installing Crush CLI (version: ${VERSION})..."

# Ensure npm is available
if ! command -v npm &> /dev/null; then
    echo "Error: npm is required to install Crush. Add the node feature before this one." >&2
    exit 1
fi

# Install Crush globally
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    npm install -g --ignore-scripts @charmland/crush
else
    npm install -g --ignore-scripts @charmland/crush@"${VERSION}"
fi
# Explicitly run postinstall to install native binaries
npm rebuild -g @charmland/crush 2>/dev/null || true

# Locate and link the binary to /usr/local/bin
CRUSH_BIN="$(command -v crush || true)"
if [[ -z "$CRUSH_BIN" ]]; then
    NPM_GLOBAL_BIN="$(npm bin -g 2>/dev/null || true)"
    if [[ ! -d "$NPM_GLOBAL_BIN" ]]; then
        NPM_GLOBAL_BIN="$(npm config get prefix 2>/dev/null || true)/bin"
    fi
    CRUSH_BIN="$NPM_GLOBAL_BIN/crush"
fi

if [[ -x "$CRUSH_BIN" ]]; then
    ln -sf "$CRUSH_BIN" /usr/local/bin/crush
    echo "Crush linked to /usr/local/bin/crush"
else
    echo "Error: Crush binary not found at $CRUSH_BIN" >&2
    exit 1
fi

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.config/crush to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        target="$REMOTE_USER_HOME/.config/crush"
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
    echo "Crush configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v crush >/dev/null 2>&1; then
    OUT=$(crush --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "Crush version: ${OUT}"
    else
        echo "Crush: version check skipped (exit ${RC})"
    fi
fi
set -e

echo "Crush CLI installed successfully!"
echo "Note: Set provider env vars like ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, or OPENROUTER_API_KEY."
