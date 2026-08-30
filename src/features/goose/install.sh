#!/bin/bash
set -e

# Goose CLI — Block's open-source extensible AI agent
# Installs the goose binary from GitHub releases.

VERSION="${VERSION:-"latest"}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/goose"

echo "Installing Goose CLI (version: ${VERSION})..."

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) GOOSE_ARCH="x86_64" ;;
    aarch64|arm64) GOOSE_ARCH="aarch64" ;;
    *)
        echo "Error: Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

OS=$(uname -s | tr '[:upper:]' '[:lower:]')

# Download to a temp directory (CWE-377)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Determine the release tag
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    API_RESPONSE=$(curl --proto =https -fsSL "https://api.github.com/repos/aaif-goose/goose/releases/latest" 2>/dev/null)
    if command -v jq &> /dev/null; then
        RELEASE_TAG=$(echo "$API_RESPONSE" | jq -r '.tag_name' 2>/dev/null)
    else
        RELEASE_TAG=$(echo "$API_RESPONSE" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    if [[ -z "$RELEASE_TAG" ]]; then
        echo "Error: Could not determine latest Goose release tag" >&2
        exit 1
    fi
else
    RELEASE_TAG="$VERSION"
fi

echo "Goose release: $RELEASE_TAG"

# Download the binary tarball
TARBALL="goose-${GOOSE_ARCH}-unknown-${OS}-gnu.tar.gz"
DOWNLOAD_URL="https://github.com/aaif-goose/goose/releases/download/${RELEASE_TAG}/${TARBALL}"

echo "Downloading: $DOWNLOAD_URL"
if ! curl --proto =https -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/goose.tar.gz"; then
    echo "Error: Failed to download Goose from $DOWNLOAD_URL" >&2
    exit 1
fi

# Download checksums and verify SHA256 (CWE-494)
if ! curl --proto =https -fsSL "https://github.com/aaif-goose/goose/releases/download/${RELEASE_TAG}/checksums.txt" -o "$TMP_DIR/checksums.txt"; then
    echo "Error: Could not download checksums file for $RELEASE_TAG" >&2
    exit 1
fi
if [[ -f "$TMP_DIR/checksums.txt" ]]; then
    expected=$(grep "$TARBALL" "$TMP_DIR/checksums.txt" | awk '{print $1}')
    if [[ -n "$expected" ]]; then
        actual=$(sha256sum "$TMP_DIR/goose.tar.gz" | awk '{print $1}')
        if [[ "$expected" != "$actual" ]]; then
            echo "Error: SHA256 mismatch for $TARBALL" >&2
            exit 1
        fi
        echo "Checksum verified: $TARBALL"
    fi
fi

# Extract
tar -xzf "$TMP_DIR/goose.tar.gz" -C "$TMP_DIR"

# Find and install the binary
GOOSE_BIN=$(find "$TMP_DIR" -name "goose" -type f -executable | head -1)
if [[ -z "$GOOSE_BIN" ]]; then
    echo "Error: Goose binary not found in archive" >&2
    exit 1
fi

ln -sf "$GOOSE_BIN" /usr/local/bin/goose
chmod +x /usr/local/bin/goose
echo "Goose CLI installed to /usr/local/bin/goose"

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.config/goose to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        target="$REMOTE_USER_HOME/.config/goose"
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
    echo "Goose configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v goose >/dev/null 2>&1; then
    OUT=$(goose --version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "Goose CLI version: ${OUT}"
    else
        echo "Goose CLI: version check skipped (exit ${RC})"
    fi
fi
set -e

echo "Goose CLI installed successfully!"
echo "Note: Set provider env vars like OPENAI_API_KEY, ANTHROPIC_API_KEY, or GEMINI_API_KEY."
echo "      Set GOOSE_PROVIDER and GOOSE_MODEL to select the LLM backend."
