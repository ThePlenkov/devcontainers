#!/bin/bash
set -e

# Gas City Entrypoint Script
# Runs at container startup to optionally register the city.

echo "Gas City entrypoint: registering city..."

AUTOREGISTER=$(cat /usr/local/share/gascity/autoregister_enabled 2>/dev/null || echo "false")
echo "AutoRegister: ${AUTOREGISTER}"

# Try to navigate to a workspace
cd /workspaces 2>/dev/null || true
for dir in /workspaces/gascity-workspace /workspaces/gascity-devcontainer /workspaces/*; do
    if [ -d "$dir" ]; then
        cd "$dir"
        break
    fi
done

if [ "${AUTOREGISTER}" = "true" ]; then
    echo "Registering city with supervisor..."
    if command -v dolt >/dev/null 2>&1; then
        dolt config --global --add user.name "DevContainer User" || true
        dolt config --global --add user.email "devcontainer@localhost" || true
    fi
    if command -v gc >/dev/null 2>&1; then
        gc register . || true
    fi
    echo "City registration attempted."
else
    echo "Auto-register skipped"
fi

# Execute the main container command (or keep alive if none)
if [ $# -gt 0 ]; then
    exec "$@"
else
    # Keep the container alive when no command is provided
    exec sleep infinity
fi
