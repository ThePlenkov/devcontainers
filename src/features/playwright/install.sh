#!/bin/bash
set -e

# Playwright System Dependencies Installation Script

BROWSERS=${BROWSERS:-"chromium"}
INSTALL_METHOD=${INSTALLMETHOD:-"auto"}

echo "Installing Playwright system dependencies (browsers: ${BROWSERS}, method: ${INSTALL_METHOD})..."

# Use Playwright's install-deps to install system dependencies
if command -v npx >/dev/null 2>&1; then
    npx playwright install-deps ${BROWSERS}
    if [[ "$INSTALL_METHOD" == "auto" ]]; then
        npx playwright install ${BROWSERS}
    fi
else
    echo "ERROR: npx not found. Node.js must be installed before this feature runs." >&2
    exit 1
fi

# Headless display for non-X servers.
export DISPLAY=:99
for shell_config in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$shell_config" ]] && ! grep -q 'export DISPLAY=:99' "$shell_config"; then
        echo 'export DISPLAY=:99' >> "$shell_config"
    fi
done

echo "Playwright system dependencies installed for: ${BROWSERS}"
