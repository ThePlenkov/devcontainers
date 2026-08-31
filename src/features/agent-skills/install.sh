#!/usr/bin/env bash
set -e

# Agent Skills — ships a runtime script that installs agent skills using the
# already-authenticated gh CLI on the PVC, and creates per-agent symlinks.
#
# Why runtime, not build-time?
#   - gh auth lives on the PVC (~/.config/gh/hosts.yml), only available at runtime
#   - Private repos (e.g. theplenkov-ai/skills) need that auth — no token in the image
#   - Skills persist on the PVC across pod recreations
#
# What this feature does at build time:
#   1. Writes /usr/local/bin/agent-skills-sync — runtime script (runs at login)
#   2. Writes /etc/profile.d/agent-skills.sh — sources the sync script
#   3. Optionally installs PUBLIC skills to /usr/local/share/agent-skills (system-wide,
#      outside PVC) as a fallback for environments without gh auth

INSTALLER="${INSTALLER:-gh}"
AGENTS="${AGENTS:-*}"
COPY="${COPY:-true}"
TOKEN_OPTION="${TOKEN:-}"

# SKILLS is a comma-separated string
SKILLS_STR="${SKILLS:-}"
IFS=',' read -ra SKILLS <<< "${SKILLS_STR}"

REMOTE_USER="${_REMOTE_USER:-${_CONTAINER_USER:-vscode}}"
HOME_DIR="${_REMOTE_USER_HOME:-$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)}"
HOME_DIR="${HOME_DIR:-/home/${REMOTE_USER}}"

# System-wide fallback store (for public skills, outside PVC)
SKILLS_STORE="/usr/local/share/agent-skills"

echo "agent-skills: installer=${INSTALLER}"
echo "agent-skills: skills=${SKILLS[*]}"
echo "agent-skills: agents=${AGENTS}"

# ---------------------------------------------------------------------------
# Auth setup (for build-time public skill installs only)
# ---------------------------------------------------------------------------

RESOLVED_TOKEN=""
if [[ -n "${TOKEN_OPTION}" ]]; then
  RESOLVED_TOKEN="${TOKEN_OPTION}"
elif [[ -n "${GH_TOKEN}" ]]; then
  RESOLVED_TOKEN="${GH_TOKEN}"
elif [[ -n "${GITHUB_TOKEN}" ]]; then
  RESOLVED_TOKEN="${GITHUB_TOKEN}"
fi

if [[ -n "${RESOLVED_TOKEN}" ]]; then
  echo "agent-skills: token found, configuring gh auth for build-time installs"
  echo "${RESOLVED_TOKEN}" | gh auth login --with-token 2>/dev/null || true
  export GH_TOKEN="${RESOLVED_TOKEN}"
else
  echo "agent-skills: no token — will try public repos only at build time"
fi

# ---------------------------------------------------------------------------
# Build-time: install PUBLIC skills to system-wide store (fallback)
# ---------------------------------------------------------------------------

run_as_user() {
  if [[ "$REMOTE_USER" == "root" ]]; then
    env HOME="${HOME_DIR}" "$@"
  else
    local cmd_args=()
    for arg in "$@"; do
      cmd_args+=("$(printf '%q' "$arg")")
    done
    local escaped_home
    escaped_home=$(printf '%q' "${HOME_DIR}")
    su -s /bin/bash "$REMOTE_USER" -c "export HOME=${escaped_home}; export GH_TOKEN=${RESOLVED_TOKEN:+$(printf '%q' "$RESOLVED_TOKEN")}; exec ${cmd_args[*]}"
  fi
}

mkdir -p "$SKILLS_STORE"
chown "${REMOTE_USER}:${REMOTE_USER}" "$SKILLS_STORE" 2>/dev/null || true

if [[ ${#SKILLS[@]} -gt 0 ]]; then
  for pkg in "${SKILLS[@]}"; do
    pkg=$(echo "${pkg}" | xargs)
    [[ -z "${pkg}" ]] && continue
    echo "agent-skills: attempting build-time install of ${pkg} (public only)"
    run_as_user gh skill install "${pkg}" --dir "${SKILLS_STORE}" --all --force 2>&1 || {
      echo "agent-skills: build-time install failed for ${pkg} (likely private — will retry at runtime)"
    }
  done
fi

SKILL_COUNT=$(find "${SKILLS_STORE}" -maxdepth 2 -name "SKILL.md" 2>/dev/null | wc -l)
echo "agent-skills: ${SKILL_COUNT} public skills in system store"

# ---------------------------------------------------------------------------
# Known agents → skills directory mapping
# ---------------------------------------------------------------------------

KNOWN_AGENTS=(
  "devin:.config/devin/skills"
  "claude-code:.claude/skills"
  "github-copilot:.copilot/skills"
  "codex:.codex/skills"
  "cursor:.cursor/skills"
  "opencode:.opencode/skills"
  "gemini-cli:.gemini/skills"
  "goose:.goose/skills"
  "windsurf:.codeium/windsurf/skills"
  "kilo:.kilo/skills"
)

# Build agent symlink list
if [[ "${AGENTS}" == "*" ]]; then
  AGENT_SYMLINKS=("${KNOWN_AGENTS[@]}")
else
  AGENT_SYMLINKS=()
  IFS=',' read -ra AGENT_LIST <<< "${AGENTS}"
  for agent in "${AGENT_LIST[@]}"; do
    agent=$(echo "${agent}" | xargs)
    for known in "${KNOWN_AGENTS[@]}"; do
      known_name="${known%%:*}"
      if [[ "${known_name}" == "${agent}" ]]; then
        AGENT_SYMLINKS+=("$known")
      fi
    done
  done
fi

# ---------------------------------------------------------------------------
# Write runtime sync script: /usr/local/bin/agent-skills-sync
# ---------------------------------------------------------------------------

# Build the skills list as a space-separated string (POSIX sh compatible)
SKILLS_STRING=""
for pkg in "${SKILLS[@]}"; do
  pkg=$(echo "${pkg}" | xargs)
  [[ -z "$pkg" ]] && continue
  SKILLS_STRING+=" ${pkg}"
done

# Build the agent symlink calls
AGENT_LINK_CALLS=""
for entry in "${AGENT_SYMLINKS[@]}"; do
  dir="${entry#*:}"
  AGENT_LINK_CALLS+="  _agent_skills_link \"$dir\";"$'\n'
done

cat > /usr/local/bin/agent-skills-sync << SYNC_EOF
#!/bin/sh
# Agent Skills sync — runs at login to:
#   1. Install skills from GitHub repos using existing gh auth (on PVC)
#   2. Create per-agent symlinks so each agent finds skills in its expected dir
#
# Idempotent: skips install if skills already present, only creates missing symlinks.

AGENT_SKILLS_STORE="/usr/local/share/agent-skills"
SKILLS_REPOS="${SKILLS_STRING# }"

# Fix HOME for OpenShift restricted SCC (sets HOME=/)
_H="\${HOME:-/home/vscode}"
[ "\$_H" = "/" ] && _H="/home/vscode"
export HOME="\$_H"

AGENTS_DIR="\$_H/.agents"
SKILLS_DIR="\$AGENTS_DIR/skills"

# --- 1. Install skills if not already present ---
# Use ~/.agents/.skill-lock.json as marker — if it exists, skills were installed
if [ ! -f "\$AGENTS_DIR/.skill-lock.json" ] && [ ! -d "\$SKILLS_DIR" ]; then
  # Check if gh is authenticated
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "agent-skills: installing skills via gh (first run)..."
    mkdir -p "\$AGENTS_DIR"
    for repo in \$SKILLS_REPOS; do
      gh skill install "\$repo" --scope user --all --force 2>/dev/null || \\
        echo "agent-skills: failed to install \$repo (skipping)"
    done
  else
    # No gh auth — fall back to system-wide store if it has skills
    if [ -d "\$AGENT_SKILLS_STORE" ] && [ "\$(find "\$AGENT_SKILLS_STORE" -name 'SKILL.md' 2>/dev/null | head -1)" ]; then
      echo "agent-skills: no gh auth, using system-wide fallback store"
      mkdir -p "\$AGENTS_DIR"
      ln -sfn "\$AGENT_SKILLS_STORE" "\$SKILLS_DIR"
    fi
  fi
fi

# --- 2. Create per-agent symlinks ---
_agent_skills_link() {
  _target="\$_H/\$1"
  _parent="\$(dirname "\$_target")"
  if [ ! -e "\$_target" ]; then
    mkdir -p "\$_parent" 2>/dev/null
    # Link to ~/.agents/skills if it exists, else to system store
    if [ -d "\$SKILLS_DIR" ]; then
      ln -sfn "\$SKILLS_DIR" "\$_target"
    elif [ -d "\$AGENT_SKILLS_STORE" ]; then
      ln -sfn "\$AGENT_SKILLS_STORE" "\$_target"
    fi
  fi
}

# Always ensure ~/.agents/skills exists (symlink to system store if no PVC skills)
if [ ! -e "\$SKILLS_DIR" ] && [ -d "\$AGENT_SKILLS_STORE" ]; then
  mkdir -p "\$AGENTS_DIR" 2>/dev/null
  ln -sfn "\$AGENT_SKILLS_STORE" "\$SKILLS_DIR"
fi

${AGENT_LINK_CALLS}
SYNC_EOF

chmod 0755 /usr/local/bin/agent-skills-sync

# ---------------------------------------------------------------------------
# Write profile.d script that calls the sync script
# ---------------------------------------------------------------------------

cat > /etc/profile.d/agent-skills.sh << 'PROFILE_EOF'
#!/bin/sh
# Agent Skills — run sync at login (installs skills + creates symlinks)
[ -x /usr/local/bin/agent-skills-sync ] && /usr/local/bin/agent-skills-sync
PROFILE_EOF

chmod 0755 /etc/profile.d/agent-skills.sh

# Also source from bashrc for non-login interactive shells
if ! grep -q 'agent-skills.sh' /etc/bash.bashrc 2>/dev/null; then
  echo '[ -f /etc/profile.d/agent-skills.sh ] && . /etc/profile.d/agent-skills.sh' >> /etc/bash.bashrc
fi

echo "agent-skills: runtime sync script at /usr/local/bin/agent-skills-sync"
echo "agent-skills: profile.d hook at /etc/profile.d/agent-skills.sh"
echo "agent-skills: done"
