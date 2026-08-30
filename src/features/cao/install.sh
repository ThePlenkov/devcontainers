#!/bin/bash
set -e

# CAO — AWS CLI Agent Orchestrator
# Installs via uv (Astral's Python package manager) from GitHub.

VERSION="${VERSION:-"latest"}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/cao"

echo "Installing CAO — CLI Agent Orchestrator (version: ${VERSION})..."

# Install curl if not present
if ! command -v curl &> /dev/null; then
    apt-get update -y && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
fi

# Install tmux if not present (required by CAO for session orchestration)
if ! command -v tmux &> /dev/null; then
    apt-get update -y && apt-get install -y tmux && rm -rf /var/lib/apt/lists/*
fi

# Install uv if not present (required to install CAO)
if ! command -v uv &> /dev/null; then
    echo "uv not found; installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    # Also make uv available system-wide
    if [[ -x "$HOME/.local/bin/uv" ]]; then
        ln -sf "$HOME/.local/bin/uv" /usr/local/bin/uv
    fi
fi

# Determine the install ref (branch/tag)
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    CAO_REF="main"
else
    CAO_REF="$VERSION"
fi

# Install CAO via uv tool install
uv tool install "git+https://github.com/awslabs/cli-agent-orchestrator.git@${CAO_REF}" --upgrade

# Locate the installed binary and link it to /usr/local/bin
CAO_BIN="$(command -v cao || true)"
if [[ -z "$CAO_BIN" ]]; then
    # uv installs tools to ~/.local/bin
    for candidate in "$HOME/.local/bin/cao" "$REMOTE_USER_HOME/.local/bin/cao"; do
        if [[ -x "$candidate" ]]; then
            CAO_BIN="$candidate"
            break
        fi
    done
fi

if [[ -z "$CAO_BIN" || ! -x "$CAO_BIN" ]]; then
    echo "CAO installation failed: binary not found" >&2
    exit 1
fi

ln -sf "$CAO_BIN" /usr/local/bin/cao
chmod +x /usr/local/bin/cao
echo "CAO linked to /usr/local/bin/cao"

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.aws/cli-agent-orchestrator to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [ -d "$REMOTE_USER_HOME" ]; then
        target="$REMOTE_USER_HOME/.aws/cli-agent-orchestrator"
        if [ -e "$target" ] && [ ! -L "$target" ]; then
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
    echo "CAO configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v cao >/dev/null 2>&1; then
    OUT=$(cao --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "CAO version: ${OUT}"
    else
        echo "CAO: version check skipped (exit ${RC})"
    fi
else
    echo "CAO: binary not on PATH; skipping version check"
fi
set -e

echo "CAO installed successfully!"
