#!/bin/bash
set -e

# Anthropic Claude Configuration Script

REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
REMOTE_USER_HOME="${REMOTE_USER_HOME:-$(eval echo ~$REMOTE_USER)}"
AGENT_DIR="${AGENT_CONFIG_DIR:-/usr/local/share/agent-config}/claude"
SHARE_CONFIG="${SHARECONFIG:-false}"

echo "Configuring Anthropic Claude..."

# Install anthropic Python package if Python is available
if command -v python3 &> /dev/null; then
    pip3 install anthropic || echo "Failed to install anthropic package"
fi

# Shared agent config for Claude
if [[ "$SHARE_CONFIG" == "true" ]]; then
    mkdir -p "$AGENT_DIR"
    if id -u "$REMOTE_USER" >/dev/null 2>&1; then
        chown -R "$REMOTE_USER:$REMOTE_USER" "$AGENT_DIR"
    fi

    if [[ -d "$REMOTE_USER_HOME" ]]; then
        for target in "$REMOTE_USER_HOME/.claude" "$REMOTE_USER_HOME/.config/claude"; do
            if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
                mv "$target" "$AGENT_DIR/$(basename "$target")-legacy"
            fi
            parent=$(dirname "$target")
            mkdir -p "$parent"
            rm -f "$target"
            if id -u "$REMOTE_USER" >/dev/null 2>&1; then
                chown "$REMOTE_USER:$REMOTE_USER" "$parent" 2>/dev/null || true
                su -s /bin/bash - "$REMOTE_USER" -c "ln -sfn '$AGENT_DIR' '$target'"
            else
                ln -sfn "$AGENT_DIR" "$target"
            fi
        done
    fi
fi

# Clean up old symlinks from previous always-on shareConfig behavior
if [[ "$SHARE_CONFIG" != "true" ]]; then
    if [[ -n "$REMOTE_USER_HOME" ]] && [[ -d "$REMOTE_USER_HOME" ]]; then
        for old_target in "$REMOTE_USER_HOME/.claude" "$REMOTE_USER_HOME/.config/claude"; do
            if [[ -L "$old_target" ]]; then
                link_dest=$(readlink "$old_target" 2>/dev/null || true)
                if [[ "$link_dest" == "$AGENT_DIR"* ]]; then
                    rm -f "$old_target"
                fi
            fi
        done
    fi
fi

# Usage examples
mkdir -p /usr/local/share/claude-examples
cat > /usr/local/share/claude-examples/usage.md << 'EOF'
# Anthropic Claude Usage

## Environment Variable
export ANTHROPIC_API_KEY="your-api-key-here"

## Python Example
```python
from anthropic import Anthropic
client = Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))
message = client.messages.create(
    model="claude-3-5-sonnet-20240620",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello, Claude!"}]
)
print(message.content)
```

## Node.js Example
```javascript
import Anthropic from '@anthropic-ai/sdk';
const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
```
EOF

echo "Anthropic Claude configured successfully!"
