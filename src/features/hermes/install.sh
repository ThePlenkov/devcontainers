#!/bin/bash
set -e

# Hermes CLI — Nous Research's agentic coding assistant
# Installs via the upstream installer script.

VERSION="${VERSION:-"latest"}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/hermes"

# Temp dir for downloaded installers (CWE-377)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Installing Hermes CLI (version: ${VERSION})..."

# Install curl if not present
if ! command -v curl &> /dev/null; then
    apt-get update -y && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
fi

# Run the upstream Hermes installer (non-interactive, skip initial setup)
# Download-then-execute instead of curl|bash (review finding)
curl --proto =https --proto-redir =https -fsSL https://hermes-agent.nousresearch.com/install.sh -o "$TMP_DIR/hermes-install.sh"
# Pass version to installer when specified (not latest)
if [[ "$VERSION" != "latest" && -n "$VERSION" ]]; then
    bash "$TMP_DIR/hermes-install.sh" --non-interactive --skip-setup --version "$VERSION"
else
    bash "$TMP_DIR/hermes-install.sh" --non-interactive --skip-setup
fi

# Locate the installed binary and link it to /usr/local/bin
HERMES_BIN="$(command -v hermes || true)"
if [[ -z "$HERMES_BIN" ]]; then
    # Installer may place the binary in ~/.local/bin; check common locations
    for candidate in "$REMOTE_USER_HOME/.local/bin/hermes" "/usr/local/bin/hermes" "/usr/bin/hermes"; do
        if [[ -x "$candidate" ]]; then
            HERMES_BIN="$candidate"
            break
        fi
    done
fi

if [[ -z "$HERMES_BIN" || ! -x "$HERMES_BIN" ]]; then
    echo "Hermes CLI installation failed: binary not found" >&2
    exit 1
fi

ln -sf "$HERMES_BIN" /usr/local/bin/hermes
chmod +x /usr/local/bin/hermes
echo "Hermes CLI linked to /usr/local/bin/hermes"

# Profile.d for login shells
cat > /etc/profile.d/hermes.sh << 'EOF'
export HERMES_HOME="${HERMES_HOME:-/home/vscode/.hermes}"
EOF
chmod 0755 /etc/profile.d/hermes.sh

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.hermes to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        target="$REMOTE_USER_HOME/.hermes"
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
    echo "Hermes configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v hermes >/dev/null 2>&1; then
    OUT=$(hermes --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "Hermes CLI version: ${OUT}"
    else
        echo "Hermes CLI: version check skipped (exit ${RC})"
    fi
else
    echo "Hermes CLI: binary not on PATH; skipping version check"
fi
set -e

echo "Hermes CLI installed successfully!"
