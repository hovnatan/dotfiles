# Project agent memory

.dotfiles: this file is the always-loaded memory for agents working in this repo.
It is kept short on purpose - every line here is paid on every session.

## Learnings

- `home/` mirrors `$HOME`: entries install at the same relative path under `~`
  (`home/.tmux.conf` -> `~/.tmux.conf`). Everything outside `home/` (`scripts/`,
  `claude_tmux_session/`, `nix/`, `docs/`, `.devcontainer/`, `docker/`) is repo tooling that never
  lands in `$HOME`; all executables live in `scripts/` and are invoked by
  absolute path, nothing here is on `PATH`. `scripts/setup_user_symlinks.sh` is the authoritative
  install map - add a line there when adding a file under `home/`.
  It is safe to re-run; `scripts/update.sh` (alias `dotup`) pulls and re-runs it
  to update a machine. `CONTEXT.md` holds the vocabulary (install, update, ...).
- Shell scripts must run on both macOS and Linux: macOS has BSD userland, so
  avoid GNU-only flags and commands (`sed -i` without a suffix arg, `readlink -f`,
  `date -d`, `stat -c`, `grep -P`, `timeout`) or branch on `uname`. Target bash 5 (Nix on macOS)
  via `#!/usr/bin/env bash`; never `#!/bin/bash`, which is 3.2 on macOS.
- `nix/flake.nix` is the curated CLI package list for Linux and macOS
  (pinned by `nix/flake.lock`; setup in README.md); `Brewfile` (repo root)
  holds only the Mac apps. Read the relevant header before any `nix profile`
  change or brew install, uninstall or cask adopt.
- Changing `scripts/claude_tmux_run.sh`, the claude-tmux unit or
  `home/.claude/ntfy-stop.sh`: extend `scripts/tests/` with the new behaviour.
  CI runs them on Linux and macOS (`.github/workflows/tests.yml`); locally
  they are safe beside live sessions.
- Changed fish, JSON or nvim config: `scripts/check_configs.sh` before pushing
  (CI runs it, `.github/workflows/configs.yml`).
- `home/.codex/config.toml` is linked as `~/.codex/config.toml`, and Codex and
  the ChatGPT app write machine-local state into it (model, app paths, MCP
  servers, `notify`), so it often shows as modified. Never stage or commit it
  as part of other work (no `git add -A`/`.`/`-u`, no `commit -a`); change it
  only when the user asks for that file, staging just the lines they want.
- backpass adds further evidence-backed entries here from real sessions.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
