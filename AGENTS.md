# Project agent memory

.dotfiles: this file is the always-loaded memory for agents working in this repo.
It is kept short on purpose - every line here is paid on every session.

## Learnings

- `home/` mirrors `$HOME`: entries install at the same relative path under `~`
  (`home/.tmux.conf` -> `~/.tmux.conf`). Everything outside `home/` (`scripts/`,
  `claude_tmux_session/`, `nix/`, `apt/`, `docs/`, `.devcontainer/`, `docker/`) is repo tooling
  that never lands in `$HOME`; all executables live in `scripts/` and are invoked by
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
  holds only the Mac apps; `apt/Aptfile` holds what an Ubuntu box needs from
  apt (daemons such as docker), applied by `scripts/apt_bundle.sh`. Read the
  relevant header before any `nix profile` change, brew install, uninstall
  or cask adopt, or apt install.
- Changing `scripts/claude_tmux_run.sh`, the claude-tmux unit,
  `home/.claude/ntfy-stop.sh` or a tmux hook (`home/.config/tmux/`, the
  `set-hook` lines): extend `scripts/tests/` with the new behaviour. A new
  test needs a `# check.sh covers:` line (format in `scripts/check.sh`); it
  decides when the pre-push hook runs the test. Tests are safe beside live sessions.
- This repo is public, commit messages included. Host names, IPs, tailnet
  names and internal documents go in the private repos (`~/.dotfiles-private`
  personal, `~/.hov-dotfiles-private` work; see CONTEXT.md) or in
  machine-local state (fish universal variables, `~/.ssh/local_config`);
  tracked files and commits use placeholders (`<host>`, `vm`). Removing one
  after a push means rewriting history and force-pushing.
- `scripts/check.sh` runs every check CI runs, and the `pre-push` hook runs it on
  each pushed commit (`scripts/git-hooks/`, wired by the installer): when it stops a
  push, fix what it names and push again. `scripts/check.sh --changed <paths>` checks
  before committing. Vendored skills are ignored in `.markdownlint-cli2.yaml`:
  add a skill there when vendoring it.
- `home/.codex/config.toml` is linked as `~/.codex/config.toml`, and Codex and
  the ChatGPT app write machine-local state into it (model, app paths, MCP
  servers, `notify`), so it often shows as modified. Never stage or commit it
  as part of other work (no `git add -A`/`.`/`-u`, no `commit -a`); change it
  only when the user asks for that file, staging just the lines they want.
- Every new script or process (Hammerspoon module, hook, daemon, scheduled
  job) logs its actions to `~/.dotfiles/.logs/<UTC YYYYMMDD_HHMMSS>_<name>/events.log`,
  one directory per run or load (per UTC day for a hook that fires at every
  turn, `event_log_daily`): a UTC-timestamped line per action,
  line-buffered so the file reads mid-run. Use `scripts/lib/event_log.sh`
  (shell) or `home/.hammerspoon/event_log.lua`; `.logs` is ignored through
  `home/.config/git/ignore`. A directory holding only `events.log` is pruned
  30 days after its last write (`scripts/prune_logs.sh`), so a record worth
  keeping needs a file of another name beside it.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
