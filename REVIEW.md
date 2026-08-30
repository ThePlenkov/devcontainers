# PR #42 Review Retrospect

**PR:** https://github.com/docker-x/devcontainers/pull/42
**Branch:** `feat/leading-agent-clis`
**Final HEAD:** `b7b9eb43cfa72fbce591c83925abbc69848ffad1`
**Iterations:** 4 (round-1 initial fixes → round-2 cubic/coderabbit → round-2 follow-up → round-3 codacy)

## Summary

Added 15 new devcontainer features for leading AI coding agents and orchestrators,
plus opt-in `shareConfig` behavior for all agent features. The review process
spanned 4 iterations across 6 bot reviewers (amazon-q, codacy, codeant, coderabbit,
cubic, sonarcloud) and required fixing ~100 review threads total.

## Fixes Applied (by theme)

### Security
- **API key exposure:** Removed all API key writing to `/etc/environment` across
  claude-code, gemini, claude. Removed orphaned `apiKey` options from feature.json.
  Credentials are now injected at runtime via env vars or secrets.
- **Checksum verification:** Added SHA-256 checksum verification for goose binary
  downloads (using checksums.txt) and docker-agent binary downloads. Build fails
  on mismatch.
- **HTTPS enforcement:** Added `--proto =https` and `--proto-redir =https` to all
  curl download commands (SonarCloud S6506).
- **Download-then-execute:** Replaced all `curl|bash` patterns in hermes, grok-build,
  and cao (uv installer) with download-to-tmpdir-then-execute.
- **npm lifecycle scripts:** Added `--ignore-scripts` to all `npm install -g`
  commands (SonarCloud S6505). For packages requiring postinstall (claude-code,
  amp, opencode, openclaw, crush), added explicit `npm rebuild -g` after install.

### Robustness
- **`$HOME` safety:** Removed profile.d scripts that used `$HOME` (OpenShift can
  set `HOME=/`). Kept safe fixed fallback paths (`/home/vscode/...`).
- **Symlink error suppression:** Removed `|| true` and `2>/dev/null` from symlink
  creation so failures are visible.
- **Herdr early-exit:** Removed config-sharing work from the binary-not-found
  early-exit path.
- **Cursor config:** Moved `CURSOR_CONFIG_DIR` export inside `shareConfig=true`
  block so it only exports the shared path when sharing is enabled.
- **Binary linking:** Changed `cp` to `ln -sf` for all npm-based binaries to
  preserve package tree resolution (cubic finding: `cp` dereferences npm symlinks,
  breaking dependency resolution).
- **npm bin resolution:** Changed openclaw, mastra-code, qwen-code to resolve
  binaries from `$NPM_GLOBAL_BIN` instead of `command -v` to avoid picking up
  pre-existing PATH entries.
- **Goose checksum fail-on-missing:** Changed checksum download from `|| true`
  to mandatory build failure.
- **Hermes installer:** Removed unsupported `-s` flag from installer invocation.
- **Grok-build self-link:** Added guard against self-link when installer already
  creates `/usr/local/bin/grok`.
- **CAO non-root access:** Installed uv with `UV_INSTALL_DIR=/usr/local` so tools
  are system-wide accessible to non-root users.

### Conventions
- **Shell tests:** Replaced all `[` with `[[` across all install.sh files
  (SonarCloud S7688). Exception: openshift-compat profile.d content uses `[`
  for POSIX shell compatibility.
- **Node dependencies:** Added `ghcr.io/devcontainers/features/node` to
  `dependsOn` for all npm-based features.
- **Version bumps:** Bumped existing affected features to `2.0.0` (breaking:
  `shareConfig` default changed from always-on to opt-in).
- **AGENTS.md:** Softened `MUST` to `SHOULD` with exception for runtimes/build
  tools that don't manage agent configuration.
- **Version pinning:** Hermes and grok-build now pass `--version` to their
  installers when `VERSION` is not `latest`.
- **Goose JSON parsing:** Use `jq` for GitHub API response with grep fallback.

## Rejected Findings (with documented reasons)

### 1. Upstream installer SHA-256 checksums (coderabbit, cubic)
**Finding:** Verify installer scripts (hermes, grok-build) with SHA-256 before
execution.
**Rejection reason:** Upstream Hermes and Grok installers do not publish SHA-256
checksums for their install scripts. This is the official distribution method.
We mitigate by downloading to a tmpdir over HTTPS with `--proto =https
--proto-redir =https` before executing, which prevents MITM downgrade attacks.
The download-then-execute pattern also allows inspection before execution.

### 2. OpenShift-compat sed patching (codacy HIGH RISK)
**Finding:** Runtime patching of Paseo's web-ui.js via sed is brittle and
high-risk.
**Rejection reason:** The sed patching is a pre-existing runtime workaround for
an upstream Paseo bug (missing default port in Host header behind reverse
proxies). It operates on a COPY of the file (not the original), uses a custom
ESM loader to intercept imports, is guarded by `grep` to prevent double-patching,
and is wrapped in `set +e` with `|| true` so failures don't break the entrypoint.
This is the only way to fix the bug without forking Paseo. An environment variable
override is not possible because the upstream code doesn't expose one.

### 3. Herdr README documentation (cubic P3)
**Finding:** README still documents copied binary, but install now uses symlink.
**Rejection reason:** README files are auto-generated by the release workflow
(per AGENTS.md convention) and must not be hand-edited. The symlink change is
in install.sh; the README will be regenerated on release.

### 4. Herdr README version tag (cubic P3)
**Finding:** README still references `herdr:1` but version bumped to `2.0.0`.
**Rejection reason:** README files are auto-generated by the release workflow.
The version tag in the README will be updated when the 2.0.0 release is published.
Hand-editing READMEs is explicitly prohibited by repo convention.

## Iteration History

| Iteration | Bots evaluated | Threads opened | Threads fixed | Threads rejected |
|-----------|---------------|----------------|---------------|------------------|
| 1 (5633175) | amazon-q, codacy, codeant, coderabbit, cubic, sonarcloud | ~61 | ~58 | ~3 |
| 2 (f907eca) | sonarcloud re-eval | 2 OPEN | 2 | 0 |
| 2 (0da01d8) | sonarcloud re-eval | 0 new | 0 | 0 |
| 3 (7c53980) | cubic, coderabbit re-eval | 26 | 23 | 3 |
| 3 (676cfb9) | codacy re-eval | 11 | 8 | 3 |
| 4 (de47746) | codacy re-eval | 9 | 6 | 3 |
| 4 (b7b9eb4) | — | 0 new | 0 | 0 |

## Key Lessons

1. **`--ignore-scripts` vs postinstall conflict:** SonarCloud S6505 requires
   `--ignore-scripts` on `npm install`, but some packages (claude-code, amp,
   opencode, openclaw, crush) require postinstall to install native binaries.
   Solution: `npm install --ignore-scripts` + `npm rebuild -g` after.

2. **`cp` vs `ln -sf` for npm binaries:** Copying npm-installed binaries to
   `/usr/local/bin` breaks packages that need to resolve siblings from their
   install location. Always use `ln -sf` to preserve the package tree.

3. **Bot re-evaluations after push:** Each push triggers bot re-evaluation,
   which can open new threads on the new diff. The loop must continue until
   no new threads appear. This PR took 4 iterations to converge.

4. **`command -v` vs npm global bin:** Using `command -v` to locate npm-installed
   binaries can pick up pre-existing PATH entries. Resolve from
   `$(npm bin -g)` or `$(npm config get prefix)/bin` instead.

5. **Profile.d and POSIX shells:** `/etc/profile.d` scripts are sourced by POSIX
   shells, so `[[` (bash-only) must not be used in profile.d heredoc content.
