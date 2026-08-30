#!/bin/bash
set -e

# Docker Agent CLI — Docker's agentic coding assistant
# Installs the binary from GitHub releases.

VERSION="${VERSION:-"latest"}"
SHARE_CONFIG="${SHARECONFIG:-false}"
REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-/home/vscode}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/docker-agent"

echo "Installing Docker Agent CLI (version: ${VERSION})..."

# Install curl if not present
if ! command -v curl &> /dev/null; then
    apt-get update -y && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
fi

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) DOCKER_AGENT_ARCH="amd64" ;;
    aarch64|arm64) DOCKER_AGENT_ARCH="arm64" ;;
    *)
        echo "Error: Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

# Download to a temp directory (CWE-377)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Normalize VERSION: release tags are prefixed with "v" (e.g. v1.128.0)
if [[ "$VERSION" != "latest" && -n "$VERSION" && "$VERSION" != v* ]]; then
    VERSION="v${VERSION}"
fi

# Determine the download URL
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    DOWNLOAD_URL="https://github.com/docker/docker-agent/releases/latest/download/docker-agent-linux-${DOCKER_AGENT_ARCH}"
else
    DOWNLOAD_URL="https://github.com/docker/docker-agent/releases/download/${VERSION}/docker-agent-linux-${DOCKER_AGENT_ARCH}"
fi

echo "Downloading: $DOWNLOAD_URL"
if ! curl --proto =https --proto-redir =https -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/docker-agent"; then
    echo "Error: Failed to download Docker Agent from $DOWNLOAD_URL" >&2
    exit 1
fi

# Download checksums and verify SHA-256 (CWE-494)
# Docker Agent releases may not publish checksums.txt — warn and continue if absent.
if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    CHECKSUM_URL="https://github.com/docker/docker-agent/releases/latest/download/checksums.txt"
else
    CHECKSUM_URL="https://github.com/docker/docker-agent/releases/download/${VERSION}/checksums.txt"
fi
if curl --proto =https --proto-redir =https -fsSL "$CHECKSUM_URL" -o "$TMP_DIR/checksums.txt" 2>/dev/null \
    && [[ -s "$TMP_DIR/checksums.txt" ]]; then
    expected=$(grep "docker-agent-linux-${DOCKER_AGENT_ARCH}" "$TMP_DIR/checksums.txt" | awk '{print $1}')
    if [[ -n "$expected" ]]; then
        actual=$(sha256sum "$TMP_DIR/docker-agent" | awk '{print $1}')
        if [[ "$actual" != "$expected" ]]; then
            echo "Error: SHA-256 checksum mismatch for docker-agent" >&2
            echo "  expected: $expected" >&2
            echo "  actual:   $actual" >&2
            exit 1
        fi
        echo "Docker Agent SHA-256 checksum verified"
    else
        echo "WARNING: docker-agent-linux-${DOCKER_AGENT_ARCH} not found in checksums.txt; skipping checksum verification" >&2
    fi
else
    echo "WARNING: checksums.txt not available for Docker Agent; skipping checksum verification" >&2
fi

# Install the binary to /usr/local/bin
cp "$TMP_DIR/docker-agent" /usr/local/bin/docker-agent
chmod +x /usr/local/bin/docker-agent
echo "Docker Agent CLI installed to /usr/local/bin/docker-agent"

# Symlink into Docker CLI plugins directory so it's available as `docker agent`
DOCKER_CLI_PLUGINS_DIR="$REMOTE_USER_HOME/.docker/cli-plugins"
mkdir -p "$DOCKER_CLI_PLUGINS_DIR"
ln -sf /usr/local/bin/docker-agent "$DOCKER_CLI_PLUGINS_DIR/docker-agent"
if id -u "$REMOTE_USER" >/dev/null 2>&1; then
    chown -R "$REMOTE_USER:" "$REMOTE_USER_HOME/.docker" 2>/dev/null || true
fi
# Also provide system-wide CLI plugin symlink
mkdir -p /usr/local/lib/docker/cli-plugins
ln -sf /usr/local/bin/docker-agent /usr/local/lib/docker/cli-plugins/docker-agent
echo "Docker Agent CLI plugin linked to $DOCKER_CLI_PLUGINS_DIR/docker-agent"

# Share config via AGENT_CONFIG_DIR when shareConfig is enabled
if [[ "$SHARE_CONFIG" == "true" ]]; then
    echo "shareConfig: linking ~/.config/cagent to $AGENT_DIR"
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        target="$REMOTE_USER_HOME/.config/cagent"
        if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
            mv "$target" "$AGENT_DIR/$(basename "$target")-legacy"
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
    echo "Docker Agent configured to use shared config at $AGENT_DIR"
fi

# Verify installation
set +e
if command -v docker-agent >/dev/null 2>&1; then
    OUT=$(docker-agent version 2>&1)
    RC=$?
    if [[ $RC -eq 0 ]]; then
        echo "Docker Agent CLI version: ${OUT}"
    else
        echo "Error: Docker Agent CLI version check failed (exit ${RC})" >&2
        exit 1
    fi
else
    echo "Error: Docker Agent CLI binary not on PATH" >&2
    exit 1
fi
set -e

echo "Docker Agent CLI installed successfully!"
