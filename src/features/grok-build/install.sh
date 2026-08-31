#!/bin/bash
set -e

# Grok Build CLI — xAI's agentic coding assistant
# Installs via the upstream installer script.

VERSION="${VERSION:-"latest"}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/grok-build"

# Temp dir for downloaded installers (CWE-377)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Installing Grok Build CLI (version: ${VERSION})..."

# Install curl if not present
if ! command -v curl &> /dev/null; then
    apt-get update -y && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
fi

# Run the upstream Grok installer
# Download-then-execute instead of curl|bash (review finding)
curl --proto =https --proto-redir =https -fsSL https://x.ai/cli/install.sh -o "$TMP_DIR/grok-install.sh"
# Set HOME explicitly so the installer places grok in $HOME/.grok/bin
export HOME="${REMOTE_USER_HOME:-/home/vscode}"
# The upstream Grok installer does NOT support --version as a flag; it treats
# it as a positional version and rejects it. Pinned versions are not supported.
bash "$TMP_DIR/grok-install.sh"

# Ensure the .grok tree is owned by the remote user (not root) when non-root
if id -u "$REMOTE_USER" >/dev/null 2>&1 && [[ "$REMOTE_USER" != "root" ]]; then
    chown -R "$REMOTE_USER:" "$HOME/.grok" 2>/dev/null || true
fi

# Locate the installed binary and link it to /usr/local/bin
GROK_BIN="$(command -v grok || true)"
if [[ -z "$GROK_BIN" ]]; then
    # The upstream installer places grok in $HOME/.grok/bin; also check common locations
    GROK_BIN="$(find "$HOME/.grok/bin" /usr/local/bin -name "grok" -executable 2>/dev/null | head -1)"
fi
if [[ -z "$GROK_BIN" ]]; then
    # Installer may place the binary in ~/.local/bin; check common locations
    for candidate in "$REMOTE_USER_HOME/.local/bin/grok" "/usr/local/bin/grok" "/usr/bin/grok"; do
        if [[ -x "$candidate" ]]; then
            GROK_BIN="$candidate"
            break
        fi
    done
fi

if [[ -z "$GROK_BIN" || ! -x "$GROK_BIN" ]]; then
    echo "Grok Build CLI installation failed: binary not found" >&2
    exit 1
fi

if [[ -n "$GROK_BIN" && "$GROK_BIN" != "/usr/local/bin/grok" ]]; then
    ln -sf "$GROK_BIN" /usr/local/bin/grok
fi
echo "Grok Build CLI linked to /usr/local/bin/grok"

# Profile.d for login shells
cat > /etc/profile.d/grok-build.sh << EOF
export GROK_HOME="\${GROK_HOME:-$REMOTE_USER_HOME/.grok}"
EOF
chmod 0755 /etc/profile.d/grok-build.sh

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.grok to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        target="$REMOTE_USER_HOME/.grok"
        if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
            mv "$target" "$AGENT_DIR/config-legacy"
        fi
        # Fix broken /usr/local/bin/grok after config migration
        GROK_NEW_BIN=$(find "$AGENT_DIR" -name "grok" -executable 2>/dev/null | head -1)
        if [[ -n "$GROK_NEW_BIN" ]]; then
            ln -sf "$GROK_NEW_BIN" /usr/local/bin/grok
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
    echo "Grok Build configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v grok >/dev/null 2>&1; then
    OUT=$(grok --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "Grok Build CLI version: ${OUT}"
    else
        echo "Grok Build CLI: version check skipped (exit ${RC})"
    fi
else
    echo "Grok Build CLI: binary not on PATH; skipping version check"
fi
set -e

echo "Grok Build CLI installed successfully!"
