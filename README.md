# docker-x/devcontainers

A reusable library of [devcontainer features](https://containers.dev/implementors/features/) and templates for AI coding agents and development tooling.

All agent features share a common configuration directory (`AGENT_CONFIG_DIR`) so multiple agents can coexist in the same workspace with persistent, PVC-backed settings.

## Features

### Core

| Feature | Description |
| ------- | ----------- |
| `agent-config` | Creates a shared directory for AI agent configuration and exposes it as `AGENT_CONFIG_DIR` so multiple agent features can store their configs in one place. |
| `agent-skills` | Install agent skills globally from GitHub repositories using `npx skills` or `gh skill`. |
| `openshift-compat` | Makes devcontainer images compatible with OpenShift restricted SCC: SSH server, random UID support, fake sudo, group-writable home. |

### AI Coding Agents

| Feature | Description |
| ------- | ----------- |
| `claude-code` | Anthropic's Claude Code CLI — terminal-native coding agent that edits files, runs commands, and uses tools autonomously. |
| `codex` | OpenAI Codex CLI — AI coding agent for terminal-based development. |
| `gemini` | Google's Gemini CLI — official terminal AI agent for coding, exploration, and automation. |
| `copilot` | GitHub's standalone Copilot CLI — terminal AI agent for coding, automation, and repository exploration. |
| `qwen-code` | Qwen Code from Alibaba — open-source AI coding agent that lives in your terminal. |
| `kimi` | Kimi Code from Moonshot AI — open-source AI coding agent. |
| `cursor` | Cursor Agent CLI — autonomous coding agent from Cursor. |
| `cline` | Cline CLI — open-source AI coding agent with VS Code extension and terminal CLI support. |
| `amp` | Amp from Sourcegraph — frontier AI agent and development environment CLI. |
| `crush` | Crush from Charm — terminal-first AI coding assistant with multi-LLM provider support. |
| `mastra-code` | Mastra Code — terminal-based AI coding agent with Build/Plan/Fast modes. |
| `opencode` | OpenCode AI — open-source AI coding agent for terminal development. |
| `grok-build` | Grok Build from xAI — coding agent harness and TUI with fullscreen mouse-interactive interface. |

### Agent Orchestrators

| Feature | Description |
| ------- | ----------- |
| `cao` | AWS Labs CLI Agent Orchestrator — multi-agent orchestration for AI coding CLIs coordinated in isolated tmux sessions. |
| `docker-agent` | Docker Agent — Docker's AI agent CLI plugin for running multi-agent teams from declarative YAML/HCL. |
| `herdr` | Herdr — AI agent herd orchestration for coordinating multiple coding agents. |
| `gascity` | Gas City — AI agent orchestration platform with Dolt and Beads integration. |
| `paseo` | Paseo CLI — local-first AI development environment with daemon, web UI, and agent orchestration. |

### Specialized Agents

| Feature | Description |
| ------- | ----------- |
| `devin` | Devin CLI — AI-powered development agent. |
| `claude` | Anthropic Claude SDK configuration. |
| `hermes` | Hermes Agent from Nous Research — self-improving AI agent CLI with skills, memory, and 60+ tools. |
| `goose` | Goose CLI from Block — open-source, extensible AI agent that installs, executes, edits, and tests code. |
| `openclaw` | OpenClaw — personal AI assistant CLI with TUI, messaging channels, and MCP tool bridge. |
| `devsy` | Devsy agent binary — fallback for orchestrators where native agent injection fails. |
| `devpod` | DevPod agent binary — unmaintained, use only for DevPod-to-Devsy migration. |

### Development Tooling

| Feature | Description |
| ------- | ----------- |
| `homebrew` | Homebrew on Linux with optional package list. |
| `bun` | Bun JavaScript runtime via the official installer. |
| `kilo` | Kilo CLI from GitHub releases. |
| `playwright` | System dependencies for Playwright browser automation. |
| `sacp-conductor` | sacp-conductor for ACP proxy orchestration. |

## Templates

| Template | Description |
| -------- | ----------- |
| `agent-base` | A base devcontainer with common AI agent CLIs sharing a single agent config folder. |
| `gascity-workspace` | A devcontainer for Gas City development with Bun, Playwright, and shared agent config. |

## Shared Agent Config

All agent features depend on `agent-config` and create a subfolder under `AGENT_CONFIG_DIR`. Their home-directory config locations are symlinked to that subfolder, so agents keep their configs in one place and can be used side-by-side.

Sharing is **opt-in** via the `shareConfig` option (default: `false`). When enabled, existing config is migrated to a `config-legacy` backup before the symlink is created.

## Usage

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/docker-x/devcontainers/agent-config:1": {},
    "ghcr.io/docker-x/devcontainers/claude-code:1": {},
    "ghcr.io/docker-x/devcontainers/codex:1": {},
    "ghcr.io/docker-x/devcontainers/gemini:1": {
      "shareConfig": true
    }
  },
  "remoteUser": "vscode"
}
```

### Opt-in config sharing

```jsonc
{
  "ghcr.io/docker-x/devcontainers/agent-config:1": {},
  "ghcr.io/docker-x/devcontainers/claude-code:1": {
    "shareConfig": true
  }
}
```

When `shareConfig` is `true`, the agent's config directory is symlinked to `AGENT_CONFIG_DIR/<feature>`, making it persistent across container rebuilds and shared with other agents.

## Publishing

Features and templates are published via the `Release Dev Container Features & Templates` GitHub Actions workflow on push to `main`.

- Features: `ghcr.io/docker-x/devcontainers/<feature>`
- Templates: `ghcr.io/docker-x/devcontainers/templates/<template>`

## Conventions

- **Security:** HTTPS-only downloads (`--proto =https --proto-redir =https`), SHA-256 checksum verification when upstream publishes checksums, download-then-execute (never `curl|bash`).
- **Robustness:** npm binaries resolved from `npm config get prefix` (not `command -v`), self-link guards on all symlinks, `npm rebuild` after `--ignore-scripts` installs.
- **OpenShift:** Profile scripts use `REMOTE_USER_HOME` (resolved at build time) instead of `$HOME` to handle restricted SCC environments where `HOME=/`.
- **Config sharing:** Opt-in via `shareConfig` option, with `config-legacy` backup for existing config.

See [AGENTS.md](AGENTS.md) for contributor guidelines and [REVIEW.md](REVIEW.md) for review rules.
