#!/usr/bin/env bash
#
# update.sh -- bring this machine's dotfiles up to date after another machine
# pushed changes, then re-run the installer so anything new under home/ gets
# linked. Run on the machine being updated; aliased as `dotup` in
# home/.zshrc.shared.
#
#   origin/main --fetch, ff-only--> ~/.dotfiles ---------------.
#   origin/main --fetch, ff-only--> ~/.dotfiles-private (opt) --+
#                                                              v
#                                   scripts/setup_user_symlinks.sh
#                                                              v
#                              macOS only: Brewfile drift report (advisory)
#                                                              v
#                              reminders: tmux, Hammerspoon, open shells
#
# Local state on this machine, and what happens to it:
#   dirty tracked file   stashed around the pull and popped after it. A pop
#                        conflict stops the run non-zero with the stash kept
#                        and the paths listed: either side may hold the edit
#                        you want, only you know which.
#   untracked file       never touched. A pulled commit creating the same
#                        path makes git refuse, naming the path.
#   local commit         ff-only refuses. Push or rebase it yourself: it is
#                        an edit you made here and forgot to publish.
# Only published commits travel; nothing is copied machine to machine.

set -euo pipefail

# Fetch and fast-forward one repo, stashing local edits around the pull.
# Prints the pulled commit range, or one line when already current.
update_repo() {
  local dir=$1
  cd "$dir"

  # A conflicted pop from an earlier run leaves unmerged paths; git refuses
  # every step below on them, so say what is going on instead.
  if [ -n "$(git ls-files --unmerged)" ]; then
    echo "error: $dir: unresolved conflicts from an earlier run, resolve them first:" >&2
    git diff --name-only --diff-filter=U | sed 's/^/       /' >&2
    exit 1
  fi

  local old
  old=$(git rev-parse HEAD)

  local stashed=0
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    git stash push --quiet -m "dotup $(date -u +%Y%m%dT%H%M%SZ)"
    stashed=1
  fi

  # On a refused pull put the edits back where they were before reporting,
  # so a diverged branch or no network never leaves them hidden in a stash.
  if ! git pull --ff-only --quiet; then
    [ "$stashed" -eq 1 ] && git stash pop --quiet
    echo "error: $dir: pull failed; local commits not on origin (push or rebase them), or no network" >&2
    exit 1
  fi

  if [ "$stashed" -eq 1 ] && ! git stash pop --quiet; then
    echo "error: $dir: local edits conflict with the pulled changes in:" >&2
    git diff --name-only --diff-filter=U | sed 's/^/       /' >&2
    echo "       resolve them, then 'git stash drop' (the stash entry is kept)" >&2
    exit 1
  fi

  local new
  new=$(git rev-parse HEAD)
  if [ "$old" = "$new" ]; then
    echo "$dir: already up to date at ${new:0:8}"
  else
    echo "$dir: ${old:0:8}..${new:0:8}"
    git log --oneline "$old..$new" | sed 's/^/  /'
  fi
}

# Report where this Mac and the curated Brewfile disagree, both directions:
#   check    listed in the Brewfile, not installed (or brew thinks outdated)
#   cleanup  installed, not listed (dry run: without --force it removes nothing)
# Advisory only: drift is a prompt to edit the Brewfile or the machine, not a
# failed update, so neither command's "found drift" exit fails the run.
# cleanup's dry run also lists what `brew cleanup` would prune (old kegs,
# caches) - hundreds of lines of noise here, so that tail is cut off.
brew_drift() {
  command -v brew >/dev/null || {
    echo "error: brew not on PATH; install Homebrew (https://brew.sh) or fix PATH" >&2
    return 1
  }
  local file=~/.dotfiles/Brewfile
  echo "--- Brewfile drift (advisory)"
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file="$file" --verbose 2>&1 | sed 's/^/  /' || true
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle cleanup --file="$file" 2>&1 \
    | sed '/^Would `brew cleanup`/,$d' | sed 's/^/  /' || true
}

main() {
  update_repo ~/.dotfiles

  # Optional private companion repo; absent on most machines by design.
  if [ -d ~/.dotfiles-private/.git ]; then
    update_repo ~/.dotfiles-private
  fi

  # Re-install so new files under home/ get their links. Its warnings are
  # non-fatal for the install itself but make this run exit non-zero too.
  echo "--- setup_user_symlinks.sh"
  local status=0
  bash ~/.dotfiles/scripts/setup_user_symlinks.sh || status=$?

  if [ "$(uname)" = "Darwin" ]; then
    brew_drift || status=1
  fi

  # Nothing running re-reads its config on its own; say what to poke.
  echo "--- reload as needed"
  echo "  tmux:        tmux source-file ~/.tmux.conf"
  [ "$(uname)" = "Darwin" ] && echo "  hammerspoon: hs -c 'hs.reload()'"
  echo "  shells:      exec zsh"
  return "$status"
}

# The pull replaces this very file mid-run. Bash reads a script as it goes,
# so keep the call and the exit on one line: both are parsed before main
# starts and nothing is read from the file afterwards.
main "$@"; exit $?
