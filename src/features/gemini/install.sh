#!/bin/bash
set -e

# Gemini CLI — Google's official terminal AI agent
# Installs the @google/gemini-cli npm package globally.

VERSION="${VERSION:-"latest"}"
API_KEY="${APIKEY:-""}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/gemini"

echo "Installing Gemini CLI (version: ${VERSION})..."

# Ensure npm is available
if ! command -v npm &> /dev/null; then
    echo "Error: npm is required to install Gemini CLI. Add the node feature before this one." >&2
    exit 1
fi

# Install Gemini CLI globally
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    npm install -g @google/gemini-cli
else
    npm install -g @google/gemini-cli@"${VERSION}"
fi

# Locate and link the binary to /usr/local/bin
GEMINI_BIN="$(command -v gemini || true)"
if [[ -z "$GEMINI_BIN" ]]; then
    NPM_GLOBAL_BIN="$(npm bin -g 2>/dev/null || true)"
    if [[ ! -d "$NPM_GLOBAL_BIN" ]]; then
        NPM_GLOBAL_BIN="$(npm config get prefix 2>/dev/null || true)/bin"
    fi
    GEMINI_BIN="$NPM_GLOBAL_BIN/gemini"
fi

if [[ -x "$GEMINI_BIN" ]]; then
    ln -sf "$GEMINI_BIN" /usr/local/bin/gemini
    echo "Gemini CLI linked to /usr/local/bin/gemini"
else
    echo "Error: Gemini CLI binary not found at $GEMINI_BIN" >&2
    exit 1
fi

# Set API key in /etc/environment if provided
if [ -n "$API_KEY" ]; then
    grep -q "^GEMINI_API_KEY=" /etc/environment 2>/dev/null || \
        echo "GEMINI_API_KEY=\"$API_KEY\"" >> /etc/environment
    echo "GEMINI_API_KEY set in /etc/environment"
else
    echo "No API key provided. Set GEMINI_API_KEY manually."
fi

# Profile.d for login shells
cat > /etc/profile.d/gemini-cli.sh << 'EOF'
export GEMINI_CONFIG_DIR="${GEMINI_CONFIG_DIR:-$HOME/.gemini}"
EOF
chmod 0755 /etc/profile.d/gemini-cli.sh

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.gemini to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [ -d "$REMOTE_USER_HOME" ]; then
        target="$REMOTE_USER_HOME/.gemini"
        if [ -e "$target" ] && [ ! -L "$target" ]; then
            mv "$target" "$AGENT_DIR/config-legacy"
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
    fi
    echo "Gemini CLI configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v gemini >/dev/null 2>&1; then
    OUT=$(gemini --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "Gemini CLI version: ${OUT}"
    else
        echo "Gemini CLI: version check skipped (exit ${RC})"
    fi
fi
set -e

echo "Gemini CLI installed successfully!"
