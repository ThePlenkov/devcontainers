#!/bin/bash
set -e

# sacp-conductor Installation Script

echo "Installing sacp-conductor..."

# Install curl if not available
if ! command -v curl &> /dev/null; then
    apt-get update -y && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
fi

# Install Rust if not available
if ! command -v rustup &> /dev/null; then
    echo "Installing Rust toolchain..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

# Source cargo env if it exists
if [[ -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env"
fi

# Ensure cargo is in PATH
if ! command -v cargo &> /dev/null; then
    echo "Error: cargo not found in PATH after Rust installation" >&2
    exit 1
fi

# Install sacp-conductor
echo "Installing sacp-conductor via cargo..."
cargo install sacp-conductor

# Copy sacp-conductor binary to avoid permission issues
if [[ -f "$HOME/.cargo/bin/sacp-conductor" ]]; then
    cp "$HOME/.cargo/bin/sacp-conductor" /usr/local/bin/sacp-conductor
    chmod +x /usr/local/bin/sacp-conductor
    echo "sacp-conductor copied to /usr/local/bin/sacp-conductor"
else
    echo "Warning: sacp-conductor binary not found after installation"
fi

echo "sacp-conductor installed successfully!"
